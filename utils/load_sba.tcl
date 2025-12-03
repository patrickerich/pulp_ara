# utils/load_sba.tcl
#
# Usage from OpenOCD telnet:
#   source utils/load_sba.tcl
#   load_sba apps/bin/hello_world_uart 0x80000000
#
# This script:
#   - Configures SBA for 32-bit accesses with sbreadonaddr=1.
#   - Writes the file to memory word-by-word.
#   - Immediately reads back each word to verify.
#   - At the end, reads SBCS (0x38) and reports any SBA errors.

proc load_sba {filename base_addr_hex} {
    echo "Loading $filename to $base_addr_hex via SBA..."

    # Parse base address as hex
    scan $base_addr_hex "%x" base_addr

    # Configure SBCS. We intentionally mirror the manual settings that you
    # already verified to work interactively:
    #   sbcs_cfg = (1 << 20) | (2 << 17) | (1 << 22) | (0x7 << 12)
    # which, for this DM variant, results in SBCS ~= 0x20160808:
    #   - sbreadonaddr   = 1  (bit 20 in this integration)
    #   - sbaccess       = 2  (bits 19:17) => 32-bit
    #   - sbbusyerror    = 0 (we write 1 to clear it via W1C)
    #   - sberror        = 0 (we write 1s into bits 14:12 to clear via W1C)
    #
    # Even though the dm_pkg.sv we inspected suggests sbreadonaddr at bit 21,
    # the *effective* behavior you observed on hardware matches this original
    # encoding, so we use it here as the "known good" configuration.
    set sbcs_cfg [expr { (1 << 20) | (2 << 17) | (1 << 22) | (0x7 << 12) }]
    riscv dmi_write 0x38 $sbcs_cfg
    riscv dmi_read  0x38

    # Read file into memory as raw bytes
    set fd [open $filename r]
    fconfigure $fd -translation binary
    set data [read $fd]
    close $fd

    # Pad to 4-byte boundary (32-bit words)
    set len [string length $data]
    if { $len % 4 != 0 } {
        set pad [expr {4 - ($len % 4)}]
        # Append pad zero bytes
        for {set i 0} {$i < $pad} {incr i} {
            append data "\x00"
        }
        set len [string length $data]
    }

    set num_words [expr {$len / 4}]
    echo "Writing $num_words words ($len bytes) with per-word write+read-back..."

    set errors 0

    # Helper: get 32-bit little-endian word at offset i
    # (i is byte offset, multiple of 4)
    proc get_le_word {data i} {
        # Extract 4 bytes starting at offset i
        set b0 [scan [string index $data $i]                 %c]
        set b1 [scan [string index $data [expr {$i + 1}]]    %c]
        set b2 [scan [string index $data [expr {$i + 2}]]    %c]
        set b3 [scan [string index $data [expr {$i + 3}]]    %c]
        # little-endian: lowest address = LSB
        set word [expr {($b0 & 0xff)
                      | (($b1 & 0xff) << 8)
                      | (($b2 & 0xff) << 16)
                      | (($b3 & 0xff) << 24)}]
        return $word
    }

    # Helper: wait until SBA is idle (sbbusy == 0) before accessing SBData.
    # This avoids reading SBData0 while the previous SBA transaction is still
    # in progress, which would cause sbbusyerror to be set and return stale data.
    proc wait_sba_idle {addr} {
        while {1} {
            set sbcs [riscv dmi_read 0x38]
            set sbbusy [expr {($sbcs >> 22) & 0x1}]
            if {$sbbusy == 0} {
                return $sbcs
            }
        }
    }

    # Main loop: for each 32-bit word
    for {set i 0} {$i < $len} {incr i 4} {
        set word_index [expr {$i / 4}]
        set addr       [expr {$base_addr + $i}]

        set word [get_le_word $data $i]

        # 1) Set SBAddress (like your manual test)
        riscv dmi_write 0x39 [expr {$addr & 0xffffffff}]
        riscv dmi_write 0x3a [expr {($addr >> 32) & 0xffffffff}]

        # 2) Write SBData0 (low 32 bits). For a 64-bit BusWidth DM, this still
        # performs a 32-bit access as per the DM's SBA implementation, which we
        # know works from your manual tests.
        riscv dmi_write 0x3c $word

        # 3) Trigger a read by setting the address again (sbreadonaddr=1)
        riscv dmi_write 0x39 [expr {$addr & 0xffffffff}]
        riscv dmi_write 0x3a [expr {($addr >> 32) & 0xffffffff}]

        # 4) Wait for SBA to become idle before reading back, to avoid
        #    sbbusyerror/stale data on the first (or any) transfer.
        #    Pass the current address so we can see which access we waited for.
        set _sbcs_after [wait_sba_idle $addr]

        # 5) Read back from SBData0
        set actual [riscv dmi_read 0x3c]

        # Compare. Note: both $word and $actual are integers; Tcl understands 0x... too.
        if {$actual != $word} {
            # Format both as 8-hex-digit values
            set w_str [format "0x%08x" $word]
            set a_str [format "0x%08x" $actual]
            echo [format "  MISMATCH at 0x%08x: wrote %s, read back %s" $addr $w_str $a_str]
            incr errors
        }

        if {($word_index % 100) == 0} {
            echo [format "  Progress: %d/%d words" $word_index $num_words]
        }
    }

    # Final summary of per-word verification
    if {$errors == 0} {
        echo "Done writing! All words verified correctly."
    } else {
        echo [format "Done writing! %d mismatches detected." $errors]
    }

    # Check SBA status (SBCS) at end of load
    set sbcs [riscv dmi_read 0x38]
    set sberror     [expr {($sbcs >> 12) & 0x7}]
    set sbbusyerror [expr {($sbcs >> 23) & 0x1}]

    if {$sberror != 0 || $sbbusyerror != 0} {
        echo [format "WARNING: SBA completed with errors (SBCS = 0x%08x, sberror=%d, sbbusyerror=%d)" \
                     $sbcs $sberror $sbbusyerror]
        echo "Hint: clear errors with e.g.:"
        echo "  set clear_errors_cfg [expr { (1 << 21) | (1 << 23) | (0x7 << 12) }]"
        echo "  riscv dmi_write 0x38 \$clear_errors_cfg"
    } else {
        echo [format "SBA status clean after load (SBCS = 0x%08x)" $sbcs]
    }
}
