# Xcelium-specific simulation script

# Check if trace environment variable is set for waveform dumping
if {[info exists ::env(XCELIUM_TRACE)] && $::env(XCELIUM_TRACE) == "1"} {
    # Select waveform format: default SHM, optional VCD via XCELIUM_WAVE_FORMAT=vcd
    set fmt "shm"
    if {[info exists ::env(XCELIUM_WAVE_FORMAT)]} {
        set fmt [string tolower $::env(XCELIUM_WAVE_FORMAT)]
    }
    set dbname "xcelium_waves"
    if {$fmt eq "vcd"} {
        # Open VCD database/file
        set vcdfile "xcelium_waves.vcd"
        database -open $dbname -vcd -into $vcdfile -default
        # Probe all signals at all levels
        probe -create -all -depth all -database $dbname
        puts "Xcelium: Waveform tracing enabled - $vcdfile (VCD)"
    } else {
        # Open SHM database for waveform dumping
        database -open $dbname -shm -default
        # Probe all signals at all levels
        probe -create -all -depth all -database $dbname
        puts "Xcelium: Waveform tracing enabled - $dbname.shm (SHM)"
    }
} else {
    puts "Xcelium: Running without waveform tracing (use trace=1 to enable; optional wavefmt=vcd|shm)"
}

# Run simulation to completion
run