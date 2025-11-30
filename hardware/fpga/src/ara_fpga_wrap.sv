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
  input  logic        uart_rx
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
   // RISC-V Debug Module (dm_top)
   // ---------------------------------------------------------------------------

   // Debug signals
   logic          dmactive;
   logic          debug_req;
   // We use ndmreset (non-debug-module reset) to reset the SoC
   // in addition to the board reset/PLL lock (see soc_rst_ni above).

   // Debug Module memory window signals (to/from ara_soc)
   logic                      dm_device_req;
   logic                      dm_device_we;
   logic [AxiAddrWidth-1:0]   dm_device_addr;
   logic [AxiDataWidth/8-1:0] dm_device_be;
   logic [AxiDataWidth-1:0]   dm_device_wdata;
   logic [AxiDataWidth-1:0]   dm_device_rdata;

   // Debug Module (no SBA host wired for now; memory access goes via
   // execution-based debug through the debug memory window)
   dm_top #(
     .NrHarts     (1             ),
     .IdcodeValue (32'h2495_11C3 ),
     .BusWidth    (64            )
   ) i_dm_top (
     .clk_i          (core_clk        ),
     .rst_ni         (rst_ni_raw      ),
     .testmode_i     (1'b0            ),
     .ndmreset_o     (ndmreset        ),
     .dmactive_o     (dmactive        ),
     .debug_req_o    ({debug_req}     ),
     .unavailable_i  ('0              ),

     // Debug memory device bus: connected to ara_soc DEBUG window
     .device_req_i   (dm_device_req   ),
     .device_we_i    (dm_device_we    ),
     .device_addr_i  (dm_device_addr  ),
     .device_be_i    (dm_device_be    ),
     .device_wdata_i (dm_device_wdata ),
     .device_rdata_o (dm_device_rdata ),

     // System Bus Access (SBA) host bus (unused for now)
     .host_req_o     (/* unused */    ),
     .host_add_o     (/* unused */    ),
     .host_we_o      (/* unused */    ),
     .host_wdata_o   (/* unused */    ),
     .host_be_o      (/* unused */    ),
     .host_gnt_i     (1'b0            ),
     .host_r_valid_i (1'b0            ),
     .host_r_rdata_i ('0              ),

     // JTAG pads (not used when BSCANE2-based DTM is present)
     .tck_i          (1'b0            ),
     .tms_i          (1'b0            ),
     .trst_ni        (1'b1            ),
     .td_i           (1'b0            ),
     .td_o           (/* unused */    )
   );

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
    .rst_ni          (soc_rst_ni      ),
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
    .dm_device_rdata_i (dm_device_rdata )
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