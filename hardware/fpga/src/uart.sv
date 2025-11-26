// Simple UART implementation based on LowRISC (ibex-demo-system implementation),
// adapted to Ara's APB UART interface and common_cells fifo_v3.

module uart
  #(
    parameter int unsigned ClockFrequency = 200_000_000,
    parameter int unsigned BaudRate       = 115200,
    parameter int unsigned RxFifoDepth    = 128,
    parameter int unsigned TxFifoDepth    = 128,
    parameter int unsigned AddrWidth      = 32,
    parameter int unsigned DataWidth      = 32
  ) (
    input  logic                   clk_i,
    input  logic                   rst_ni,

    // APB slave interface (to be connected to ara_soc UART APB master)
    input  logic                   psel_i,
    input  logic                   penable_i,
    input  logic                   pwrite_i,
    input  logic [AddrWidth-1:0]   paddr_i,
    input  logic [DataWidth-1:0]   pwdata_i,
    output logic [DataWidth-1:0]   prdata_o,
    output logic                   pready_o,
    output logic                   pslverr_o,

    // UART pins and interrupt
    input  logic                   uart_rx_i,
    output logic                   uart_irq_o,
    output logic                   uart_tx_o
  );

  // --------------------------------------------------------------------------
  // APB register map and types
  // --------------------------------------------------------------------------

  localparam int unsigned RegAddrWidth  = AddrWidth;
  localparam int unsigned ClocksPerBaud = ClockFrequency / BaudRate;

  localparam logic [RegAddrWidth-1:0] UartRxReg     = RegAddrWidth'('h0);
  localparam logic [RegAddrWidth-1:0] UartTxReg     = RegAddrWidth'('h4);
  localparam logic [RegAddrWidth-1:0] UartStatusReg = RegAddrWidth'('h8);

  typedef enum logic [1:0] {
    IDLE,
    START,
    PROC,
    STOP
  } uart_state_t;

  // --------------------------------------------------------------------------
  // APB decode
  // --------------------------------------------------------------------------

  logic                      apb_rd, apb_wr;
  logic [RegAddrWidth-1:0]   apb_addr;
  logic [DataWidth-1:0]      apb_wdata, apb_rdata;

  // Simple APB slave: transfer on psel_i & penable_i
  assign apb_wr    = psel_i && penable_i &&  pwrite_i;
  assign apb_rd    = psel_i && penable_i && !pwrite_i;
  assign apb_addr  = paddr_i[RegAddrWidth-1:0];
  assign apb_wdata = pwdata_i;

  // Always ready, no error for this simple UART
  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign prdata_o  = apb_rdata;

  // --------------------------------------------------------------------------
  // RX path
  // --------------------------------------------------------------------------

  logic [$clog2(ClocksPerBaud)-1:0] rx_baud_counter_q, rx_baud_counter_d;
  logic                             rx_baud_tick;

  uart_state_t rx_state_q, rx_state_d;
  logic [2:0]  rx_bit_counter_q, rx_bit_counter_d;
  logic [7:0]  rx_current_byte_q, rx_current_byte_d;
  logic [2:0]  rx_q;
  logic        rx_start, rx_valid;

  logic        rx_fifo_wvalid;
  logic        rx_fifo_rready;
  logic [7:0]  rx_fifo_rdata;
  logic        rx_fifo_empty;

  // --------------------------------------------------------------------------
  // TX path
  // --------------------------------------------------------------------------

  logic [$clog2(ClocksPerBaud)-1:0] tx_baud_counter_q, tx_baud_counter_d;
  logic                             tx_baud_tick;

  uart_state_t tx_state_q, tx_state_d;
  logic [2:0]  tx_bit_counter_q, tx_bit_counter_d;
  logic [7:0]  tx_current_byte_q, tx_current_byte_d;
  logic        tx_next_byte;

  logic        tx_fifo_wvalid;
  logic        tx_fifo_rvalid, tx_fifo_rready;
  logic [7:0]  tx_fifo_rdata;
  logic        tx_fifo_full;
  logic        tx_fifo_empty;

  // --------------------------------------------------------------------------
  // APB register access
  // --------------------------------------------------------------------------

  always_comb begin
    apb_rdata      = '0;
    rx_fifo_rready = 1'b0;

    if (apb_rd) begin
      unique case (apb_addr)
        UartRxReg: begin
          apb_rdata      = {(DataWidth-8)'('0), rx_fifo_rdata};
          rx_fifo_rready = 1'b1;
        end
        UartTxReg: begin
          apb_rdata = '0; // TX register is write-only
        end
        UartStatusReg: begin
          apb_rdata = {(DataWidth-2)'('0), tx_fifo_full, rx_fifo_empty};
        end
        default: begin
          apb_rdata = '0;
        end
      endcase
    end
  end

  assign tx_fifo_wvalid = (apb_addr == UartTxReg) & apb_wr;

  // --------------------------------------------------------------------------
  // RX baud generator and state machine
  // --------------------------------------------------------------------------

  assign rx_fifo_wvalid = rx_baud_tick & rx_valid;

  // Set the rx_baud_counter half-way on rx_start to sample bits in the middle
  assign rx_baud_counter_d = rx_baud_tick ? '0                                            :
                             rx_start     ? $bits(rx_baud_counter_q)'(ClocksPerBaud >> 1) :
                                            rx_baud_counter_q + 1'b1;

  assign rx_baud_tick = rx_baud_counter_q == $bits(rx_baud_counter_q)'(ClocksPerBaud - 1);

  // Synchronize RX and derive rx_start signal
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_q <= '0;
    end else begin
      rx_q <= {rx_q[1:0], uart_rx_i};
    end
  end

  assign rx_start = !rx_q[1] & rx_q[2] & (rx_state_q == IDLE);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_baud_counter_q <= '0;
    end else begin
      rx_baud_counter_q <= rx_baud_counter_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_state_q        <= IDLE;
      rx_bit_counter_q  <= '0;
      rx_current_byte_q <= '0;
    // Transition the rx state on both rx_start and an rx_baud_tick
    end else if (rx_start || rx_baud_tick) begin
      rx_state_q        <= rx_state_d;
      rx_bit_counter_q  <= rx_bit_counter_d;
      rx_current_byte_q <= rx_current_byte_d;
    end
  end

  always_comb begin
    rx_valid          = 1'b0;
    rx_bit_counter_d  = rx_bit_counter_q;
    rx_current_byte_d = rx_current_byte_q;
    rx_state_d        = rx_state_q;

    unique case (rx_state_q)
      IDLE: begin
        if (rx_start) begin
          rx_state_d = START;
        end
      end
      START: begin
        rx_current_byte_d = '0;
        rx_bit_counter_d  = '0;
        if (!rx_q[2]) begin
          rx_state_d = PROC;
        end else begin
          rx_state_d = IDLE;
        end
      end
      PROC: begin
        rx_current_byte_d = {rx_q[2], rx_current_byte_q[7:1]};
        if (rx_bit_counter_q == 3'd7) begin
          rx_state_d = STOP;
        end else begin
          rx_bit_counter_d = rx_bit_counter_q + 3'd1;
        end
      end
      STOP: begin
        if (rx_q[2]) begin
          rx_valid = 1'b1;
        end
        rx_state_d = IDLE;
      end
      default: begin
      end
    endcase
  end

  // --------------------------------------------------------------------------
  // TX baud generator and state machine
  // --------------------------------------------------------------------------

  assign tx_fifo_rready    = tx_baud_tick & tx_next_byte;
  assign tx_baud_counter_d = tx_baud_tick ? '0 : tx_baud_counter_q + 1'b1;
  assign tx_baud_tick      = tx_baud_counter_q == $bits(tx_baud_counter_q)'(ClocksPerBaud - 1);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tx_baud_counter_q <= '0;
    end else begin
      tx_baud_counter_q <= tx_baud_counter_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tx_state_q        <= IDLE;
      tx_bit_counter_q  <= '0;
      tx_current_byte_q <= '0;
    end else if (tx_baud_tick) begin
      tx_state_q        <= tx_state_d;
      tx_bit_counter_q  <= tx_bit_counter_d;
      tx_current_byte_q <= tx_current_byte_d;
    end
  end

  always_comb begin
    uart_tx_o         = 1'b0;
    tx_bit_counter_d  = tx_bit_counter_q;
    tx_current_byte_d = tx_current_byte_q;
    tx_next_byte      = 1'b0;
    tx_state_d        = tx_state_q;

    unique case (tx_state_q)
      IDLE: begin
        uart_tx_o = 1'b1;
        if (tx_fifo_rvalid) begin
          tx_state_d = START;
        end
      end
      START: begin
        uart_tx_o         = 1'b0;
        tx_state_d        = PROC;
        tx_bit_counter_d  = 3'd0;
        tx_current_byte_d = tx_fifo_rdata;
        tx_next_byte      = 1'b1;
      end
      PROC: begin
        uart_tx_o         = tx_current_byte_q[0];
        tx_current_byte_d = {1'b0, tx_current_byte_q[7:1]};
        if (tx_bit_counter_q == 3'd7) begin
          tx_state_d = STOP;
        end else begin
          tx_bit_counter_d = tx_bit_counter_q + 3'd1;
        end
      end
      STOP: begin
        uart_tx_o = 1'b1;
        if (tx_fifo_rvalid) begin
          tx_state_d = START;
        end else begin
          tx_state_d = IDLE;
        end
      end
      default: begin
      end
    endcase
  end

  // --------------------------------------------------------------------------
  // FIFOs using common_cells fifo_v3
  // --------------------------------------------------------------------------

  fifo_v3 #(
    .FALL_THROUGH (1'b0),
    .DATA_WIDTH   (8),
    .DEPTH        (RxFifoDepth),
    .dtype        (logic [7:0])
  ) u_rx_fifo (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .full_o     (/* unused */),
    .empty_o    (rx_fifo_empty),
    .usage_o    (/* unused */),
    .data_i     (rx_current_byte_q),
    .push_i     (rx_fifo_wvalid),
    .data_o     (rx_fifo_rdata),
    .pop_i      (rx_fifo_rready)
  );

  fifo_v3 #(
    .FALL_THROUGH (1'b0),
    .DATA_WIDTH   (8),
    .DEPTH        (TxFifoDepth),
    .dtype        (logic [7:0])
  ) u_tx_fifo (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .full_o     (tx_fifo_full),
    .empty_o    (tx_fifo_empty),
    .usage_o    (/* unused */),
    .data_i     (apb_wdata[7:0]),
    .push_i     (tx_fifo_wvalid),
    .data_o     (tx_fifo_rdata),
    .pop_i      (tx_fifo_rready)
  );

  assign tx_fifo_rvalid = ~tx_fifo_empty;
  assign uart_irq_o     = ~rx_fifo_empty;

endmodule
