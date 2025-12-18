#!/usr/bin/env bash
# run_elf.sh - Load and run a RISC-V ELF on CVA6 via OpenOCD+GDB with optional timeout.
#
# Usage:
#   ./run_elf.sh path/to/program.elf [timeout_seconds]
#
# This script loads the ELF, runs it, and automatically exits GDB after the specified
# timeout (default: 5 seconds). Useful for programs that enter infinite loops at the end.
#
# Notes:
#   - OpenOCD must already be running on localhost:3333
#   - Press Ctrl-C during execution to stop early
#   - Output from the program appears in the OpenOCD terminal or via UART
#
# Examples:
#   # Run with default 5 second timeout
#   ./run_elf.sh apps/bin/dhrystone
#
#   # Run with 10 second timeout
#   ./run_elf.sh apps/bin/dhrystone 10

set -e

if [ $# -lt 1 ]; then
  echo "Usage: $0 path/to/program.elf [timeout_seconds]" 1>&2
  exit 1
fi

ELF="$1"
TIMEOUT="${2:-5}"  # Default 5 seconds if not specified

# Select GDB command (same logic as load_elf.sh)
if [ -n "$GDB" ]; then
  GDB_CMD="$GDB"
else
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

echo "Loading and running $ELF with ${TIMEOUT}s timeout..."
echo "Press Ctrl-C to stop early"
echo ""

# Create a temporary GDB command file
TMPFILE=$(mktemp /tmp/gdb_commands.XXXXXX)
trap "rm -f $TMPFILE" EXIT

cat > "$TMPFILE" << EOF
target extended-remote localhost:3333
monitor reset halt
load
set \$pc = 0x80000000
continue
EOF

# Run GDB in batch mode with timeout
# The timeout command will kill GDB after the specified time
timeout --foreground --signal=INT "${TIMEOUT}" "$GDB_CMD" "$ELF" -batch -x "$TMPFILE" || {
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 124 ]; then
    echo ""
    echo "Timeout reached after ${TIMEOUT}s - program stopped"
    exit 0
  else
    echo ""
    echo "GDB exited with code $EXIT_CODE"
    exit $EXIT_CODE
  fi
}

echo ""
echo "Program completed"
