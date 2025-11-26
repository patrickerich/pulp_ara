// Simple bare-metal UART "hello world" for Ara SoC on FPGA.

#include <stdint.h>

#define UART_BASE        0xC0000000UL
#define UART_RX_REG      (UART_BASE + 0x0)
#define UART_TX_REG      (UART_BASE + 0x4)
#define UART_STATUS_REG  (UART_BASE + 0x8)

// UART status register layout (from hardware/fpga/src/uart.sv):
// bit 1: tx_fifo_full
// bit 0: rx_fifo_empty

static inline void uart_putc(char c)
{
    volatile uint32_t *status = (volatile uint32_t *)UART_STATUS_REG;
    volatile uint32_t *tx     = (volatile uint32_t *)UART_TX_REG;

    // Wait while TX FIFO is full (bit 1 set)
    while (*status & (1u << 1)) {
        // spin
    }

    *tx = (uint32_t)(uint8_t)c;
}

int main(void)
{
    const char msg[] = "hello world\n";

    for (unsigned i = 0; msg[i] != '\0'; ++i) {
        uart_putc(msg[i]);
    }

    // Spin forever after printing
    while (1) {
        // could later add WFI or low-power hint here
    }

    return 0;
}