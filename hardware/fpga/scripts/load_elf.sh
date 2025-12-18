#!/usr/bin/env bash
# load_elf.sh - Convenience wrapper to load and run a RISC-V ELF on CVA6 via OpenOCD+GDB.
#
# Usage:
#   ./load_elf.sh path/to/program.elf [additional GDB -ex commands...]
#
# Notes:
#   - This script automatically uses the GDB from the repo's toolchain at:
#       install/riscv-gcc/bin/riscv64-unknown-elf-gdb
#   - You can override with the $GDB environment variable if needed.
#   - Falls back to $RISCV/bin/riscv-none-elf-gdb or system PATH if repo GDB not found.
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
# Priority:
#   1. $GDB environment variable (user override)
#   2. Repo's toolchain (install/riscv-gcc/bin/riscv64-unknown-elf-gdb)
#   3. $RISCV/bin/riscv-none-elf-gdb (legacy)
#   4. System PATH fallback
if [ -n "$GDB" ]; then
  GDB_CMD="$GDB"
else
  # Try to find repo root and use its toolchain
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  REPO_GDB="$REPO_ROOT/install/riscv-gcc/bin/riscv64-unknown-elf-gdb"

  if [ -x "$REPO_GDB" ]; then
    GDB_CMD="$REPO_GDB"
  elif [ -n "$RISCV" ]; then
    GDB_CMD="$RISCV/bin/riscv-none-elf-gdb"
  else
    GDB_CMD="riscv64-unknown-elf-gdb"
  fi
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
  -ex "target extended-remote localhost:3333" \
  -ex "monitor reset halt" \
  -ex "load" \
  -ex "set \$pc = 0x80000000" \
  -ex "continue" \
  "$@"