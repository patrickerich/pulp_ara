# Ara

[![ci](https://github.com/pulp-platform/ara/actions/workflows/ci.yml/badge.svg)](https://github.com/pulp-platform/ara/actions/workflows/ci.yml)

Ara is a vector unit working as a coprocessor for the CVA6 core.
It supports the RISC-V Vector Extension, [version 1.0](https://github.com/riscv/riscv-v-spec/releases/tag/v1.0).

Prototypical documentation can be found at https://pulp-platform.github.io/ara

## Dependencies

Check `DEPENDENCIES.md` for a list of hardware and software dependencies of Ara.

## Supported instructions

Check `FUNCTIONALITIES.md` to check which instructions are currently supported by Ara.

## Get started

Make sure you clone this repository recursively to get all the necessary submodules:

```bash
make git-submodules
```

If the repository path of any submodule changes, run the following command to change your submodule's pointer to the remote repository:

```bash
git submodule sync --recursive
```

## Toolchain

Ara requires a RISC-V LLVM toolchain capable of understanding the vector extension, version 1.0.

To build this toolchain, run the following command in the project's root directory.

```bash
# Build the LLVM toolchain
make toolchain-llvm
```

Ara also requires an updated Spike ISA simulator, with support for the vector extension.
There are linking issues with the standard libraries when using newer CC/CXX versions to compile Spike. Therefore, here we resort to older versions of the compilers. If there are problems with dynamic linking, use:
`make riscv-isa-sim LDFLAGS="-static-libstdc++"`. Spike was compiled successfully using gcc and g++ version 7.2.0.

To build Spike, run the following command in the project's root directory.

```bash
# Build Spike
make riscv-isa-sim
```

## Verilator

Ara requires an updated version of Verilator, for RTL simulations.

To build it, run the following command in the project's root directory.

```bash
# Build Verilator
make verilator
```

## Configuration

Ara's parameters are centralized in the `config` folder, which provides several configurations to the vector machine.
Please check `config/README.md` for more details.

Prepend `config=chosen_ara_configuration` to your Makefile commands, or export the `ARA_CONFIGURATION` variable to choose a configuration other than the `default` one.

## Software

### Build Applications

The `apps` folder contains example applications that work on Ara. Run the following command to build an application. E.g., `hello_world`:

```bash
cd apps
make bin/hello_world
```

#### UART Output for FPGA

By default, applications use `printf()` that outputs to a simulated UART (`fake_uart`) for RTL simulation. To redirect `printf()` output to a real hardware UART (for FPGA deployment), compile applications with the `UART_OUTPUT` macro:

```bash
# Build dhrystone with UART output enabled
ENV_DEFINES=-DUART_OUTPUT make -C apps dhrystone

# Build any application with UART output
ENV_DEFINES=-DUART_OUTPUT make -C apps bin/<app_name>
```

When `UART_OUTPUT` is defined:
- The UART hardware at memory address `0xC0000000` is automatically initialized at startup (before `main()`)
- All `printf()` calls are redirected to the hardware UART (115200 baud, 8N1 format)
- Output can be observed via a serial terminal connected to the FPGA's UART interface
- No application source code modifications are required

When compiled **without** `UART_OUTPUT` (default behavior):
- Applications work normally in RTL simulation (Verilator, ModelSim, Xcelium)
- `printf()` output goes to `fake_uart` which is captured by the simulation environment
- This is the standard mode for running simulations

**Example workflow for FPGA:**
```bash
# 1. Build application with UART output
ENV_DEFINES=-DUART_OUTPUT make -C apps dhrystone

# 2. Load the binary to FPGA (method depends on your setup)
# 3. Connect to UART at 115200 baud to see printf output
```

### SPIKE Simulation

All the applications can be simulated with SPIKE. Run the following command to build and run an application. E.g., `hello_world`:

```bash
cd apps
make bin/hello_world.spike
make spike-run-hello_world
```

### RISC-V Tests

The `apps` folder also contains the RISC-V tests repository, including a few unit tests for the vector instructions. Run the following command to build the unit tests:

```bash
cd apps
make riscv_tests
```

## RTL Simulation

### Hardware dependencies

The Ara repository depends on external IPs and uses Bender to handle the IP dependencies.
To install Bender and initialize all the hardware IPs, run the following commands:

```bash
# Go to the hardware folder
cd hardware
# Install Bender and checkout all the IPs
make checkout
```

### Patches (only once!)

Note: this step is required only once, and needs to be repeated ONLY if the IP hardware dependencies are deleted and checked out again.

Some of the IPs need to be patched to work with Verilator.

```bash
# Go to the hardware folder
cd hardware
# Apply the patches (only need to run this once)
make apply-patches
```

### Simulation

To simulate the Ara system with ModelSim, go to the `hardware` folder, which contains all the SystemVerilog files. Use the following command to run your simulation:

```bash
# Go to the hardware folder
cd hardware
# Only compile the hardware without running the simulation.
make compile
# Run the simulation with the *hello_world* binary loaded
app=hello_world make sim
# Run the simulation with the *some_binary* binary. This allows specifying the full path to the binary
preload=/some_path/some_binary make sim
# Run the simulation without starting the gui
app=hello_world make simc
```

#### Xcelium Simulation

For users with access to Cadence Xcelium, you can also run simulations using:

```bash
# Go to the hardware folder
cd hardware
# Compile the design with Xcelium
make compile_xcelium
# Run the simulation with the *hello_world* binary loaded (interactive with GUI)
app=hello_world make simx
# Run the simulation without starting the GUI
app=hello_world make simxc
# Run with a custom binary
preload=/some_path/some_binary make simx
# Enable waveform dumping (default SHM)
app=hello_world trace=1 make simx
# Enable VCD waveform dumping
format=vcd app=hello_world trace=1 make simx
```

By default (trace=1), waveforms are dumped in SHM format to `hardware/build/xcelium_waves.shm/` and can be viewed with SimVision.
To dump VCD instead, pass `format=vcd` (or `wavefmt=vcd`); the file `hardware/build/xcelium_waves.vcd` will be produced.

#### Verilator Simulation

We also provide the `simv` makefile target to run simulations with the Verilator model.

```bash
# Go to the hardware folder
cd hardware
# Apply the patches (only need to run this once)
make apply-patches
# Only compile the hardware without running the simulation.
make verilate
# Run the simulation with the *hello_world* binary loaded
app=hello_world make simv
```

Portable linking notes (libelf/libatomic)
- The Verilator build links against libelf and, on some systems, requires libatomic too.
- The makefile now auto-detects libelf via pkg-config, with a fallback to -lelf, and links -latomic by default.
- You can customize via these knobs in the Verilator build:
  - ELF_LIBS is auto-set to the output of: pkg-config --silence-errors --libs libelf || echo -lelf
  - ATOMIC_LIBS defaults to -latomic. Set ATOMIC_LIBS= (empty) to disable.
  - EXTRA_LDFLAGS lets you add site-specific -L/-Wl paths as needed.

Examples:
```bash
# Typical build (auto-detect libelf via pkg-config, link libatomic)
make -C hardware verilate

# If libelf is installed in a non-default directory
make -C hardware verilate EXTRA_LDFLAGS="-L/opt/libelf/lib"

# If your platform does not need libatomic, you can disable it
make -C hardware verilate ATOMIC_LIBS=

# Combine both: custom search path and disable atomic
make -C hardware verilate EXTRA_LDFLAGS="-L/opt/libelf/lib" ATOMIC_LIBS=

# RHEL with gcc-toolset-14 (fixes: "mold: fatal: library not found: atomic")
make -C hardware verilate EXTRA_LDFLAGS="-L/opt/rh/gcc-toolset-14/root/usr/lib/gcc/x86_64-redhat-linux/14"
```

The corresponding logic lives in:
- hardware/Makefile (ELF_LIBS auto-detect, ATOMIC_LIBS default, EXTRA_LDFLAGS hook)

It is also possible to simulate the unit tests compiled in the `apps` folder. Given the number of unit tests, we use Verilator. Use the following command to install Verilator, verilate the design, and run the simulation:

```bash
# Go to the hardware folder
cd hardware
# Apply the patches (only need to run this once)
make apply-patches
# Verilate the design
make verilate
# Run the tests
make riscv_tests_simv
```

Alternatively, you can also use the `riscv_tests` target at Ara's top-level Makefile to both compile the RISC-V tests and run their simulation.

### Traces

Add `trace=1` to the `verilate`, `simv`, and `riscv_tests_simv` commands to generate waveform traces in the `fst` format.
Traces are saved to `hardware/build/verilator_waves.fst` and can be viewed with:
```bash
gtkwave hardware/build/verilator_waves.fst
```

For Xcelium simulations, add `trace=1` to enable waveform dumping.
By default SHM traces are saved to `hardware/build/xcelium_waves.shm/` (view with SimVision).
To dump VCD instead, pass `format=vcd` (or `wavefmt=vcd`), which produces `hardware/build/xcelium_waves.vcd`.

### Ideal Dispatcher mode

CVA6 can be replaced by an ideal FIFO that dispatches the vector instructions to Ara with the maximum issue-rate possible.
In this mode, only Ara and its memory system affect performance.
This mode has some limitations:
 - The dispatcher is a simple FIFO. Ara and the dispatcher cannot have complex interactions.
 - Therefore, the vector program should be fire-and-forget. There cannot be runtime dependencies from the vector to the scalar code.
 - Not all the vector instructions are supported, e.g., the ones that use the `rs2` register.

To compile a program and generate its vector trace:

```bash
cd apps
make bin/${program}.ideal
```

This command will generate the `ideal` binary to be loaded in the L2 memory for the simulation (data accessed by the vector code).
To run the system in Ideal Dispatcher mode:

```bash
cd hardware
make sim app=${program} ideal_dispatcher=1
```

### VCD Dumping

It's possible to dump VCD files for accurate activity-based power analyses. To do so, use the `vcd_dump=1` option to compile the program and to run the simulation:

```bash
make -C apps bin/${program} vcd_dump=1
make -C hardware simc app=${program} vcd_dump=1
```

Currently, the following kernels support automatic VCD dumping: `fmatmul`, `fconv3d`, `fft`, `dwt`, `exp`, `cos`, `log`, `dropout`, `jacobi2d`.

### Linting Flow

We also provide Synopsys Spyglass linting scripts in the hardware/spyglass. Run make lint in the hardware folder, with a specific MemPool configuration, to run the tests associated with the lint_rtl target.

### Support for `rvv-bench`

To run `rvv-bench` instructions benchmark, execute:

```bash
make rvv-bench
make -C apps bin/rvv
make -C hardware simv app=rvv
```

## FPGA implementation and Linux flow

This repository currently contains **two FPGA-related flows**:

1) **AXKU5 “standalone” bring-up flow (Vivado + OpenOCD)**
   A minimal FPGA top that targets bring-up and debug of the CVA6/Ara system via external JTAG (OpenOCD/GDB).
   - Ara top: `ara_fpga_wrap`
   - CVA6-only baseline top: `cva6_fpga_wrap` (useful to isolate Ara-related issues)

2) **Cheshire FPGA flow (VCU118/VCU128, bare-metal + Linux)**
   A separate (Cheshire-based) integration that supports VCU128/VCU118 in bare-metal and with Linux.

### AXKU5 standalone FPGA flow (Vivado + OpenOCD)

#### 0) Dependencies / checkout
Make sure the hardware dependencies are checked out (Bender-managed):

```bash
make -C hardware checkout
```

If you have not done so before (or after re-checking out deps), apply patches:

```bash
make -C hardware apply-patches
```

#### 1) Select an Ara configuration
The AXKU5 FPGA flow reuses the existing Ara configuration system. Example:

- `config=2_lanes_256`

You can either pass `config=...` to commands, or export `ARA_CONFIGURATION`.

#### 2) Generate the synthesis filelist (Ara top or CVA6-only top)

**Ara top (CVA6 + Ara, default):**
```bash
make -C hardware synth_flist_fpga_wrap FPGA_TOP=ara_fpga_wrap config=2_lanes_256
```

Notes:
- `FPGA_TOP=ara_fpga_wrap` is the default; passing it explicitly just makes intent obvious.
- The current `ara_fpga_wrap`/`ara_soc_fpga` integration uses the same “known-good” debug plumbing as the upstream OpenHW CVA6 FPGA reference:
  - `dm_top` is instantiated without overriding `DmBaseAddress`
  - the debug memory window uses `axi2mem`
  - SBA uses the standard `axi_adapter`

**CVA6-only baseline top (no Ara):**
```bash
make -C hardware synth_flist_fpga_wrap FPGA_TOP=cva6_fpga_wrap config=2_lanes_256
```

This produces:
- `hardware/build/synth_fpga_wrap_<FPGA_TOP>_<config>.f`
- `hardware/build/synth_fpga_wrap_<FPGA_TOP>_<config>_incdirs.txt`

And also keeps compatibility copies:
- `hardware/build/synth_fpga_wrap_<config>.f`
- `hardware/build/synth_fpga_wrap_incdirs_<config>.txt`

#### 3) Build the AXKU5 bitstream (batch Vivado)
The AXKU5 Vivado build script supports selecting the top module explicitly.

**Ara top (CVA6 + Ara):**
```bash
vivado -mode batch -source hardware/fpga/boards/axku5/build_axku5.tcl -tclargs 2_lanes_256 ara_fpga_wrap
```

**CVA6-only baseline top (no Ara):**
```bash
vivado -mode batch -source hardware/fpga/boards/axku5/build_axku5.tcl -tclargs 2_lanes_256 cva6_fpga_wrap
```

The build directory is created under:
- `hardware/build/build_axku5_<top>_<config>/`

And the bitstream is written as:
- `<top>_axku5_<config>.bit` (plus `.mmi`)

#### 4) OpenOCD bring-up
After programming the FPGA bitstream, start OpenOCD:

```bash
openocd -f hardware/fpga/scripts/openocd.cfg
```

This config is currently set up for an Olimex JTAG adapter and a RISC-V JTAG DTM TAP.

#### 5) Loading and running software

The repository contains helper scripts under `hardware/fpga/scripts/` for loading and running programs via OpenOCD/GDB.

**Interactive mode (for debugging):**
```bash
# Load and run interactively (stays in GDB)
./hardware/fpga/scripts/load_elf.sh apps/bin/hello_world_uart
# Then manually quit GDB with Ctrl-C followed by 'quit'
```

**Non-interactive mode (with timeout):**
```bash
# Run with automatic timeout (default 5 seconds)
./hardware/fpga/scripts/run_elf.sh apps/bin/dhrystone

# Run with custom timeout (e.g., 10 seconds)
./hardware/fpga/scripts/run_elf.sh apps/bin/dhrystone 10
```

The `run_elf.sh` script is useful for programs that enter infinite loops at the end (like most bare-metal applications). It automatically stops GDB after the specified timeout, allowing you to run benchmarks and tests without manual intervention.

**For applications with UART output:**
1. Connect a serial terminal to the FPGA's UART (115200 baud)
2. Build with `ENV_DEFINES=-DUART_OUTPUT`
3. Run with either script - output appears on the serial terminal

**Notes:**
- For Ara builds, OpenOCD may print: `Couldn't read vlenb; vector register access won't work.`
  This is usually a non-fatal probe warning and does not prevent basic halt/load/run flows; it only affects vector register access via the debugger.

### Cheshire FPGA flow (VCU118/VCU128, bare-metal + Linux)

Ara supports Cheshire's FPGA flow and can be currently implemented on VCU128 and VCU118 in bare-metal and with Linux. The tested configuration is with 2 lanes.

For information about the FPGA bare-metal and Linux flows, please refer to `cheshire/README.md`.

## Publications

If you want to use Ara, you can cite us:
```
@Article{Ara2020,
  author = {Matheus Cavalcante and Fabian Schuiki and Florian Zaruba and Michael Schaffner and Luca Benini},
  journal= {IEEE Transactions on Very Large Scale Integration (VLSI) Systems},
  title  = {Ara: A 1-GHz+ Scalable and Energy-Efficient RISC-V Vector Processor With Multiprecision Floating-Point Support in 22-nm FD-SOI},
  year   = {2020},
  volume = {28},
  number = {2},
  pages  = {530-543},
  doi    = {10.1109/TVLSI.2019.2950087}
}
```
```
@INPROCEEDINGS{9912071,
  author={Perotti, Matteo and Cavalcante, Matheus and Wistoff, Nils and Andri, Renzo and Cavigelli, Lukas and Benini, Luca},
  booktitle={2022 IEEE 33rd International Conference on Application-specific Systems, Architectures and Processors (ASAP)},
  title={A “New Ara” for Vector Computing: An Open Source Highly Efficient RISC-V V 1.0 Vector Processor Design},
  year={2022},
  volume={},
  number={},
  pages={43-51},
  doi={10.1109/ASAP54787.2022.00017}}
```
```
@ARTICLE{10500752,
  author={Perotti, Matteo and Cavalcante, Matheus and Andri, Renzo and Cavigelli, Lukas and Benini, Luca},
  journal={IEEE Transactions on Computers},
  title={Ara2: Exploring Single- and Multi-Core Vector Processing With an Efficient RVV 1.0 Compliant Open-Source Processor},
  year={2024},
  volume={73},
  number={7},
  pages={1822-1836},
  keywords={Vectors;Registers;Computer architecture;Vector processors;Multicore processing;Microarchitecture;Kernel;RISC-V;vector;ISA;RVV;processor;efficiency;multi-core},
  doi={10.1109/TC.2024.3388896}}
```
