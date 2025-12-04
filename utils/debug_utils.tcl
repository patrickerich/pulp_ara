# utils/debug_utils.tcl
#
# Utility Tcl procedures for OpenOCD + RISC-V DM/SBA on Ara/CVA6.
#
# Usage from OpenOCD telnet:
#   source utils/debug_utils.tcl
#   sba_config_32
#   sba_read32 0x80000000
#   uart_status_once
#   uart_tx_char A

########################################################################
# Low-level DM / DMI helpers
########################################################################

# Read a DM CSR via DMI (address in hex or decimal)
proc dm_read {addr} {
    set val [riscv dmi_read $addr]
    echo [format "DM(0x%02x) = 0x%08x" $addr $val]
    return $val
}

# Write a DM CSR via DMI (address + value)
proc dm_write {addr value} {
    riscv dmi_write $addr $value
    # Optionally read back for confirmation
    set val [riscv dmi_read $addr]
    echo [format "DM(0x%02x) <= 0x%08x (readback)" $addr $val]
    return $val
}

########################################################################
# SBA helpers (32-bit accesses)
#
# Assumes:
#   - DM/SBA configured with BusWidth=64.
#   - sbcs already set up for 32-bit accesses, sbreadonaddr=1, etc.
#
# If needed, you can (re)configure SBCS here too.
########################################################################

# Configure SBCS for 32-bit accesses with sbreadonaddr and clear errors.
proc sba_config_32 {} {
    # sbreadonaddr = 1 (bit 20)
    # sbaccess     = 2 (bits 19:17) => 32-bit
    # clear sbbusyerror and sberror via W1C (impl-dependent mask 0x7<<12)
    # plus set a W1C bit to clear sberror in this implementation.
    set sbcs_cfg [expr { (1 << 20) | (2 << 17) | (1 << 22) | (0x7 << 12) }]
    riscv dmi_write 0x38 $sbcs_cfg
    set sbcs [riscv dmi_read 0x38]
    echo [format "SBCS = 0x%08x" $sbcs]
    return $sbcs
}

# # Clear SBA error bits (sbbusyerror, sberror) without changing mode fields.
# proc sba_clear_errors {} {
#     # clear_errors_cfg:
#     #   - sbbusyerror W1C (bit 21)
#     #   - sberror     W1C (bit 23)
#     #   - implementation-defined W1C mask (0x7 << 12)
#     set clear_errors_cfg [expr { (1 << 21) | (1 << 23) | (0x7 << 12) }]
#     riscv dmi_write 0x38 $clear_errors_cfg
#     set sbcs [riscv dmi_read 0x38]
#     echo [format "SBCS (after clear) = 0x%08x" $sbcs]
#     return $sbcs
# }

# Clear SBA error bits safely by re-applying the known-good SBCS config.
# This keeps sbreadonaddr/sbaccess and any other required fields in a
# consistent state and avoids relying on uncertain bitfield positions.
proc sba_clear_errors {} {
    return [sba_config_32]
}

# Wait until SBA is idle (sbbusy==0) before accessing SBData.
# max_iter is a safety limit to avoid hanging forever if something wedges.
proc sba_wait_idle {{max_iter 1000}} {
    # From dm_pkg.sv: sbbusy is bit 21 of SBCS.
    set SBBUSY_MASK 0x00200000
    for {set i 0} {$i < $max_iter} {incr i} {
        set sbcs [riscv dmi_read 0x38]
        if {($sbcs & $SBBUSY_MASK) == 0} {
            return $sbcs
        }
    }
    # Timed out: still busy after max_iter polls.
    echo [format "SBA still busy after %d polls, SBCS = 0x%08x" $max_iter $sbcs]
    return $sbcs
}

# Perform a single 32-bit SBA read from 'addr' (64-bit address).
proc sba_read32 {addr} {
    # Program address (this kicks off the read because sbreadonaddr=1)
    riscv dmi_write 0x39 [expr {$addr & 0xffffffff}]
    riscv dmi_write 0x3a [expr {($addr >> 32) & 0xffffffff}]

    # Wait for SBA engine to go idle before reading SBData0.
    set sbcs [sba_wait_idle]

    # Now read SBData0 (even if we timed out, so caller can inspect behavior)
    set data [riscv dmi_read 0x3c]
    echo [format "SBA(0x%016llx) -> 0x%08x" $addr $data]
    return $data
}

# Perform a single 32-bit SBA write to 'addr' with 'value'.
proc sba_write32 {addr value} {
    # Program address
    riscv dmi_write 0x39 [expr {$addr & 0xffffffff}]
    riscv dmi_write 0x3a [expr {($addr >> 32) & 0xffffffff}]
    # Write data
    riscv dmi_write 0x3c $value

    # Wait for SBA engine to complete the write.
    set sbcs [sba_wait_idle]

    echo [format "SBA(0x%016llx) => 0x%08x" $addr $value]
}

########################################################################
# Generic memory read/write loops via SBA
########################################################################

# Read 'count' 32-bit words starting at 'base_addr' via SBA.
proc read_mem {base_addr count} {
    set addr $base_addr
    for {set i 0} {$i < $count} {incr i} {
        set val [sba_read32 $addr]
        echo [format "MEM(0x%016llx) = 0x%08x" $addr $val]
        set addr [expr {$addr + 4}]
    }
}

# Write a list of 32-bit words to consecutive addresses via SBA.
# Usage:
#   write_mem 0x80000000 {0x11223344 0x55667788 0xAABBCCDD}
proc write_mem {base_addr values} {
    set addr $base_addr
    foreach v $values {
        sba_write32 $addr $v
        set addr [expr {$addr + 4}]
    }
}

########################################################################
# UART-specific helpers (addresses match Ara SoC)
########################################################################

# Base addresses as used in ara_soc / hello_world_uart.
set ::UART_BASE 0xC0000000
# Adjust offsets if your C code / UART IP uses different layout.
set ::UART_TX_OFFSET     0x0
set ::UART_STATUS_OFFSET 0x8

# Read UART status register once.
proc uart_status_once {} {
    variable ::UART_BASE
    variable ::UART_STATUS_OFFSET
    set addr [expr {$UART_BASE + $UART_STATUS_OFFSET}]
    set status [sba_read32 $addr]
    echo [format "UART_STATUS @ 0x%08x = 0x%08x" $addr $status]
    return $status
}

# Read UART status repeatedly 'count' times.
proc uart_status_loop {count} {
    variable ::UART_BASE
    variable ::UART_STATUS_OFFSET
    set addr [expr {$UART_BASE + $UART_STATUS_OFFSET}]
    for {set i 0} {$i < $count} {incr i} {
        set status [sba_read32 $addr]
        echo [format "UART_STATUS(%d) @ 0x%08x = 0x%08x" $i $addr $status]
    }
}

# Write a single byte to UART TX via SBA (for quick tests).
# 'ch' can be an integer or a single-character string.
proc uart_tx_char {ch} {
    variable ::UART_BASE
    variable ::UART_TX_OFFSET
    set addr [expr {$UART_BASE + $UART_TX_OFFSET}]

    if {[string length $ch] == 1} {
        scan $ch %c val
    } else {
        # Assume integer
        set val $ch
    }

    # Write lower 8 bits, preserved in 32-bit word.
    sba_write32 $addr [expr {$val & 0xff}]
    echo [format "UART_TX @ 0x%08x <= 0x%02x" $addr $val]
}

########################################################################
# Convenience functions for DM control / status
########################################################################

# Enable DM (dmactive=1) without changing other bits.
proc dm_enable {} {
    # Simple: write 1 to dmcontrol (dmactive=1)
    dm_write 0x10 0x00000001
}

# Assert and deassert ndmreset with dmactive=1.
proc dm_pulse_ndmreset {} {
    dm_write 0x10 0x00000003   ;# dmactive=1, ndmreset=1
    dm_write 0x10 0x00000001   ;# dmactive=1, ndmreset=0
}

# Request a halt (haltreq=1, dmactive=1).
proc dm_haltreq {} {
    dm_write 0x10 0x80000001   ;# haltreq=1, dmactive=1
}

# Read dmstatus and print key fields as raw value.
proc dm_status {} {
    set val [dm_read 0x11]
    echo [format "dmstatus = 0x%08x" $val]
    return $val
}

########################################################################
# SBCS inspection
########################################################################

# Read and print SBCS (0x38)
proc sba_status {} {
    set sbcs [riscv dmi_read 0x38]
    echo [format "SBCS = 0x%08x" $sbcs]
    return $sbcs
}