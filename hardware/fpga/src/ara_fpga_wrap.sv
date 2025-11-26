// FPGA-oriented top-level for Ara SoC on AXKU5 FPGA.
// - Handles board-level clock/reset.
// - Instantiates ara_soc and the APB UART.
// - Exposes only FPGA pin-level ports (sys_clk_p/n, sys_rst_n, led, uart_tx/rx).

module ara_fpga_wrap
  import axi_pkg::*;
  import ara_pkg::*;
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
  logic core_clk_raw;
  logic core_clk;
  logic pll_clkfb;
  logic pll_locked;
  logic rst_ni;
  logic pll_locked_r;

  // Differential clock buffer
  IBUFDS i_sys_clk_ibufds (
    .I (sys_clk_p),
    .IB(sys_clk_n),
    .O (clk_in_200)
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
    .CLKIN1(clk_in_200),
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
  // - Use board sys_rst_n (active-low) and PLL lock to release rst_ni.
  always_ff @(posedge core_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      pll_locked_r <= 1'b0;
      rst_ni       <= 1'b0;
    end else begin
      pll_locked_r <= pll_locked;
      rst_ni       <= pll_locked_r;
    end
  end

  // ---------------------------------------------------------------------------
  // SoC control/status
  // ---------------------------------------------------------------------------
  logic [63:0] exit_o;
  logic [63:0] hw_cnt_en_o;

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
    .clk_i         (core_clk      ),
    .rst_ni        (rst_ni        ),
    .exit_o        (exit_o        ),
    .hw_cnt_en_o   (hw_cnt_en_o   ),
    // No external scan chain on FPGA
    .scan_enable_i (1'b0          ),
    .scan_data_i   (1'b0          ),
    .scan_data_o   (/* unused */  ),
    // UART APB interface
    .uart_penable_o(uart_penable  ),
    .uart_pwrite_o (uart_pwrite   ),
    .uart_paddr_o  (uart_paddr    ),
    .uart_psel_o   (uart_psel     ),
    .uart_pwdata_o (uart_pwdata   ),
    .uart_prdata_i (uart_prdata   ),
    .uart_pready_i (uart_pready   ),
    .uart_pslverr_i(uart_pslverr  )
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
    .rst_ni     (rst_ni),
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
  // led[0] : shows reset (on when in reset)
  // led[1] : reflects exit flag bit 0 (tohost valid)
  // led[2] : reserved
  // led[3] : reserved
  assign led[0] = ~rst_ni;
  assign led[1] = exit_o[0];
  assign led[2] = 1'b0;
  assign led[3] = 1'b0;

endmodule : ara_fpga_wrap