# ==============================================================================
# AXKU5 Board - Minimal Vivado XDC for Ara FPGA Bring-up
# Device: XCKU5P-FFVB676-2I
#
# This file is derived from axku5_template.xdc but only keeps the signals
# relevant for an initial Ara-on-FPGA bring-up:
#   - One system differential clock (sys_clk_p/n)
#   - System reset pushbutton (sys_rst_n)
#   - 4 user LEDs (led[3:0])
#   - UART TX/RX (uart_tx, uart_rx)
# ==============================================================================

# ==============================================================================
# System Reference Clock (200 MHz differential clock on K22/K23, LVDS)
# ==============================================================================
# Board clock is 200 MHz LVDS. PLLE2 in ara_fpga_wrap generates a 50 MHz core clock.

create_clock -name sys_clk_pin -period 5.000 [get_ports sys_clk_p]
set_property PACKAGE_PIN K22 [get_ports sys_clk_p]
set_property PACKAGE_PIN K23 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports {sys_clk_p sys_clk_n}]

# Optional clock input jitter example (tune as needed)
# set_input_jitter [get_clocks -of_objects [get_ports sys_clk_p]] 0.050

# ==============================================================================
# Board Management: Reset
# ==============================================================================

# Active-low system reset pushbutton
set_property PACKAGE_PIN J14 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

# ==============================================================================
# User LEDs (4x)
# ==============================================================================

set_property PACKAGE_PIN J12 [get_ports {led[0]}]
set_property PACKAGE_PIN H14 [get_ports {led[1]}]
set_property PACKAGE_PIN F13 [get_ports {led[2]}]
set_property PACKAGE_PIN H12 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# ==============================================================================
# UART
# ==============================================================================

set_property PACKAGE_PIN AD15 [get_ports uart_tx]
set_property PACKAGE_PIN AE15 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_tx uart_rx}]
# From AXKU5 manual: UART_TXD=B84_L3_P(AD15), UART_RXD=B84_L3_N(AE15)

# ==============================================================================
# Methodology helpers (optional)
# ==============================================================================

# Example: treat asynchronous, board-level pushbutton reset as false path
# set_false_path -from [get_ports sys_rst_n]

# Drive/slew examples for fast GPIO if needed:
# set_property SLEW FAST [get_ports led[*]]
# set_property DRIVE 8   [get_ports led[*]]

# ==============================================================================
# End of minimal AXKU5 constraints for Ara FPGA bring-up
# ==============================================================================