#include <stdint.h>

#define UART_BASE        0xC0000000UL
#define UART_RX_REG      (UART_BASE + 0x0)
#define UART_TX_REG      (UART_BASE + 0x4)
#define UART_STATUS_REG  (UART_BASE + 0x8)

// Chosen marker address in L2 (must be in the 0x8000_0000.. region).
#define MARKER_ADDR      ((volatile uint32_t *)0x80001000UL)

static inline void uart_putc(char c)
{
    volatile uint32_t *status = (volatile uint32_t *)UART_STATUS_REG;
    volatile uint32_t *tx     = (volatile uint32_t *)UART_TX_REG;

    while (*status & (1u << 1)) {
        // spin while TX FIFO full
    }

    *tx = (uint32_t)(uint8_t)c;
}

int main(void)
{
    const char msg[] = "hello world\n";

    // Write a marker before printing
    *MARKER_ADDR = 0xDEADBEEF;

    for (unsigned i = 0; msg[i] != '\0'; ++i) {
        uart_putc(msg[i]);
    }

    while (1) {
        // stay here
    }

    return 0;
}
