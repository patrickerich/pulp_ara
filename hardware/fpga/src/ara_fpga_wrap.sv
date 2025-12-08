// FPGA-oriented top-level for Ara SoC on AXKU5 FPGA.
// - Handles board-level clock/reset.
// - Instantiates ara_soc and the APB UART.
// - Exposes only FPGA pin-level ports (sys_clk_p/n, sys_rst_n, led, uart_tx/rx).

module ara_fpga_wrap
  import axi_pkg::*;
  import ara_pkg::*;
  import dm::*;
  import ariane_pkg::*;
#(
  // RVV Parameters
  parameter int unsigned NrLanes      = 2,
  parameter int unsigned VLEN         = 256,
  parameter int unsigned OSSupport    = 1,

  // Support for floating-point data types (FP16 only by default on FPGA)
  parameter fpu_support_e   FPUSupport   = FPUSupportHalf,
  // External support for vfrec7, vfrsqrt7
  parameter fpext_support_e FPExtSupport = FPExtSupportEnable,
  // Support for fixed-point data types
  parameter fixpt_support_e FixPtSupport = FixedPointEnable,
  // Support for segment memory operations
  parameter seg_support_e   SegSupport   = SegSupportEnable,

  // AXI Interface
  parameter int unsigned AxiDataWidth = 32*NrLanes,
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiUserWidth = 1,
  parameter int unsigned AxiIdWidth   = 5,

  // AXI Resp Delay [ps] for gate-level simulation
  parameter int unsigned AxiRespDelay = 200,

  // Main memory (smaller L2 for FPGA: 2^14 bytes per full AxiDataWidth)
  localparam int unsigned L2NumWords   = (2**14) / NrLanes
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
  // soc_rst_ni: additionally controlled by debug module ndmreset
  logic rst_ni_raw;
  logic soc_rst_ni;
  logic pll_locked_r;

  // Differential clock buffer
  IBUFDS i_sys_clk_ibufds (
    .I (sys_clk_p),
    .IB(sys_clk_n),
    .O (clk_in_200)
  );

   BUFG BUFG_inst (
      .O(clk_in_200_buf), // 1-bit output: Clock output.
      .I(clk_in_200)  // 1-bit input: Clock input.
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
  // - soc_rst_ni is further gated by ndmreset from the debug module.
  always_ff @(posedge core_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      pll_locked_r <= 1'b0;
      rst_ni_raw   <= 1'b0;
    end else begin
      pll_locked_r <= pll_locked;
      rst_ni_raw   <= pll_locked_r;
    end
  end

  // soc_rst_ni is deasserted only when the board/PLL reset is released
  // and the debug module does not hold ndmreset high.
  logic ndmreset;
  assign soc_rst_ni = rst_ni_raw & ~ndmreset;

  // ---------------------------------------------------------------------------
  // SoC control/status
  // ---------------------------------------------------------------------------
  logic [63:0] exit_o;
  logic [63:0] hw_cnt_en_o;

   // ---------------------------------------------------------------------------
   // RISC-V Debug Transport (JTAG DMI) + Debug Module (upstream riscv-dbg)
   // ---------------------------------------------------------------------------

   // Debug signals
   logic          dmactive;
   logic          debug_req;
   // ndmreset (non-debug-module reset) is used to hold the core in reset in
   // addition to the board reset/PLL lock (see soc_rst_ni above).

   // DMI handshake between dmi_jtag and dm_top
   dm::dmi_req_t  dmi_req;
   dm::dmi_resp_t dmi_resp;
   logic          dmi_req_valid, dmi_req_ready;
   logic          dmi_resp_valid, dmi_resp_ready;

   // Debug Module memory window signals (to/from ara_soc_fpga)
   logic                      dm_device_req;
   logic                      dm_device_we;
   logic [AxiAddrWidth-1:0]   dm_device_addr;
   logic [AxiDataWidth/8-1:0] dm_device_be;
   logic [AxiDataWidth-1:0]   dm_device_wdata;
   logic [AxiDataWidth-1:0]   dm_device_rdata;

   // System Bus Access (SBA) master bus signals between dm_top and ara_soc_fpga
   logic                      dm_master_req;
   logic [AxiAddrWidth-1:0]   dm_master_add;
   logic                      dm_master_we;
   logic [AxiDataWidth-1:0]   dm_master_wdata;
   logic [AxiDataWidth/8-1:0] dm_master_be;
   logic                      dm_master_gnt;
   logic                      dm_master_r_valid;
   logic [AxiDataWidth-1:0]   dm_master_r_rdata;

   // ---------------------------------------------------------------------------
   // JTAG DMI transport (upstream dmi_jtag from riscv-dbg)
   // ---------------------------------------------------------------------------
   // On AXKU5, jtag_tck comes from an HDIO bank. Vivado was inferring a BUFGCE_DIV
   // directly from that IO, which violates PLHDIO-3. Insert an explicit BUFGCE
   // so the HDIO only drives a BUFGCE, and the global clock network is driven
   // from the BUFGCE output instead of the IO pin itself.
   logic jtag_tck_buf;

   BUFGCE i_jtag_tck_bufg (
     .I  (jtag_tck),
     .CE (1'b1),
     .O  (jtag_tck_buf)
   );

   dmi_jtag #(
     .IdcodeValue (32'h2495_11C3)
   ) i_dmi_jtag (
     .clk_i            (core_clk        ),
     .rst_ni           (rst_ni_raw      ),
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

   // Debug Module core (upstream dm_top from riscv-dbg)
   logic debug_req_irq;

   dm_top #(
     .NrHarts         (1                  ),
     .BusWidth        (AxiDataWidth       ),
     .SelectableHarts (1'b1               )
   ) i_dm_top (
     .clk_i            (core_clk          ),
     .rst_ni           (rst_ni_raw        ),
     .testmode_i       (1'b0              ),
     .ndmreset_o       (ndmreset          ),
     .dmactive_o       (dmactive          ),
     .debug_req_o      ({debug_req_irq}   ),
     .unavailable_i    ('0                ),
     .hartinfo_i       ({ariane_pkg::DebugHartInfo}),

     // Debug memory device bus: connected to ara_soc_fpga DEBUG window
     .slave_req_i      (dm_device_req     ),
     .slave_we_i       (dm_device_we      ),
     .slave_addr_i     (dm_device_addr    ),
     .slave_be_i       (dm_device_be      ),
     .slave_wdata_i    (dm_device_wdata   ),
     .slave_rdata_o    (dm_device_rdata   ),

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

   // Map IRQ-style debug request to the SoC-level debug_req signal
   assign debug_req = debug_req_irq;

  // ---------------------------------------------------------------------------
  // UART APB signals between ara_soc and UART IP
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
  // Ara SoC
  // ---------------------------------------------------------------------------
  ara_soc #(
    .NrLanes      (NrLanes      ),
    .VLEN         (VLEN         ),
    .OSSupport    (OSSupport    ),
    .FPUSupport   (FPUSupport   ),
    .FPExtSupport (FPExtSupport ),
    .FixPtSupport (FixPtSupport ),
    .SegSupport   (SegSupport   ),
    .AxiDataWidth (AxiDataWidth ),
    .AxiAddrWidth (AxiAddrWidth ),
    .AxiUserWidth (AxiUserWidth ),
    .AxiIdWidth   (AxiIdWidth   ),
    .AxiRespDelay (AxiRespDelay ),
    .L2NumWords   (L2NumWords   )
  ) i_ara_soc (
    .clk_i           (core_clk        ),
    // SoC fabric + L2 SRAM reset: only from board/PLL reset.
    // This keeps SBA and memory accessible even when ndmreset is asserted.
    .rst_ni          (rst_ni_raw      ),
    // Core (CVA6+Ara) reset: gated by ndmreset via soc_rst_ni.
    .core_rst_ni_i   (soc_rst_ni      ),
    .exit_o          (exit_o          ),
    .hw_cnt_en_o     (hw_cnt_en_o     ),
    // Debug request from external Debug Module
    .debug_req_i     (debug_req       ),
    // Scan chain
    .scan_enable_i   (1'b0            ),
    .scan_data_i     (1'b0            ),
    .scan_data_o     (/* unused */    ),
    // UART APB interface
    .uart_penable_o  (uart_penable    ),
    .uart_pwrite_o   (uart_pwrite     ),
    .uart_paddr_o    (uart_paddr      ),
    .uart_psel_o     (uart_psel       ),
    .uart_pwdata_o   (uart_pwdata     ),
    .uart_prdata_i   (uart_prdata     ),
    .uart_pready_i   (uart_pready     ),
    .uart_pslverr_i  (uart_pslverr    ),
    // Debug Module memory window (DEBUG AXI slave)
    .dm_device_req_o   (dm_device_req   ),
    .dm_device_we_o    (dm_device_we    ),
    .dm_device_addr_o  (dm_device_addr  ),
    .dm_device_be_o    (dm_device_be    ),
    .dm_device_wdata_o (dm_device_wdata ),
    .dm_device_rdata_i (dm_device_rdata ),
    // System Bus Access (SBA) for full address space access
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
  // UART IP (APB slave + FIFOs) connected to board pins
  // Core clock for UART is also 50 MHz
  // ---------------------------------------------------------------------------
  uart #(
    .ClockFrequency (50_000_000),
    .BaudRate       (115200),
    .RxFifoDepth    (128),
    .TxFifoDepth    (128),
    .AddrWidth      (32),
    .DataWidth      (32)
  ) i_uart (
    .clk_i      (core_clk),
    .rst_ni     (soc_rst_ni),
    .psel_i     (uart_psel),
    .penable_i  (uart_penable),
    .pwrite_i   (uart_pwrite),
    .paddr_i    (uart_paddr),
    .pwdata_i   (uart_pwdata),
    .prdata_o   (uart_prdata),
    .pready_o   (uart_pready),
    .pslverr_o  (uart_pslverr),
    .uart_rx_i  (uart_rx),
    .uart_tx_o  (uart_tx),
    .uart_irq_o (/* unused for now */)
  );

  // ---------------------------------------------------------------------------
  // Simple LED status
  // ---------------------------------------------------------------------------
  // led[0] : shows reset (on when SoC is in reset)
  // led[1] : reflects exit flag bit 0 (tohost valid)
  // led[2] : reserved
  // led[3] : reserved
  // assign led[0] = ~soc_rst_ni;
  // assign led[1] = exit_o[0];
  // assign led[2] = pll_locked;
  // assign led[3] = 1'b0;

  // Simple LED status - DEBUG VERSION
  assign led[0] = pll_locked;      // Should be ON when PLL locks
  assign led[1] = rst_ni_raw;      // Should be ON when out of reset
  assign led[2] = dmactive;        // Should go ON when debug connected
  assign led[3] = debug_req;       // Pulses when debugger halts core

endmodule : ara_fpga_wrap