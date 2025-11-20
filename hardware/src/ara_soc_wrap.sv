// Simple wrapper around ara_soc that exposes the same parameters and ports,
// but lets you choose different default parameter values (e.g. FPUSupport).

module ara_soc_wrap
  import axi_pkg::*;
  import ara_pkg::*;
#(
  // RVV Parameters
  parameter int unsigned NrLanes      = 2,
  parameter int unsigned VLEN         = 256,
  parameter int unsigned OSSupport    = 1,

  // Support for floating-point data types
  parameter fpu_support_e   FPUSupport   = FPUSupportHalfSingleDouble,
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

  // Main memory
  parameter int unsigned L2NumWords   = (2**22) / NrLanes
)(
  input  logic        clk_i,
  input  logic        rst_ni,
  output logic [63:0] exit_o,
  output logic [63:0] hw_cnt_en_o,
  // Scan chain
  input  logic        scan_enable_i,
  input  logic        scan_data_i,
  output logic        scan_data_o,
  // UART APB interface
  output logic        uart_penable_o,
  output logic        uart_pwrite_o,
  output logic [31:0] uart_paddr_o,
  output logic        uart_psel_o,
  output logic [31:0] uart_pwdata_o,
  input  logic [31:0] uart_prdata_i,
  input  logic        uart_pready_i,
  input  logic        uart_pslverr_i
);

  // Direct instantiation of ara_soc, passing through all parameters and ports.
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
    .clk_i         (clk_i         ),
    .rst_ni        (rst_ni        ),
    .exit_o        (exit_o        ),
    .hw_cnt_en_o   (hw_cnt_en_o   ),
    .scan_enable_i (scan_enable_i ),
    .scan_data_i   (scan_data_i   ),
    .scan_data_o   (scan_data_o   ),
    .uart_penable_o(uart_penable_o),
    .uart_pwrite_o (uart_pwrite_o ),
    .uart_paddr_o  (uart_paddr_o  ),
    .uart_psel_o   (uart_psel_o   ),
    .uart_pwdata_o (uart_pwdata_o ),
    .uart_prdata_i (uart_prdata_i ),
    .uart_pready_i (uart_pready_i ),
    .uart_pslverr_i(uart_pslverr_i)
  );

endmodule : ara_soc_wrap