// FPGA-oriented top-level for CVA6-only SoC on AXKU5 FPGA.
// Stripped-down counterpart of [ara_fpga_wrap](hardware/fpga/src/ara_fpga_wrap.sv:6):
// - Handles board-level clock/reset
// - Instantiates cva6_soc (CVA6-only SoC) and the APB UART
// - Instantiates upstream riscv-dbg (dmi_jtag + dm_top) for OpenOCD/GDB access
// - Exposes only FPGA pin-level ports (sys_clk_p/n, sys_rst_n, led, uart_tx/rx, JTAG)

module cva6_fpga_wrap
  import axi_pkg::*;
  import ara_pkg::*;
  import dm::*;
  import ariane_pkg::*;
#(
  // AXI Interface (SoC-wide)
  parameter int unsigned AxiDataWidth = 64,
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiUserWidth = 1,
  parameter int unsigned AxiIdWidth   = 5,

  // AXI Resp Delay [ps] for gate-level simulation
  parameter int unsigned AxiRespDelay = 200,

  // Main memory (BRAM-backed): match upstream CVA6 reference project size (512 KiB)
  localparam int unsigned L2NumWords = 2**16  // 65536 words * 8 bytes/word = 512 KiB
) (
  // Board-level clock and reset (match axku5.xdc)
  input  logic        sys_clk_p,
  input  logic        sys_clk_n,
  input  logic        sys_rst_n,

  // Board LEDs
  output logic [3:0]  led,

  // Board UART pins
  output logic        uart_tx,
  input  logic        uart_rx,

  // External JTAG pod (separate from Xilinx configuration JTAG)
  input  logic        jtag_tck,
  input  logic        jtag_tms,
  input  logic        jtag_trst_n,
  input  logic        jtag_tdi,
  output logic        jtag_tdo
);

  // ---------------------------------------------------------------------------
  // Clocking
  // - Differential 200 MHz input clock from AXKU5 board
  // - PLLE2 used to generate a 50 MHz core clock
  // ---------------------------------------------------------------------------
  logic clk_in_200;
  logic clk_in_200_buf;
  logic core_clk_raw;
  logic core_clk;
  logic pll_clkfb;
  logic pll_locked;
  // rst_ni_raw: board/PLL reset
  // core_rst_ni: additionally controlled by debug module ndmreset
  logic rst_ni_raw;
  logic core_rst_ni;
  logic pll_locked_r;

  // Differential clock buffer
  IBUFDS i_sys_clk_ibufds (
    .I (sys_clk_p),
    .IB(sys_clk_n),
    .O (clk_in_200)
  );

  BUFG i_sys_clk_bufg (
    .O(clk_in_200_buf),
    .I(clk_in_200)
  );

  // PLL: 200 MHz -> 1 GHz (VCO) -> 50 MHz (CLKOUT0)
  PLLE2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT(5),   // 200 MHz * 5 = 1000 MHz VCO
    .CLKIN1_PERIOD(5.0), // 200 MHz input
    .CLKOUT0_DIVIDE(20), // 1000 MHz / 20 = 50 MHz
    .DIVCLK_DIVIDE(1),
    .STARTUP_WAIT("FALSE")
  ) i_pll (
    .CLKOUT0(core_clk_raw),
    .CLKOUT1(),
    .CLKOUT2(),
    .CLKOUT3(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKFBOUT(pll_clkfb),
    .LOCKED(pll_locked),
    .CLKIN1(clk_in_200_buf),
    .PWRDWN(1'b0),
    .RST(1'b0),
    .CLKFBIN(pll_clkfb)
  );

  // Global buffer for core clock
  BUFG i_core_clk_bufg (
    .I(core_clk_raw),
    .O(core_clk)
  );

  // Reset generation:
  // - Use board sys_rst_n (active-low) and PLL lock to release rst_ni_raw.
  always_ff @(posedge core_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      pll_locked_r <= 1'b0;
      rst_ni_raw   <= 1'b0;
    end else begin
      pll_locked_r <= pll_locked;
      rst_ni_raw   <= pll_locked_r;
    end
  end

  // ---------------------------------------------------------------------------
  // RISC-V Debug Transport (JTAG DMI) + Debug Module (upstream riscv-dbg)
  // ---------------------------------------------------------------------------

  // Debug signals
  logic dmactive;
  logic debug_req;
  logic ndmreset;
  logic ndmreset_n;

  // DMI handshake between dmi_jtag and dm_top
  dm::dmi_req_t  dmi_req;
  dm::dmi_resp_t dmi_resp;
  logic          dmi_req_valid, dmi_req_ready;
  logic          dmi_resp_valid, dmi_resp_ready;

  // Debug Module memory window signals (to/from cva6_soc_fpga)
  logic                      dm_device_req;
  logic                      dm_device_we;
  logic [AxiAddrWidth-1:0]   dm_device_addr;
  logic [AxiDataWidth/8-1:0] dm_device_be;
  logic [AxiDataWidth-1:0]   dm_device_wdata;
  logic [AxiDataWidth-1:0]   dm_device_rdata;

  // SBA master bus signals between dm_top and cva6_soc_fpga
  logic                      dm_master_req;
  logic [AxiAddrWidth-1:0]   dm_master_add;
  logic                      dm_master_we;
  logic [AxiDataWidth-1:0]   dm_master_wdata;
  logic [AxiDataWidth/8-1:0] dm_master_be;
  logic                      dm_master_gnt;
  logic                      dm_master_r_valid;
  logic [AxiDataWidth-1:0]   dm_master_r_rdata;

  // SoC SBA host interface
  logic                      dm_host_req;
  logic                      dm_host_we;
  logic [AxiAddrWidth-1:0]   dm_host_addr;
  logic [AxiDataWidth/8-1:0] dm_host_be;
  logic [AxiDataWidth-1:0]   dm_host_wdata;
  logic                      dm_host_gnt;
  logic                      dm_host_r_valid;
  logic [AxiDataWidth-1:0]   dm_host_r_rdata;

  // Core reset gating with ndmreset (use the same strategy as upstream CVA6 FPGA)
  rstgen i_rstgen_core (
    .clk_i       ( core_clk              ),
    .rst_ni      ( rst_ni_raw & ~ndmreset ),
    .test_mode_i ( 1'b0                  ),
    .rst_no      ( ndmreset_n             ),
    .init_no     (                        )
  );
  assign core_rst_ni = ndmreset_n;

  // JTAG clock buffer (HDIO -> BUFGCE to avoid PLHDIO-3)
  logic jtag_tck_buf;
  BUFGCE i_jtag_tck_bufg (
    .I  (jtag_tck),
    .CE (1'b1),
    .O  (jtag_tck_buf)
  );

  dmi_jtag #(
    // Match the OpenHW CVA6 reference design default IDCODE so that
    // the same OpenOCD configuration (fpga/scripts/openocd.cfg) can
    // be reused without changes.
    .IdcodeValue (32'h0000_0001)
  ) i_dmi_jtag (
    .clk_i            (core_clk        ),
    .rst_ni           (rst_ni_raw       ),
    .testmode_i       (1'b0            ),

    .dmi_rst_no       (/* unused */    ),
    .dmi_req_o        (dmi_req         ),
    .dmi_req_valid_o  (dmi_req_valid   ),
    .dmi_req_ready_i  (dmi_req_ready   ),
    .dmi_resp_i       (dmi_resp        ),
    .dmi_resp_ready_o (dmi_resp_ready  ),
    .dmi_resp_valid_i (dmi_resp_valid  ),

    .tck_i            (jtag_tck_buf    ),
    .tms_i            (jtag_tms        ),
    .trst_ni          (jtag_trst_n     ),
    .td_i             (jtag_tdi        ),
    .td_o             (jtag_tdo        ),
    .tdo_oe_o         (/* unused */    )
  );

  logic debug_req_irq;

  dm_top #(
    .NrHarts         (1            ),
    .BusWidth        (AxiDataWidth ),
    // Match upstream reference: do not override DmBaseAddress here (defaults to 0x1000 in dm_top).
    .SelectableHarts (1'b1         )
  ) i_dm_top (
    .clk_i            (core_clk        ),
    .rst_ni           (rst_ni_raw       ),
    .testmode_i       (1'b0            ),
    .ndmreset_o       (ndmreset        ),
    .dmactive_o       (dmactive        ),
    .debug_req_o      ({debug_req_irq} ),
    .unavailable_i    ('0              ),
    .hartinfo_i       ({ariane_pkg::DebugHartInfo}),

    // Debug memory device bus: connected to cva6_soc DEBUG window
    .slave_req_i      (dm_device_req   ),
    .slave_we_i       (dm_device_we    ),
    .slave_addr_i     (dm_device_addr  ),
    .slave_be_i       (dm_device_be    ),
    .slave_wdata_i    (dm_device_wdata ),
    .slave_rdata_o    (dm_device_rdata ),

    // System Bus Access (SBA) master bus: full address space access
    .master_req_o     (dm_master_req     ),
    .master_add_o     (dm_master_add     ),
    .master_we_o      (dm_master_we      ),
    .master_wdata_o   (dm_master_wdata   ),
    .master_be_o      (dm_master_be      ),
    .master_gnt_i     (dm_master_gnt     ),
    .master_r_valid_i (dm_master_r_valid ),
    .master_r_rdata_i (dm_master_r_rdata ),

    // DMI from JTAG
    .dmi_rst_ni       (rst_ni_raw        ),
    .dmi_req_valid_i  (dmi_req_valid     ),
    .dmi_req_ready_o  (dmi_req_ready     ),
    .dmi_req_i        (dmi_req           ),
    .dmi_resp_valid_o (dmi_resp_valid    ),
    .dmi_resp_ready_i (dmi_resp_ready    ),
    .dmi_resp_o       (dmi_resp          )
  );

  assign debug_req = debug_req_irq;

  // dm_top (SBA) <-> SoC SBA host interface (1:1)
  assign dm_host_req        = dm_master_req;
  assign dm_host_we         = dm_master_we;
  assign dm_host_addr       = dm_master_add;
  assign dm_host_be         = dm_master_be;
  assign dm_host_wdata      = dm_master_wdata;
  assign dm_master_gnt      = dm_host_gnt;
  assign dm_master_r_valid  = dm_host_r_valid;
  assign dm_master_r_rdata  = dm_host_r_rdata;

  // ---------------------------------------------------------------------------
  // UART APB signals between SoC and UART IP
  // ---------------------------------------------------------------------------
  logic        uart_penable;
  logic        uart_pwrite;
  logic [31:0] uart_paddr;
  logic        uart_psel;
  logic [31:0] uart_pwdata;
  logic [31:0] uart_prdata;
  logic        uart_pready;
  logic        uart_pslverr;

  // ---------------------------------------------------------------------------
  // CVA6 SoC (CVA6-only)
  // ---------------------------------------------------------------------------
  logic [63:0] exit_o;
  logic [63:0] hw_cnt_en_o;

  cva6_soc #(
    .AxiDataWidth (AxiDataWidth ),
    .AxiAddrWidth (AxiAddrWidth ),
    .AxiUserWidth (AxiUserWidth ),
    .AxiIdWidth   (AxiIdWidth   ),
    .AxiRespDelay (AxiRespDelay ),
    .L2NumWords   (L2NumWords   )
  ) i_cva6_soc (
    .clk_i           (core_clk      ),
    // SoC fabric + L2 SRAM reset: only from board/PLL reset (not gated by ndmreset).
    .rst_ni          (rst_ni_raw    ),
    // CVA6 core reset: gated by ndmreset.
    .core_rst_ni_i   (core_rst_ni   ),
    .exit_o          (exit_o        ),
    .hw_cnt_en_o     (hw_cnt_en_o   ),
    .debug_req_i     (debug_req     ),
    .scan_enable_i   (1'b0          ),
    .scan_data_i     (1'b0          ),
    .scan_data_o     (/* unused */  ),

    // UART APB
    .uart_penable_o  (uart_penable  ),
    .uart_pwrite_o   (uart_pwrite   ),
    .uart_paddr_o    (uart_paddr    ),
    .uart_psel_o     (uart_psel     ),
    .uart_pwdata_o   (uart_pwdata   ),
    .uart_prdata_i   (uart_prdata   ),
    .uart_pready_i   (uart_pready   ),
    .uart_pslverr_i  (uart_pslverr  ),

    // Debug window
    .dm_device_req_o   (dm_device_req   ),
    .dm_device_we_o    (dm_device_we    ),
    .dm_device_addr_o  (dm_device_addr  ),
    .dm_device_be_o    (dm_device_be    ),
    .dm_device_wdata_o (dm_device_wdata ),
    .dm_device_rdata_i (dm_device_rdata ),

    // SBA host
    .sba_req_i         (dm_host_req     ),
    .sba_we_i          (dm_host_we      ),
    .sba_addr_i        (dm_host_addr    ),
    .sba_be_i          (dm_host_be      ),
    .sba_wdata_i       (dm_host_wdata   ),
    .sba_gnt_o         (dm_host_gnt     ),
    .sba_r_valid_o     (dm_host_r_valid ),
    .sba_r_rdata_o     (dm_host_r_rdata )
  );

  // ---------------------------------------------------------------------------
  // UART: reuse upstream OpenHW APB UART IP (as in ariane_peripherals)
  // ---------------------------------------------------------------------------
  apb_uart i_apb_uart (
    .CLK     ( core_clk        ),
    .RSTN    ( core_rst_ni      ),
    .PSEL    ( uart_psel       ),
    .PENABLE ( uart_penable    ),
    .PWRITE  ( uart_pwrite     ),
    .PADDR   ( uart_paddr[4:2] ),
    .PWDATA  ( uart_pwdata     ),
    .PRDATA  ( uart_prdata     ),
    .PREADY  ( uart_pready     ),
    .PSLVERR ( uart_pslverr    ),
    .INT     ( /* unused */    ),
    .OUT1N   (                 ),
    .OUT2N   (                 ),
    .RTSN    (                 ),
    .DTRN    (                 ),
    .CTSN    ( 1'b0            ),
    .DSRN    ( 1'b0            ),
    .DCDN    ( 1'b0            ),
    .RIN     ( 1'b0            ),
    .SIN     ( uart_rx         ),
    .SOUT    ( uart_tx         )
  );

  // ---------------------------------------------------------------------------
  // Simple LED status - bring-up probes
  //   led[0] : PLL locked
  //   led[1] : core reset released (core_rst_ni / ndmreset_n)
  //   led[2] : dmactive (DMCONTROL.dmactive set by debugger)
  //   led[3] : debug_req (halt request line driven towards CVA6)
  // ---------------------------------------------------------------------------
  assign led[0] = pll_locked;
  assign led[1] = core_rst_ni;
  assign led[2] = dmactive;
  assign led[3] = debug_req;

endmodule : cva6_fpga_wrap