#include <stdint.h>

extern char fake_uart;

// UART hardware implementation for FPGA/EMU targets
#ifdef UART_OUTPUT

#define UART_BASE      0xC0000000UL

/* Register offsets (byte offsets from UART_BASE) matching apb_uart PADDR[4:2] */
#define UART_RBR       0x00u  /* Receive Buffer Register   (read,  DLAB=0) */
#define UART_THR       0x00u  /* Transmit Holding Register (write, DLAB=0) */
#define UART_DLL       0x00u  /* Divisor Latch Low         (DLAB=1)        */
#define UART_IER       0x04u  /* Interrupt Enable          (DLAB=0)        */
#define UART_DLM       0x04u  /* Divisor Latch High        (DLAB=1)        */
#define UART_FCR       0x08u  /* FIFO Control (write)                     */
#define UART_LCR       0x0Cu  /* Line Control Register                    */
#define UART_MCR       0x10u  /* Modem Control Register                   */
#define UART_LSR       0x14u  /* Line Status Register                     */
#define UART_MSR       0x18u  /* Modem Status Register                    */
#define UART_SCR       0x1Cu  /* Scratch Register                         */

/* LSR bits */
#define UART_LSR_THRE  0x20u  /* Transmit-hold-register empty (bit 5) */

/* AXKU5: core/peripheral clock is 50 MHz (via PLLE2, see ariane_xilinx AXKU5 path) */
#define UART_CLK_HZ    50000000u
#define UART_BAUD      115200u

static inline void uart_write_reg(uint32_t offset, uint8_t value)
{
    volatile uint8_t *reg = (volatile uint8_t *)(UART_BASE + offset);
    *reg = value;
}

static inline uint8_t uart_read_reg(uint32_t offset)
{
    volatile uint8_t *reg = (volatile uint8_t *)(UART_BASE + offset);
    return *reg;
}

/* Program divisor, FIFO, and 8N1 format */
void uart_init(void)
{
    /* Divisor = UART_CLK_HZ / (16 * baud) */
    uint32_t divisor = (UART_CLK_HZ + (16u * UART_BAUD) / 2u) / (16u * UART_BAUD);
    uint8_t dll = (uint8_t)(divisor & 0xFFu);
    uint8_t dlm = (uint8_t)((divisor >> 8) & 0xFFu);

    /* Set DLAB=1 to access DLL/DLM */
    uart_write_reg(UART_LCR, 0x80u);      /* DLAB=1, rest 0 */

    /* Program divisor for ~115200 baud */
    uart_write_reg(UART_DLL, dll);
    uart_write_reg(UART_DLM, dlm);

    /* 8 data bits, 1 stop, no parity, DLAB=0 => LCR = 0b0000_0011 */
    uart_write_reg(UART_LCR, 0x03u);

    /* Enable FIFOs and clear RX/TX FIFOs: FCR[0]=1, [1]=1 (RX reset), [2]=1 (TX reset) => 0x07 */
    uart_write_reg(UART_FCR, 0x07u);
}

static inline void uart_putc(char c)
{
    /* Wait until transmitter is ready (THR empty) */
    while ((uart_read_reg(UART_LSR) & UART_LSR_THRE) == 0u) {
        /* spin */
    }

    uart_write_reg(UART_THR, (uint8_t)c);
}

void _putchar(char character) {
    if (character == '\n') {
        /* Convert LF to CRLF for terminals */
        uart_putc('\r');
    }
    uart_putc(character);
}

#else
// Default implementation for simulation
void _putchar(char character) {
  // send char to console
  fake_uart = character;
}
#endif