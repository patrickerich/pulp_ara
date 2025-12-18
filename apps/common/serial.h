#ifndef _SERIAL_H_
#define _SERIAL_H_

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Initialize UART for printf output
 *
 * This function is automatically called from crt0.S startup code
 * before main() when UART_OUTPUT is defined during compilation.
 *
 * To enable UART output for any application, compile with:
 *   -DUART_OUTPUT
 *
 * When enabled, all printf() calls will be redirected to the
 * hardware UART at 0xC0000000 (115200 baud, 8N1).
 *
 * When disabled, printf() output goes to fake_uart for simulation.
 */
void uart_init(void);

#ifdef __cplusplus
}
#endif

#endif // _SERIAL_H_
