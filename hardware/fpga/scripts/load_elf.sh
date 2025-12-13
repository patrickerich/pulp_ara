#!/usr/bin/env bash
# load_elf.sh - Convenience wrapper to load and run a RISC-V ELF on CVA6 via OpenOCD+GDB.
#
# Usage:
#   ./load_elf.sh path/to/program.elf [additional GDB -ex commands...]
#
# Notes:
#   - It is recommended to first run:
#       source ./sourceme.sh
#     from the repository root so that the RISCV environment variable is set.
#   - If RISCV is set, this script uses:
#       $RISCV/bin/riscv-none-elf-gdb
#     otherwise it falls back to `riscv-none-elf-gdb` in PATH.
#   - OpenOCD must already be running and listening on localhost:3333, e.g.:
#       openocd -f fpga/scripts/openocd.cfg
#
# Examples:
#   Simple interactive session (stays in GDB after starting the program):
#     ./load_elf.sh fpga/tests/out/hello_world_uart.elf
#
#   One-shot load & run, then shut down OpenOCD and quit GDB:
#     ./load_elf.sh fpga/tests/out/hello_world_uart.elf \
#       -ex "monitor shutdown" \
#       -ex "quit"

set -e

if [ $# -lt 1 ]; then
  echo "Usage: $0 path/to/program.elf [additional GDB -ex commands...]" 1>&2
  exit 1
fi

ELF="$1"
shift

# Select GDB command
if [ -n "$GDB" ]; then
  GDB_CMD="$GDB"
elif [ -n "$RISCV" ]; then
  GDB_CMD="$RISCV/bin/riscv-none-elf-gdb"
else
  GDB_CMD="riscv-none-elf-gdb"
fi

# Default GDB command sequence:
#   - connect to OpenOCD
#   - reset & halt the core
#   - load the ELF
#   - set PC to 0x80000000 (CV6 reset vector / ROM entry)
#   - continue execution
#
# Any extra arguments are passed verbatim to GDB, so you can add
# additional -ex commands like "monitor shutdown" and "quit".
exec "$GDB_CMD" "$ELF" \
  -ex "target remote localhost:3333" \
  -ex "monitor reset halt" \
  -ex "load" \
  -ex "set \$pc = 0x80000000" \
  -ex "continue" \
  "$@"