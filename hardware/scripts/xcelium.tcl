# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Xcelium-specific simulation script

# Check if trace environment variable is set for waveform dumping
if {[info exists ::env(XCELIUM_TRACE)] && $::env(XCELIUM_TRACE) == "1"} {
    # Open SHM database for waveform dumping
    database -open xcelium_waves -shm -default
    # Probe all signals at all levels
    probe -create -all -depth all -database xcelium_waves
    puts "Xcelium: Waveform tracing enabled - xcelium_waves.shm"
} else {
    puts "Xcelium: Running without waveform tracing (use trace=1 to enable)"
}

# Run simulation to completion
run