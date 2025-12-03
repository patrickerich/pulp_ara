# utils/run_hello_uart.tcl
#
# Usage from the host:
#   openocd -f hardware/fpga/boards/axku5/axku5.cfg \
#           -c "source utils/run_hello_uart.tcl; run_hello_uart; shutdown"
#
# Or from an existing OpenOCD telnet session:
#   > source utils/load_sba.tcl
#   > source utils/run_hello_uart.tcl
#   > run_hello_uart

proc run_hello_uart {} {
    # Configuration
    set bin_path  "apps/bin/hello_world_uart.bin"
    set base_addr "0x80000000"
    set marker_addr 0x80001000

    echo "=== run_hello_uart: starting ==="
    echo "  Binary  : $bin_path"
    echo "  Base    : $base_addr"
    echo "  Marker  : [format 0x%08x $marker_addr]"

    # ----------------------------------------------------------------------------
    # 1. Turn DM on, no ndmreset, no haltreq
    # ----------------------------------------------------------------------------
    #
    # dmcontrol layout (see dm_pkg.sv):
    #   [31] haltreq
    #   [30] resumereq
    #   [1]  ndmreset
    #   [0]  dmactive
    #
    # 0x00000001 => dmactive=1, ndmreset=0, haltreq=0
    #
    echo "run_hello_uart: dmactive=1, ndmreset=0, haltreq=0"
    riscv dmi_write 0x10 0x00000001

    # ----------------------------------------------------------------------------
    # 2. Assert ndmreset (core in reset while we program SRAM via SBA)
    # ----------------------------------------------------------------------------
    #
    # 0x00000003 => dmactive=1, ndmreset=1, haltreq=0
    #
    echo "run_hello_uart: Asserting ndmreset (core in reset)"
    riscv dmi_write 0x10 0x00000003

    # ----------------------------------------------------------------------------
    # 3. Configure SBA & load binary into SRAM via existing load_sba()
    # ----------------------------------------------------------------------------
    #
    # This uses the same SBCS configuration you verified manually:
    #   sbreadonaddr   = 1  (bit 20)
    #   sbaccess       = 2  (32-bit)
    #   clear sberror/sbbusyerror via W1C
    #
    set sbcs_cfg [expr { (1 << 20) | (2 << 17) | (1 << 22) | (0x7 << 12) }]
    echo [format "run_hello_uart: Initial SBCS cfg = 0x%08x" $sbcs_cfg]
    riscv dmi_write 0x38 $sbcs_cfg
    riscv dmi_read  0x38

    # Make sure load_sba is defined
    if {[llength [info commands load_sba]] == 0} {
        echo "run_hello_uart: ERROR: load_sba procedure not found."
        echo "  Please 'source utils/load_sba.tcl' before calling run_hello_uart."
        return
    }

    echo "run_hello_uart: Loading binary via SBA..."
    load_sba $bin_path $base_addr

    # ----------------------------------------------------------------------------
    # 4. Clear SBA errors (SBCS) after the load, keep sbreadonaddr
    # ----------------------------------------------------------------------------
    #
    # Write-1-to-clear sberror[14:12] and sbbusyerror[22], keep sbreadonaddr.
    #
    set clear_errors_cfg 10514432
    echo [format "run_hello_uart: Clearing SBA errors with SBCS=0x%08x" $clear_errors_cfg]
    riscv dmi_write 0x38 $clear_errors_cfg
    riscv dmi_read  0x38

    # ----------------------------------------------------------------------------
    # 5. Release ndmreset with dmactive=1, haltreq=0 so the core starts
    # ----------------------------------------------------------------------------
    #
    # DO NOT set haltreq (bit 31) here. We want the core to run freely.
    #
    echo "run_hello_uart: Releasing ndmreset (core starts at base address)"
    riscv dmi_write 0x10 0x00000001

    # Optionally, wait a bit (in wall-clock time) by polling dmstatus
    # so we give the core time to run before checking the marker.
    #
    # Simple loop: read dmstatus a few times just to insert some delay.
    for {set i 0} {$i < 10} {incr i} {
        set dmstatus [riscv dmi_read 0x11]
        # Uncomment if you want to see it:
        # echo [format "  dmstatus[%d] = 0x%08x" $i $dmstatus]
    }

    # ----------------------------------------------------------------------------
    # 6. (Optional) Halt core via ndmreset again and read MARKER via SBA
    # ----------------------------------------------------------------------------
    #
    # Now we want to see whether main() ran and wrote 0xDEADBEEF to MARKER_ADDR.
    #
    echo "run_hello_uart: Halting core via ndmreset to inspect marker"
    riscv dmi_write 0x10 0x00000003   ;# dmactive=1, ndmreset=1, haltreq=0

    # Re-configure SBCS for a one-off SBA read
    riscv dmi_write 0x38 $sbcs_cfg
    riscv dmi_read  0x38

    # Read MARKER_ADDR via SBA
    riscv dmi_write 0x39 [expr {$marker_addr & 0xffffffff}]
    riscv dmi_write 0x3a [expr {($marker_addr >> 32) & 0xffffffff}]
    set marker [riscv dmi_read 0x3c]
    echo [format "run_hello_uart: MARKER @0x%08x = 0x%08x" $marker_addr $marker]

    echo "=== run_hello_uart: done ==="
}
