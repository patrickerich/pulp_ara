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

create_clock -period 5.000 -name sys_clk_pin [get_ports sys_clk_p]
set_property PACKAGE_PIN K22 [get_ports sys_clk_p]
set_property PACKAGE_PIN K23 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports sys_clk_p]
set_property IOSTANDARD LVDS [get_ports sys_clk_n]

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
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
# From AXKU5 manual: UART_TXD=B84_L3_P(AD15), UART_RXD=B84_L3_N(AE15)

# ==============================================================================
# Methodology helpers (optional)
# ==============================================================================

# Example: treat asynchronous, board-level pushbutton reset as false path
set_false_path -from [get_ports sys_rst_n]

# If the button is not pressed (normal operation), ensure it reads high
# Some boards need explicit pullup enabled
set_property PULLTYPE PULLUP [get_ports sys_rst_n]

# Drive/slew examples for fast GPIO if needed:
# set_property SLEW FAST [get_ports led[*]]
# set_property DRIVE 8   [get_ports led[*]]

# ==============================================================================
# End of minimal AXKU5 constraints for Ara FPGA bring-up
# ==============================================================================

# ==============================================================================
# JTAG (RISC-V Debug Module via dmi_jtag)
# ==============================================================================
# The FPGA top-level [`ara_fpga_wrap()`](hardware/fpga/src/ara_fpga_wrap.sv:6) exposes:
#   - jtag_tck
#   - jtag_tms
#   - jtag_trst_n
#   - jtag_tdi
#   - jtag_tdo
#
# Map these ports to the appropriate user I/O pins or a dedicated fabric JTAG
# header on your AXKU5 board. The example below shows the constraint syntax;
# you MUST replace &lt;PIN_*&gt; with valid package pins for your board and then
# uncomment the lines.
#
# Example:
#
# set_property PACKAGE_PIN &lt;PIN_TCK&gt;   [get_ports jtag_tck]
# set_property PACKAGE_PIN &lt;PIN_TMS&gt;   [get_ports jtag_tms]
# set_property PACKAGE_PIN &lt;PIN_TRST&gt;  [get_ports jtag_trst_n]
# set_property PACKAGE_PIN &lt;PIN_TDI&gt;   [get_ports jtag_tdi]
# set_property PACKAGE_PIN &lt;PIN_TDO&gt;   [get_ports jtag_tdo]
# set_property IOSTANDARD LVCMOS33 [get_ports {jtag_tck jtag_tms jtag_trst_n jtag_tdi jtag_tdo}]
#
# NOTE:
# - These JTAG signals are for the RISC-V Debug Module only and are independent
#   of the dedicated Xilinx configuration JTAG pins used to program the FPGA.
# - Make sure the selected pins belong to a bank powered for 3.3 V (LVCMOS33),
#   or adjust the IOSTANDARD accordingly.


# ==============================================================================
# JTAG (RISC-V Debug Module via dmi_jtag) – Olimex ARM-USB-TINY on J8
# ==============================================================================
# The FPGA top-level [`ara_fpga_wrap()`](hardware/fpga/src/ara_fpga_wrap.sv:6) exposes:
#   - jtag_tck
#   - jtag_tms
#   - jtag_trst_n
#   - jtag_tdi
#   - jtag_tdo
#
# The reference design (`hardware/fpga/reference/axku5_olimex.xdc`) uses the
# following J8 mapping (high end of the AXKU5 J8 header):
#   J8-28 (IO1_13P, C12) -> TRST_N
#   J8-30 (IO1_14P, E13) -> TDI
#   J8-32 (IO1_15P, G12) -> TMS
#   J8-34 (IO1_16P, A13) -> TCK
#   J8-36 (IO1_17P, D14) -> TDO
#
# We reuse exactly those package pins, but bind them to our ara_fpga_wrap ports:
#   jtag_tck, jtag_tms, jtag_trst_n, jtag_tdi, jtag_tdo

# Pin assignments (adapted from axku5_olimex.xdc)
set_property PACKAGE_PIN A13 [get_ports jtag_tck]
set_property PACKAGE_PIN G12 [get_ports jtag_tms]
set_property PACKAGE_PIN E13 [get_ports jtag_tdi]
set_property PACKAGE_PIN D14 [get_ports jtag_tdo]
set_property PACKAGE_PIN C12 [get_ports jtag_trst_n]

# JTAG is 3.3V single-ended on these IO pins
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_tck jtag_tms jtag_trst_n jtag_tdi jtag_tdo}]

# Recommended pulls so TAP stays in reset/idle when no probe is attached
set_property PULLTYPE PULLUP [get_ports {jtag_tms jtag_trst_n}]

# Basic timing guidance for the external JTAG signals
set_max_delay -to   [get_ports { jtag_tdo } ] 20
set_max_delay -from [get_ports { jtag_tms } ] 20
set_max_delay -from [get_ports { jtag_tdi } ] 20
set_max_delay -from [get_ports { jtag_trst_n } ] 20
set_false_path -from [get_ports { jtag_trst_n }]


# ------------------------------------------------------------------------------
# JTAG TCK routing: prevent promotion to global clock (fix PLHDIO-3)
# ------------------------------------------------------------------------------
# Vivado was inferring a BUFG/BUFGCE_DIV on jtag_tck, which is illegal for
# this HDIO bank and triggers DRC PLHDIO-3. We do not need jtag_tck on the
# global clock network, so disable automatic clock buffering here.
set_property CLOCK_BUFFER_TYPE NONE [get_ports jtag_tck]


# Allow non-dedicated routing between jtag_tck HDIO and BUFGCE (fix rule_gclkio_bufg).
# This is acceptable for low-frequency JTAG TCK.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets jtag_tck_IBUF_inst/O]
