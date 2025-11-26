# Copyright 2021 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Author: Matheus Cavalcante <matheusd@iis.ee.ethz.ch>

SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ARA_DIR := $(shell git rev-parse --show-toplevel 2>/dev/null || echo $$ARA_DIR)
INSTALL_DIR := $(abspath $(ROOT_DIR)/../install)
VERILATOR_INCLUDE := $(INSTALL_DIR)/verilator/share/verilator/include/vltstd

BENDER         := $(ROOT_DIR)/../hardware/bender
BENDER_VERSION := 0.27.3

# Choose Ara's configuration
ifndef config
	ifdef ARA_CONFIGURATION
		config := $(ARA_CONFIGURATION)
	else
		config := default
	endif
endif

# Include configuration
config_file := $(ROOT_DIR)/../config/$(config).mk
include $(abspath $(ROOT_DIR)/../config/$(config).mk)

# Clang flags for Verilator command
ifneq (${CLANG_PATH},)
	CLANG_CXXFLAGS := -CFLAGS "-nostdinc++ -isystem $(CLANG_PATH)/include/c++/v1"
	CLANG_LDFLAGS  := -LDFLAGS "-L $(CLANG_PATH)/lib -Wl,-rpath,$(CLANG_PATH)/lib -lc++ -nostdlib++"
else
	CLANG_CXXFLAGS := ""
	CLANG_LDFLAGS  := ""
endif

# Detect libelf libraries via pkg-config, fallback to -lelf
ELF_LIBS := $(shell pkg-config --silence-errors --libs libelf || echo -lelf)
# Link libatomic by default for portability (override with ATOMIC_LIBS= to disable)
ATOMIC_LIBS ?= -latomic
# Site-specific extra linker flags hook (e.g., -L/path/to/libs)
EXTRA_LDFLAGS ?=

# build path
buildpath      ?= build
resultpath     ?= results
# questa library
library        ?= work
# dpi library
dpi_library    ?= work-dpi
# verilator library
veril_library  ?= $(buildpath)/verilator
# verilator path
veril_path     ?= $(abspath $(INSTALL_DIR)/verilator/bin)
# verilator top-level
veril_top      ?= ara_tb_verilator
# Top level module to compile
top_level      ?= ara_tb
# Questa version
ifeq ($(vcd_dump), 1)
  questa_version ?= 2019.3
else
  questa_version ?= 2021.3
endif
# QuestaSim command
questa_cmd     ?= questa-$(questa_version)
# QuestaSim arguments
questa_args    ?=
# Xcelium version
xcelium_version ?= 23.09
# Xcelium command
xcelium_cmd     ?= xrun
# Xcelium arguments
xcelium_args    ?=
# Path to the binaries
app_path       ?= $(abspath $(ROOT_DIR)/../apps/bin)
# Path to ideal dispatcher vtraces
vtrace_path    ?= $(abspath $(ROOT_DIR)/../apps/ideal_dispatcher/vtrace)

ideal          ?=
ifeq ($(ideal_dispatcher), 1)
  vtrace       = $(vtrace_path)/$(app).vtrace
  bender_defs += --define IDEAL_DISPATCHER=1 --define VTRACE="$(vtrace)" --define N_VINSN=$(shell wc -l $(vtrace) | cut -d " " -f 1)
  ideal        = "_ideal"
endif

ifeq ($(vcd_dump), 1)
  vcd_path    ?= ../vcd/$(app).vcd
  bender_defs += --define VCD_DUMP=1 --define VCD_PATH=$(vcd_path)
endif

# Check if the specified QuestaSim version exists
ifeq (, $(shell which $(questa_cmd)))
  # Spaces are needed for indentation here!
  $(warning "Specified QuestaSim version ($(questa_cmd)) not found in PATH $(PATH)")
  questa_cmd =
endif

# Check if Xcelium is available
ifeq (, $(shell which $(xcelium_cmd)))
  xcelium_cmd =
endif

questa_args += +UVM_NO_RELNOTES
ifdef app
ifeq ($(ideal_dispatcher), 1)
	preload ?= "$(app_path)/$(app).ideal"
else
	preload ?= "$(app_path)/$(app)"
endif
endif
ifdef preload
	questa_args += +PRELOAD=$(preload)
endif
questa_args += -sv_lib $(dpi_library)/ara_dpi -work $(library) -voptargs=+acc
questa_args += -suppress vsim-3009 -suppress vopt-7033

# Xcelium simulation arguments
ifdef app
ifeq ($(ideal_dispatcher), 1)
	xcelium_preload ?= "$(app_path)/$(app).ideal"
else
	xcelium_preload ?= "$(app_path)/$(app)"
endif
endif
ifdef preload
	xcelium_preload ?= $(preload)
endif
ifdef xcelium_preload
	xcelium_args += +PRELOAD=$(xcelium_preload)
endif
xcelium_args += -sv_lib $(dpi_library)/ara_dpi_xcelium -work $(library)
xcelium_args += -access +rwc -64bit

# DPI source files
dpi   := $(patsubst tb/dpi/%.cc,$(buildpath)/$(dpi_library)/%.o,$(wildcard tb/dpi/*.cc))

vlog_args += -suppress vlog-2583 -suppress vlog-13314 -suppress vlog-13233
vlog_args += -work $(library)

# Xcelium compilation arguments
xcelium_compile_args += -64bit -sv -access +rwc
xcelium_compile_args += -work $(library)
xcelium_compile_args += -disable_sem2009
xcelium_compile_args += -errormax 0
xcelium_compile_args += -timescale 1ns/1ps
# Align timing semantics to be cycle-accurate without inertial delays.
# This avoids backpressure differences without redefining VERILATOR in RTL.
xcelium_compile_args += -delay_mode zero

# Bender
# Defines
bender_defs += --define NR_LANES=$(nr_lanes) --define VLEN=$(vlen) --define ARIANE_ACCELERATOR_PORT=1
bender_defs_veril := $(bender_defs) --define COMMON_CELLS_ASSERTS_OFF
# Targets
bender_common_targs := -t rtl -t cv64a6_imafdcv_sv39 -t tech_cells_generic_include_tc_sram -t tech_cells_generic_include_tc_clk -t exclude_first_pass_decoder
bender_targs_simc     := $(bender_common_targs) -t ara_test -t cva6_test
bender_targs_veril    := $(bender_common_targs) -t ara_test -t cva6_test -t verilator
bender_targs_spyglass := $(bender_common_targs) -t spyglass

# Default target
all: compile

# Build path
$(buildpath):
	mkdir -p $(buildpath)

.PHONY: bender update
# Bender
bender: $(BENDER)
$(BENDER):
	@[ -x $(BENDER) ] && echo "Bender already exists." || \
	curl --proto '=https' --tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh	-s -- $(BENDER_VERSION)
	@echo "$$(./bender --version) available."

update: $(BENDER) $(ROOT_DIR)/../Bender.yml
	rm -rf $(ROOT_DIR)/../hardware/deps/*
	$(BENDER) update -f
	$(BENDER) checkout

checkout: $(BENDER)
	$(BENDER) checkout

# Patches
.PHONY: apply-patches
apply-patches: patches
	cd deps/tech_cells_generic && git apply ../../patches/0001-tech-cells-generic-sram.patch

# Library
.PHONY: lib
lib: $(buildpath) $(buildpath)/$(library)
$(buildpath)/$(library):
	cd $(buildpath) && $(questa_cmd) vlib $(library) && $(questa_cmd) vmap $(library) $(library)

# Compilation
.PHONY: compile
compile: dpi lib $(buildpath) bender $(buildpath)/compile_$(config).tcl
$(buildpath)/compile_$(config).tcl: $(config_file) Makefile ../Bender.yml $(shell find src -type f) $(shell find ../config -type f) $(shell find include -type f) $(shell find tb -type f) $(shell find deps -type f)
	$(BENDER) script vsim --vlog-arg="$(vlog_args)" $(bender_targs_simc) $(bender_defs) > $(buildpath)/compile_$(config).tcl
	echo "exit" >> $(buildpath)/compile_$(config).tcl
	cd $(buildpath) && $(questa_cmd) vsim -work $(library) -c -do compile_$(config).tcl
	# Rename the file if compilation did not succeed
	if [ `cat $(buildpath)/transcript | grep "\*\* Error" | wc -l` -ne 0 ]; then mv $(buildpath)/compile_$(config).tcl $(buildpath)/compile_$(config).tcl.ERROR; fi

# Simulation
.PHONY: sim
sim: compile
	cd $(buildpath) && \
	$(questa_cmd) vsim $(questa_args) $(library).$(top_level) -do ../scripts/run$(ideal).tcl
	./scripts/return_status.sh $(buildpath)/transcript

.PHONY: simc
simc: compile
	cd $(buildpath) && \
	$(questa_cmd) vsim -c $(questa_args) $(library).$(top_level) -do "run -a"
	./scripts/return_status.sh $(buildpath)/transcript

# Xcelium compilation
.PHONY: compile_xcelium
compile_xcelium: dpi_xcelium $(buildpath) bender $(buildpath)/compile_xcelium_$(config).f
$(buildpath)/compile_xcelium_$(config).f: $(config_file) Makefile ../Bender.yml $(shell find src -type f) $(shell find ../config -type f) $(shell find include -type f) $(shell find tb -type f) $(shell find deps -type f)
	$(BENDER) script flist $(bender_targs_simc) $(bender_defs) | grep -v '\.svh$$' > $(buildpath)/compile_xcelium_$(config).f
	$(BENDER) script vsim $(bender_targs_simc) $(bender_defs) | grep '+incdir+' | sed 's|.*"+incdir+\$$ROOT/hardware/\(.*\)" \\|-incdir ../\1|' | tr '\n' ' ' > $(buildpath)/xcelium_incdirs_$(config).txt
	cd $(buildpath) && $(xcelium_cmd) $(xcelium_compile_args) $$(cat xcelium_incdirs_$(config).txt) -f compile_xcelium_$(config).f \
		-defparam ara_tb.NrLanes=$(nr_lanes) -defparam ara_tb.VLEN=$(vlen) -elaborate -top $(library).$(top_level)

# Synthesis filelist including ara_soc_wrap.sv
.PHONY: synth_flist_wrap
synth_flist_wrap: $(buildpath) bender $(buildpath)/synth_wrap_$(config).f $(buildpath)/synth_wrap_incdirs_$(config).txt

$(buildpath)/synth_wrap_$(config).f: $(config_file) Makefile ../Bender.yml src/ara_soc_wrap.sv
	# Generate a temporary raw list (no .svh, skip simulation-only and verification-only modules)
	$(BENDER) script flist $(bender_targs_simc) $(bender_defs) \
	  | grep -v '\.svh$$' \
	  | grep -v 'pad_functional.sv' \
	  | grep -v 'accel_dispatcher_ideal.sv' \
	  | grep -v 'ara_tb.sv' \
	  > $(buildpath)/synth_wrap_$(config).tmp
	# Start the final flist with all package files so packages are seen first by the synthesizer
	grep '_pkg\.sv$$' $(buildpath)/synth_wrap_$(config).tmp > $(buildpath)/synth_wrap_$(config).f || true
	# Append all remaining SystemVerilog sources
	grep -v '_pkg\.sv$$' $(buildpath)/synth_wrap_$(config).tmp >> $(buildpath)/synth_wrap_$(config).f || true
	# Cleanup temporary file
	rm $(buildpath)/synth_wrap_$(config).tmp
	# Append the wrapper explicitly so synthesis can use ara_soc_wrap as top
	echo "$(ROOT_DIR)/src/ara_soc_wrap.sv" >> $(buildpath)/synth_wrap_$(config).f

$(buildpath)/synth_wrap_incdirs_$(config).txt: $(config_file) Makefile ../Bender.yml
	$(BENDER) script vsim $(bender_targs_simc) $(bender_defs) | grep '+incdir+' | \
		sed 's|.*"+incdir+\$$ROOT/hardware/\(.*\)".*|-incdir ../\1|' | tr '\n' ' ' > $(buildpath)/synth_wrap_incdirs_$(config).txt


# Synthesis filelist including ara_fpga_wrap.sv (FPGA-oriented top)
.PHONY: synth_flist_fpga_wrap
synth_flist_fpga_wrap: $(buildpath) bender $(buildpath)/synth_fpga_wrap_$(config).f $(buildpath)/synth_fpga_wrap_incdirs_$(config).txt

$(buildpath)/synth_fpga_wrap_$(config).f: $(config_file) Makefile ../Bender.yml fpga/src/ara_fpga_wrap.sv
	# Generate a temporary raw list (no .svh, skip simulation-only and verification-only modules)
	$(BENDER) script flist $(bender_targs_simc) $(bender_defs) \
	  | grep -v '\.svh$$' \
	  | grep -v 'pad_functional.sv' \
	  | grep -v 'accel_dispatcher_ideal.sv' \
	  | grep -v 'ara_tb.sv' \
	  | grep -v 'tech_cells_generic/src/rtl/tc_sram.sv' \
	  | grep -v 'tech_cells_generic/src/rtl/tc_clk.sv' \
	  > $(buildpath)/synth_fpga_wrap_$(config).tmp
	# Start the final flist with all package files so packages are seen first by the synthesizer
	grep '_pkg\.sv$$' $(buildpath)/synth_fpga_wrap_$(config).tmp > $(buildpath)/synth_fpga_wrap_$(config).f || true
	# Append all remaining SystemVerilog sources
	grep -v '_pkg\.sv$$' $(buildpath)/synth_fpga_wrap_$(config).tmp >> $(buildpath)/synth_fpga_wrap_$(config).f || true
	# Cleanup temporary file
	rm $(buildpath)/synth_fpga_wrap_$(config).tmp
	# Append the FPGA wrapper explicitly so synthesis can use ara_fpga_wrap as top
	echo "$(ROOT_DIR)/fpga/src/ara_fpga_wrap.sv" >> $(buildpath)/synth_fpga_wrap_$(config).f
	# Append Xilinx-specific tech-cell implementations for SRAM and clock
	echo "$(ROOT_DIR)/deps/tech_cells_generic/src/fpga/tc_sram_xilinx.sv" >> $(buildpath)/synth_fpga_wrap_$(config).f
	echo "$(ROOT_DIR)/deps/tech_cells_generic/src/fpga/tc_clk_xilinx.sv" >> $(buildpath)/synth_fpga_wrap_$(config).f
	# Append UART IP and common_cells FIFO explicitly
	echo "$(ROOT_DIR)/fpga/src/uart.sv" >> $(buildpath)/synth_fpga_wrap_$(config).f
	echo "$(ROOT_DIR)/deps/common_cells/src/fifo_v3.sv" >> $(buildpath)/synth_fpga_wrap_$(config).f

$(buildpath)/synth_fpga_wrap_incdirs_$(config).txt: $(config_file) Makefile ../Bender.yml
	$(BENDER) script vsim $(bender_targs_simc) $(bender_defs) | grep '+incdir+' | \
		sed 's|.*"+incdir+\$$ROOT/hardware/\(.*\)".*|-incdir ../\1|' | tr '\n' ' ' > $(buildpath)/synth_fpga_wrap_incdirs_$(config).txt
# Xcelium simulation (interactive with GUI)
.PHONY: simx
simx: compile_xcelium
	cd $(buildpath) && \
	$(if $(trace),XCELIUM_TRACE=1,) $(if $(format),XCELIUM_WAVE_FORMAT=$(format),$(if $(wavefmt),XCELIUM_WAVE_FORMAT=$(wavefmt),)) $(xcelium_cmd) -R $(xcelium_args) -gui -input ../scripts/xcelium.tcl
	@if [ -f $(buildpath)/xcelium.log ]; then \
		./scripts/return_status.sh $(buildpath)/xcelium.log; \
	fi

# Xcelium simulation (batch mode)
.PHONY: simxc
simxc: compile_xcelium
	cd $(buildpath) && \
	$(if $(trace),XCELIUM_TRACE=1,) $(if $(format),XCELIUM_WAVE_FORMAT=$(format),$(if $(wavefmt),XCELIUM_WAVE_FORMAT=$(wavefmt),)) $(xcelium_cmd) -R $(xcelium_args) -batch -input ../scripts/xcelium.tcl
	@if [ -f $(buildpath)/xcelium.log ]; then \
		./scripts/return_status.sh $(buildpath)/xcelium.log; \
	fi

# RISC-V Tests simulation
APPS_DIR := $(abspath $(ROOT_DIR)/../apps)
TESTS_DIR := $(APPS_DIR)/riscv-tests/isa
include $(APPS_DIR)/common/riscv_tests.mk

tests := $(ara_tests) $(cva6_tests)

# Verilator
.PHONY: verilate
verilate: $(buildpath) bender $(veril_library)/V$(veril_top)

$(veril_library)/V$(veril_top): $(config_file) Makefile ../Bender.yml $(shell find src -type f) $(shell find ../config -type f) $(shell find include -type f) $(shell find tb -type f) $(shell find deps -type f)
	rm -rf $(veril_library); mkdir -p $(veril_library)
	$(BENDER) script verilator $(bender_targs_veril) $(bender_defs_veril) > $(veril_library)/bender_script_$(config)
# # Ensure Verilator symlinks exist for hierarchical mode
# 	@if [ -d "$(INSTALL_DIR)/verilator" ]; then \
# 		mkdir -p $(INSTALL_DIR)/verilator/share/verilator; \
# 		[ -L $(INSTALL_DIR)/verilator/share/verilator/verilator_bin ] || \
# 			ln -sf ../../bin/verilator_bin $(INSTALL_DIR)/verilator/share/verilator/verilator_bin; \
# 		[ -L $(INSTALL_DIR)/verilator/share/verilator/verilator_bin_dbg ] || \
# 			ln -sf ../../bin/verilator_bin_dbg $(INSTALL_DIR)/verilator/share/verilator/verilator_bin_dbg; \
# 		[ -L $(INSTALL_DIR)/verilator/include ] || \
# 			ln -sf share/verilator/include $(INSTALL_DIR)/verilator/include; \
# 	fi
# Verilate the design
	VERILATOR_ROOT=$(INSTALL_DIR)/verilator $(veril_path)/verilator -f $(veril_library)/bender_script_$(config)           \
  --timescale 1ns/1ps                                                           \
  -GNrLanes=$(nr_lanes)                                                         \
  -GVLEN=$(vlen)                                                                \
  -O3                                                                           \
  $(if $(trace),,-Wno-UNOPTTHREADS --hierarchical)                             \
  -Wno-fatal                                                                    \
  -Wno-PINCONNECTEMPTY                                                          \
  -Wno-BLKANDNBLK                                                               \
  -Wno-CASEINCOMPLETE                                                           \
  -Wno-CMPCONST                                                                 \
  -Wno-LATCH                                                                    \
  -Wno-LITENDIAN                                                                \
  -Wno-UNOPTFLAT                                                                \
  -Wno-UNPACKED                                                                 \
  -Wno-UNSIGNED                                                                 \
  -Wno-WIDTH                                                                    \
  -Wno-WIDTHCONCAT                                                              \
  -Wno-ENUMVALUE                                                                \
  -Wno-COMBDLY                                                                  \
  tb/verilator/waiver.vlt                                                       \
  --Mdir $(veril_library)                                                       \
  -Itb/dpi                                                                      \
  --compiler clang                                                              \
  -CFLAGS "-DTOPLEVEL_NAME=$(veril_top)"                                        \
  -CFLAGS "-DNR_LANES=$(nr_lanes)"                                              \
  -CFLAGS -I$(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_memutil_dpi/cpp       \
  -CFLAGS -I$(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_memutil_verilator/cpp \
  -CFLAGS -I$(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_simutil_verilator/cpp \
  $(CLANG_CXXFLAGS)                                                             \
  -LDFLAGS "$(ELF_LIBS) $(ATOMIC_LIBS) $(EXTRA_LDFLAGS)"                        \
  $(CLANG_LDFLAGS)                                                              \
  --exe                                                                         \
  $(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_memutil_dpi/cpp/*.cc            \
  $(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_memutil_verilator/cpp/*.cc      \
  $(ROOT_DIR)/tb/verilator/lowrisc_dv_verilator_simutil_verilator/cpp/*.cc      \
  $(ROOT_DIR)/tb/verilator/ara_tb.cpp                                           \
  --cc                                                                          \
  $(if $(trace),--trace-fst -Wno-INSECURE,)                                     \
  --top-module $(veril_top) &&                                                  \
 cd $(veril_library) && VERILATOR_ROOT=$(INSTALL_DIR)/verilator OBJCACHE='' make -j4 -f V$(veril_top).mk

# Simulation
.PHONY: simv
simv:
	$(veril_library)/V$(veril_top) $(if $(trace),-t,) -l ram,$(app_path)/$(app),elf

.PHONY: riscv_tests_simv
riscv_tests_simv: $(tests)

$(tests): rv%: $(app_path)/rv%
	$(veril_library)/V$(veril_top) $(if $(trace),-t,) -l ram,$<,elf &> $(buildpath)/$@.trace

# Lint
.PHONY: lint spyglass/tmp/files

SNPS_SG ?= spyglass-2022.06
lint: spyglass/tmp/files spyglass/sdc/func.sdc spyglass/scripts/run_lint.tcl
	cd spyglass; $(SNPS_SG) sg_shell -tcl scripts/run_lint.tcl

spyglass/tmp/files: $(bender)
	mkdir -p spyglass/tmp
	$(BENDER) script verilator $(bender_targs_spyglass) $(bender_defs) --define SPYGLASS > spyglass/tmp/files

# DPIs
.PHONY: dpi
dpi: $(buildpath)/$(dpi_library)/ara_dpi.so

$(buildpath)/$(dpi_library)/%.o: tb/dpi/%.cc
	mkdir -p $(buildpath)/$(dpi_library)
	$(CXX) -shared -fPIC -std=c++11 -Bsymbolic -c $< -I$(VERILATOR_INCLUDE) -I$(INSTALL_DIR)/riscv-isa-sim/include -o $@

$(buildpath)/$(dpi_library)/ara_dpi.so: $(dpi)
	mkdir -p $(buildpath)/$(dpi_library)
	$(CXX) -shared -m64 -o $(buildpath)/$(dpi_library)/ara_dpi.so $?

# Xcelium DPI
.PHONY: dpi_xcelium
dpi_xcelium: $(buildpath)/$(dpi_library)/ara_dpi_xcelium.so

$(buildpath)/$(dpi_library)/ara_dpi_xcelium.so: tb/dpi/*.cc
	mkdir -p $(buildpath)/$(dpi_library)
	@if [ -n "$$XCELIUM_HOME" ]; then \
		$(CXX) -shared -fPIC -std=c++11 -o $@ $^ \
			-I$$XCELIUM_HOME/tools/include \
			-I$(INSTALL_DIR)/riscv-isa-sim/include; \
	elif [ -n "$(xcelium_cmd)" ]; then \
		XCELIUM_ROOT=$$(dirname $$(dirname $$(which $(xcelium_cmd)))); \
		$(CXX) -shared -fPIC -std=c++11 -o $@ $^ \
			-I$$XCELIUM_ROOT/tools/include \
			-I$(INSTALL_DIR)/riscv-isa-sim/include; \
	else \
		echo "Warning: Xcelium not found, skipping DPI compilation"; \
	fi

# Clean targets
.PHONY: clean
clean:
	rm -rf $(buildpath)
	rm -f  $(BENDER)
