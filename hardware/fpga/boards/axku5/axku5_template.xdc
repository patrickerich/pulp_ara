# ==============================================================================
# AXKU5 Board - Consolidated Vivado XDC Template
# Device: XCKU5P-FFVB676-2I
# ==============================================================================

# ==============================================================================
# System Reference Clocks (choose ONE primary source)
# ==============================================================================

## Option A: 200 MHz differential clock on K22/K23 (commonly used)
## Seen in: hdmi_loop, ethernet_test, DDR4 designs, corescore
# create_clock -period 5.000 [get_ports sys_clk_p]
# set_property PACKAGE_PIN K22 [get_ports sys_clk_p]
# set_property PACKAGE_PIN K23 [get_ports sys_clk_n]
# set_property IOSTANDARD DIFF_SSTL12 [get_ports {sys_clk_p sys_clk_n}]
# Alternative for generic LVDS oscillators (as used in corescore):
# set_property IOSTANDARD LVDS [get_ports {sys_clk_p sys_clk_n}]

## Option B: Differential clock on AC13/AC14 (used in LCD demos)
## Note: Some projects used DIFF_SSTL12; others LVDS_25. Pick the one matching your board/clock source.
# create_clock -period 5.000 [get_ports sys_clk_p]
# set_property PACKAGE_PIN AC13 [get_ports sys_clk_p]
# set_property PACKAGE_PIN AC14 [get_ports sys_clk_n]
# set_property IOSTANDARD DIFF_SSTL12 [get_ports {sys_clk_p sys_clk_n}]
# Alternative if required by your oscillator/bridge:
# set_property IOSTANDARD LVDS_25 [get_ports {sys_clk_p sys_clk_n}]

## DDR4 reference clock (if driving MIG sys clock directly via top ports)
## Keep commented if your MIG IP brings its own constraints or uses dedicated pins.
# create_clock -period 5.000 [get_ports ddr_clk_p]
# set_property PACKAGE_PIN K22 [get_ports ddr_clk_p]
# set_property PACKAGE_PIN K23 [get_ports ddr_clk_n]
# set_property IOSTANDARD DIFF_SSTL12 [get_ports {ddr_clk_p ddr_clk_n}]

# Optional clock input jitter examples (use with your actual clock port)
# set_input_jitter [get_clocks -of_objects [get_ports sys_clk_p]] 0.050

## Option C: User-defined differential clock on J23/J24 (per manual USER_DEF_CLOCK_P/N)
# create_clock -period 10.000 [get_ports user_clk_p]
# set_property PACKAGE_PIN J23 [get_ports user_clk_p]
# set_property PACKAGE_PIN J24 [get_ports user_clk_n]
# set_property IOSTANDARD LVDS [get_ports {user_clk_p user_clk_n}]

# ==============================================================================
# Board Management: Reset, Keys, Fan
# ==============================================================================

# Active-low system reset pushbutton
set_property PACKAGE_PIN J14 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

# User key/button (single)
set_property PACKAGE_PIN J15 [get_ports key]
set_property IOSTANDARD LVCMOS33 [get_ports key]

# Optional 4 user keys (active low). KEY1 shares J14 (often used as sys_rst_n).
# set_property PACKAGE_PIN J14 [get_ports {key[0]}]
# set_property PACKAGE_PIN J15 [get_ports {key[1]}]
# set_property PACKAGE_PIN J13 [get_ports {key[2]}]
# set_property PACKAGE_PIN H13 [get_ports {key[3]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {key[*]}]

# Fan PWM
set_property PACKAGE_PIN Y16 [get_ports fan_pwm]
set_property IOSTANDARD LVCMOS33 [get_ports fan_pwm]

# ==============================================================================
# User LEDs (4x)
# ==============================================================================

set_property PACKAGE_PIN J12 [get_ports {led[0]}]
set_property PACKAGE_PIN H14 [get_ports {led[1]}]
set_property PACKAGE_PIN F13 [get_ports {led[2]}]
set_property PACKAGE_PIN H12 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# ==============================================================================
# SD Card (SPI mode)
# From sd_picture_lcd_* demos
# ==============================================================================

set_property PACKAGE_PIN Y13  [get_ports sd_dclk]
set_property PACKAGE_PIN AF14 [get_ports sd_ncs]
set_property PACKAGE_PIN AA13 [get_ports sd_mosi]
set_property PACKAGE_PIN W13  [get_ports sd_miso]
set_property IOSTANDARD LVCMOS33 [get_ports {sd_dclk sd_ncs sd_mosi sd_miso}]

# Recommended drive/slew and pullups from demos
set_property DRIVE 16 [get_ports sd_dclk]
set_property DRIVE 16 [get_ports sd_mosi]
set_property DRIVE 16 [get_ports sd_ncs]
set_property SLEW SLOW [get_ports sd_dclk]
set_property SLEW SLOW [get_ports sd_mosi]
set_property SLEW SLOW [get_ports sd_ncs]
set_property PULLUP true [get_ports sd_dclk]
set_property PULLUP true [get_ports sd_mosi]
set_property PULLUP true [get_ports sd_ncs]
set_property PULLUP true [get_ports sd_miso]

# SD Card (SDIO mode, per AXKU5 manual)
# Note: SDIO shares pins in BANK84; choose either SPI mode above or SDIO below.
# Card detect (low when card inserted)
set_property PACKAGE_PIN AD14 [get_ports sd_cd]
# SDIO signals
set_property PACKAGE_PIN Y13  [get_ports sd_clk]
set_property PACKAGE_PIN AA13 [get_ports sd_cmd]
set_property PACKAGE_PIN W13  [get_ports sd_d0]
set_property PACKAGE_PIN W12  [get_ports sd_d1]
set_property PACKAGE_PIN AF15 [get_ports sd_d2]
set_property PACKAGE_PIN AF14 [get_ports sd_d3]
set_property IOSTANDARD LVCMOS33 [get_ports {sd_cd sd_clk sd_cmd sd_d0 sd_d1 sd_d2 sd_d3}]

# ==============================================================================
# Ethernet: RGMII (as in ethernet_test/rgmii_ethernet top.xdc)
# Bank voltage: 1.8V, FAST slew on TX
# ==============================================================================

# 125 MHz receive clock from PHY
create_clock -period 8.000 [get_ports rgmii_rxc]

# IOSTANDARDs
set_property IOSTANDARD LVCMOS18 [get_ports {rgmii_rxd[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports {rgmii_txd[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports {rgmii_rxc rgmii_rxctl rgmii_txc rgmii_txctl}]
set_property IOSTANDARD LVCMOS18 [get_ports {e_mdc e_mdio e_reset}]

# Slew for TX
set_property SLEW FAST [get_ports {rgmii_txd[*]}]
set_property SLEW FAST [get_ports rgmii_txc]
set_property SLEW FAST [get_ports rgmii_txctl]

# Pin mapping (RGMII)
set_property PACKAGE_PIN R22 [get_ports {rgmii_rxd[3]}]
set_property PACKAGE_PIN P21 [get_ports {rgmii_rxd[2]}]
set_property PACKAGE_PIN P20 [get_ports {rgmii_rxd[1]}]
set_property PACKAGE_PIN V19 [get_ports {rgmii_rxd[0]}]

set_property PACKAGE_PIN P19 [get_ports {rgmii_txd[3]}]
set_property PACKAGE_PIN N19 [get_ports {rgmii_txd[2]}]
set_property PACKAGE_PIN V22 [get_ports {rgmii_txd[1]}]
set_property PACKAGE_PIN V21 [get_ports {rgmii_txd[0]}]

set_property PACKAGE_PIN U21 [get_ports rgmii_rxc]
set_property PACKAGE_PIN R23 [get_ports rgmii_rxctl]
set_property PACKAGE_PIN R25 [get_ports rgmii_txc]
set_property PACKAGE_PIN R26 [get_ports rgmii_txctl]
# MDIO/MDC and PHY reset
set_property PACKAGE_PIN N26 [get_ports e_mdc]
set_property PACKAGE_PIN U19 [get_ports e_mdio]
set_property PACKAGE_PIN N22 [get_ports e_reset]

# Alternative port names per manual (ETH_*). Uncomment if your top-level uses these names:
# set_property PACKAGE_PIN N26 [get_ports ETH_MDC]
# set_property PACKAGE_PIN U19 [get_ports ETH_MDIO]
# set_property PACKAGE_PIN N22 [get_ports ETH_RESET]
# set_property PACKAGE_PIN U21 [get_ports ETH_RXCK]
# set_property PACKAGE_PIN R23 [get_ports ETH_RXCTL]
# set_property PACKAGE_PIN V19 [get_ports ETH_RXD0]
# set_property PACKAGE_PIN P20 [get_ports ETH_RXD1]
# set_property PACKAGE_PIN P21 [get_ports ETH_RXD2]
# set_property PACKAGE_PIN R22 [get_ports ETH_RXD3]
# set_property PACKAGE_PIN R25 [get_ports ETH_TXCK]
# set_property PACKAGE_PIN R26 [get_ports ETH_TXCTL]
# set_property PACKAGE_PIN V21 [get_ports ETH_TXD0]
# set_property PACKAGE_PIN V22 [get_ports ETH_TXD1]
# set_property PACKAGE_PIN N19 [get_ports ETH_TXD2]
# set_property PACKAGE_PIN P19 [get_ports ETH_TXD3]

# ==============================================================================
# HDMI Control/I2C/HPD (subset from hdmi_loop)
# Video data/control buses are design-specific; include if you use HDMI blocks.
# ==============================================================================

# Downstream (TX) side control lines
set_property PACKAGE_PIN Y20 [get_ports hdmi_nreset]
set_property PACKAGE_PIN AB17 [get_ports hdmi_scl]
set_property PACKAGE_PIN AC17 [get_ports hdmi_sda]
set_property IOSTANDARD LVCMOS18 [get_ports {hdmi_nreset hdmi_scl hdmi_sda}]

# Upstream (RX) side DDC/HPD
set_property PACKAGE_PIN AD19 [get_ports hdmi_hpd]
set_property PACKAGE_PIN Y18  [get_ports hdmi_ddc_scl_io]
set_property PACKAGE_PIN AA18 [get_ports hdmi_ddc_sda_io]
set_property IOSTANDARD LVCMOS18 [get_ports {hdmi_hpd hdmi_ddc_scl_io hdmi_ddc_sda_io}]

# If you use full HDMI input/output 24-bit buses, see 01_demo_document/demo/hdmi_loop/.../hdmi_loop.xdc
# for the complete pin mapping and add here accordingly.

# ==============================================================================
# MIPI CSI-2 Camera (optional) — per AXKU5 manual (BANK66/BANK84)
# ==============================================================================
# Differential clock
# set_property PACKAGE_PIN L18 [get_ports mipi_clk_p]
# set_property PACKAGE_PIN K18 [get_ports mipi_clk_n]
# Data lanes
# set_property PACKAGE_PIN K21 [get_ports mipi_lan0_p]
# set_property PACKAGE_PIN J21 [get_ports mipi_lan0_n]
# set_property PACKAGE_PIN M20 [get_ports mipi_lan1_p]
# set_property PACKAGE_PIN M21 [get_ports mipi_lan1_n]
# set_property PACKAGE_PIN J19 [get_ports mipi_lan2_p]
# set_property PACKAGE_PIN J20 [get_ports mipi_lan2_n]
# set_property PACKAGE_PIN M19 [get_ports mipi_lan3_p]
# set_property PACKAGE_PIN L19 [get_ports mipi_lan3_n]
# Sideband/control
# set_property PACKAGE_PIN W14 [get_ports mipi_clk]      ; camera clock in (if used)
# set_property PACKAGE_PIN W15 [get_ports mipi_gpio]
# set_property PACKAGE_PIN AB14 [get_ports mipi_i2c_scl]
# set_property PACKAGE_PIN AA14 [get_ports mipi_i2c_sda]
# set_property IOSTANDARD LVCMOS18 [get_ports {mipi_clk mipi_gpio mipi_i2c_scl mipi_i2c_sda}]
# Note: D-PHY requires a proper PHY; these assignments are for associated low-speed/control pins.

# ==============================================================================
# LCD Panels (optional) — choose the panel you use and enable its block
# ==============================================================================

## AN070 LCD (from sd_picture_lcd_an070)
# set_property PACKAGE_PIN B10 [get_ports lcd_pwm]
# set_property PACKAGE_PIN E10 [get_ports lcd_hs]
# set_property PACKAGE_PIN E11 [get_ports lcd_vs]
# set_property PACKAGE_PIN A9  [get_ports lcd_dclk]
# set_property PACKAGE_PIN B9  [get_ports lcd_de]
# set_property PACKAGE_PIN D10 [get_ports {lcd_b[6]}]
# set_property PACKAGE_PIN D11 [get_ports {lcd_b[7]}]
# set_property PACKAGE_PIN C9  [get_ports {lcd_b[4]}]
# set_property PACKAGE_PIN D9  [get_ports {lcd_b[5]}]
# set_property PACKAGE_PIN F9  [get_ports {lcd_b[2]}]
# set_property PACKAGE_PIN F10 [get_ports {lcd_b[3]}]
# set_property PACKAGE_PIN G9  [get_ports {lcd_b[0]}]
# set_property PACKAGE_PIN G10 [get_ports {lcd_b[1]}]
# set_property PACKAGE_PIN H9  [get_ports {lcd_g[6]}]
# set_property PACKAGE_PIN J9  [get_ports {lcd_g[7]}]
# set_property PACKAGE_PIN J10 [get_ports {lcd_g[4]}]
# set_property PACKAGE_PIN J11 [get_ports {lcd_g[5]}]
# set_property PACKAGE_PIN G11 [get_ports {lcd_g[2]}]
# set_property PACKAGE_PIN H11 [get_ports {lcd_g[3]}]
# set_property PACKAGE_PIN K9  [get_ports {lcd_g[0]}]
# set_property PACKAGE_PIN K10 [get_ports {lcd_g[1]}]
# set_property PACKAGE_PIN B12 [get_ports {lcd_r[6]}]
# set_property PACKAGE_PIN C12 [get_ports {lcd_r[7]}]
# set_property PACKAGE_PIN E12 [get_ports {lcd_r[4]}]
# set_property PACKAGE_PIN E13 [get_ports {lcd_r[5]}]
# set_property PACKAGE_PIN F12 [get_ports {lcd_r[2]}]
# set_property PACKAGE_PIN G12 [get_ports {lcd_r[3]}]
# set_property PACKAGE_PIN A12 [get_ports {lcd_r[0]}]
# set_property PACKAGE_PIN A13 [get_ports {lcd_r[1]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {lcd_pwm lcd_hs lcd_vs lcd_dclk lcd_de lcd_b[*] lcd_g[*] lcd_r[*]}]

## AN430 LCD (from an430_lcd_test / sd_picture_lcd_an430)
# set_property PACKAGE_PIN A10 [get_ports {lcd_r[0]}]
# set_property PACKAGE_PIN B10 [get_ports {lcd_r[1]}]
# set_property PACKAGE_PIN B11 [get_ports {lcd_r[2]}]
# set_property PACKAGE_PIN C11 [get_ports {lcd_r[3]}]
# set_property PACKAGE_PIN E10 [get_ports {lcd_r[4]}]
# set_property PACKAGE_PIN E11 [get_ports {lcd_r[5]}]
# set_property PACKAGE_PIN A9  [get_ports {lcd_r[6]}]
# set_property PACKAGE_PIN B9  [get_ports {lcd_r[7]}]
# set_property PACKAGE_PIN D10 [get_ports {lcd_g[0]}]
# set_property PACKAGE_PIN D11 [get_ports {lcd_g[1]}]
# set_property PACKAGE_PIN C9  [get_ports {lcd_g[2]}]
# set_property PACKAGE_PIN D9  [get_ports {lcd_g[3]}]
# set_property PACKAGE_PIN F9  [get_ports {lcd_g[4]}]
# set_property PACKAGE_PIN F10 [get_ports {lcd_g[5]}]
# set_property PACKAGE_PIN G9  [get_ports {lcd_g[6]}]
# set_property PACKAGE_PIN G10 [get_ports {lcd_g[7]}]
# set_property PACKAGE_PIN H9  [get_ports {lcd_b[0]}]
# set_property PACKAGE_PIN J9  [get_ports {lcd_b[1]}]
# set_property PACKAGE_PIN J10 [get_ports {lcd_b[2]}]
# set_property PACKAGE_PIN J11 [get_ports {lcd_b[3]}]
# set_property PACKAGE_PIN G11 [get_ports {lcd_b[4]}]
# set_property PACKAGE_PIN H11 [get_ports {lcd_b[5]}]
# set_property PACKAGE_PIN K9  [get_ports {lcd_b[6]}]
# set_property PACKAGE_PIN K10 [get_ports {lcd_b[7]}]
# set_property PACKAGE_PIN B12 [get_ports lcd_dclk]
# set_property PACKAGE_PIN C12 [get_ports lcd_hs]
# set_property PACKAGE_PIN E12 [get_ports lcd_vs]
# set_property PACKAGE_PIN E13 [get_ports lcd_de]
# set_property IOSTANDARD LVCMOS33 [get_ports {lcd_r[*] lcd_g[*] lcd_b[*] lcd_dclk lcd_hs lcd_vs lcd_de}]

# ==============================================================================
# UART
# ==============================================================================

set_property PACKAGE_PIN AD15 [get_ports uart_tx]
set_property PACKAGE_PIN AE15 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_tx uart_rx}]
# From manual (AXKU5.pdf): UART_TXD=B84_L3_P(AD15), UART_RXD=B84_L3_N(AE15)

# ==============================================================================
# DDR4 Notes
# ==============================================================================
# MIG/DDRx IP delivers its own detailed XDC (IOSTANDARDs POD12_DCI, SSTL12_DCI, equalization, etc.).
# Typically you should NOT duplicate those here. If needed, only ensure the reference clock pins
# (e.g., c0_sys_clk_p/n or ddr_clk_p/n) are correctly constrained using the clock options above.

# ==============================================================================
# Methodology helpers (optional patterns)
# ==============================================================================

# Example: treat asynchronous, board-level pushbutton reset as false path
# set_false_path -from [get_ports sys_rst_n]

# Drive strength/slew examples:
# set_property SLEW FAST [get_ports some_fast_output]
# set_property DRIVE 8   [get_ports some_output]

# ==============================================================================
# End of template
# ==============================================================================