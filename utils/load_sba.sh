#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <binary> [base_addr_hex]" >&2
  echo "Example: $0 apps/bin/hello_world_uart.bin 0x80000000" >&2
  exit 1
fi

BIN="$1"
BASE_ADDR="${2:-0x80000000}"

# Path to your OpenOCD config
OPENOCD_CFG="hardware/fpga/boards/axku5/axku5.cfg"

# Run OpenOCD once, let it:
#   - init
#   - assert ndmreset (hold core in reset)
#   - source the Tcl SBA loader
#   - load the binary via SBA to BASE_ADDR
#   - clear SBA errors (SBCS)
#   - release ndmreset so core starts running
#   - shutdown
openocd -f "$OPENOCD_CFG" \
  -c "init; \
      echo \"load_sba.sh: dmactive=1, ndmreset=0\"; \
      riscv dmi_write 0x10 0x00000001; \
      echo \"load_sba.sh: Asserting ndmreset (core in reset)\"; \
      riscv dmi_write 0x10 0x00000003; \
      echo \"load_sba.sh: Loading '$BIN' to $BASE_ADDR via SBA\"; \
      source utils/load_sba.tcl; \
      set bin \"$BIN\"; \
      set base \"$BASE_ADDR\"; \
      load_sba \$bin \$base; \
      echo \"load_sba.sh: Clearing SBA errors in SBCS\"; \
      set clear_errors_cfg [expr { (1 << 21) | (1 << 23) | (0x7 << 12) }]; \
      riscv dmi_write 0x38 \$clear_errors_cfg; \
      riscv dmi_read  0x38; \
      echo \"load_sba.sh: Releasing ndmreset (core starts at $BASE_ADDR)\"; \
      riscv dmi_write 0x10 0x00000001; \
      shutdown"
