# FPGA Utility Scripts

This directory contains helper scripts for working with the CVA6 FPGA targets (e.g. AXKU5), in particular for driving OpenOCD, GDB, and monitoring UART output.

The scripts assume you are running commands from the **repository root**.

## Environment setup

Before using these scripts, it is recommended to source the common environment script so that the `RISCV` variable (and other tool paths) are set:

```bash
source ./sourceme.sh
```

After this, `RISCV` will typically point to your RISC-V toolchain prefix, e.g.:

```bash
echo "$RISCV"
/opt/ariane/riscv
```

The scripts will use:

- `$RISCV/bin/riscv-none-elf-gdb` if `RISCV` is set, or
- `riscv-none-elf-gdb` from your `PATH` otherwise.

## OpenOCD configuration

Launch OpenOCD in a separate terminal using the generic config:

```bash
openocd -f fpga/scripts/openocd.cfg
```

This should start an OpenOCD server listening on `localhost:3333` for GDB connections.

## Building FPGA bitstreams

From the repository root you can build FPGA bitstreams using the top-level Makefile. For example, to build for the AXKU5 board with the CV64A6 IMAFDC SV39 configuration:

```bash
make fpga BOARD=axku5 target=cv64a6_imafdc_sv39
```

Replace `axku5` and the `target` as needed for other boards and configurations.

## Monitoring UART output (picocom / minicom)

On AXKU5, the CVA6 SoC UART is connected to the on-board CP210x USB-UART bridge. After a reboot, the device enumeration can change, so you should verify which `/dev/ttyUSBx` corresponds to the CP210x.

Typical mapping (adjust as needed based on `lsusb` / `dmesg`):

- `/dev/ttyUSB2` → Silicon Labs CP210x UART Bridge
- `/dev/ttyUSB1` → FT232H (FPGA JTAG/programming)
- `/dev/ttyUSB0` → Olimex JTAG

### Using picocom

Start picocom on the UART device (example for `/dev/ttyUSB2`):

```bash
picocom -b 115200 /dev/ttyUSB2
```

Settings:

- Baud rate: 115200
- Data bits: 8
- Parity: none
- Stop bits: 1
- Flow control: none

You should see something like:

```text
picocom v2024-07

port is        : /dev/ttyUSB2
flowcontrol    : none
baudrate is    : 115200
parity is      : none
databits are   : 8
stopbits are   : 1
...
Terminal ready
Hello World from AXKU5 UART!
```

Press `C-a` then `C-x` to exit picocom.

### Using minicom (optional)

If you prefer minicom:

Start:

```bash
minicom -b 115200 -D /dev/ttyUSB2
```

Inside minicom, you can press `Ctrl-A` then `Z` to bring up the help menu. Ensure:

- Serial device: `/dev/ttyUSB2` (or whichever device is your CP210x)
- 115200 8N1
- No hardware or software flow control

Minicom will also display any UART text (e.g., “Hello World from AXKU5 UART!”) once the ELF is loaded and running.

## `load_elf.sh`

Script: [`load_elf.sh`](fpga/scripts/load_elf.sh:1)

This is a convenience wrapper to load and start a RISC-V ELF on the CVA6 FPGA via OpenOCD + GDB.

### Basic usage

```bash
fpga/scripts/load_elf.sh path/to/program.elf
```

Example (from repo root):

```bash
# 1. Environment setup
source ./sourceme.sh

# 2. Start OpenOCD in a separate terminal
openocd -f fpga/scripts/openocd.cfg

# 3. Load and run the ELF
fpga/scripts/load_elf.sh fpga/tests/out/hello_world_uart.elf
```

What this does internally:

1. Start `riscv-none-elf-gdb` on the given ELF.
2. Connects to OpenOCD: `target remote localhost:3333`.
3. Issues `monitor reset halt` to reset and halt the core.
4. Issues `load` to program the ELF into the target memory.
5. Sets the PC to `0x8000_0000`.
6. Issues `continue` to start execution.

By default, GDB stays open interactively after these steps.

### Passing additional GDB commands

Any extra arguments passed after the ELF path are forwarded to GDB. This is useful if you want a **one-shot** programming flow that also shuts down OpenOCD and quits GDB afterwards.

Example: load & run, then shut down OpenOCD and exit GDB:

```bash
source ./sourceme.sh

# OpenOCD already running in another terminal:
#   openocd -f fpga/scripts/openocd.cfg

fpga/scripts/load_elf.sh fpga/tests/out/hello_world_uart.elf \
  -ex "monitor shutdown" \
  -ex "quit"
```

In this mode:

- `monitor shutdown` asks OpenOCD to terminate.
- `quit` exits GDB once the previous commands complete.

### Running with a custom GDB

If you want to override the GDB binary (for example, use a specific build), set the `GDB` environment variable:

```bash
GDB=/path/to/custom-riscv-gdb \
  fpga/scripts/load_elf.sh fpga/tests/out/hello_world_uart.elf
```

Otherwise the script will default to:

- `$RISCV/bin/riscv-none-elf-gdb` if `RISCV` is set, or
- `riscv-none-elf-gdb` if `RISCV` is not set.