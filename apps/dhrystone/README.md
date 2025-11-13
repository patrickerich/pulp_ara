# Dhrystone build variants

Clean before each build and use one of the profiles below.

1) Vanilla (baseline)
make -C apps clean && make -C apps bin/dhrystone

2) LTO + loop unroll + inlining
make -C apps clean && make -C apps bin/dhrystone LLVM_FLAGS='-march=rv64gcv_zfh_zvfh -mabi=lp64d -mno-relax -fuse-ld=lld -flto -funroll-loops -finline-functions' RISCV_LDFLAGS='-static -nostartfiles -lm -Wl,--gc-sections -Tcommon/link.ld -flto'

3) LTO only (no loop unroll/inlining)
make -C apps clean && make -C apps bin/dhrystone LLVM_FLAGS='-march=rv64gcv_zfh_zvfh -mabi=lp64d -mno-relax -fuse-ld=lld -flto' RISCV_LDFLAGS='-static -nostartfiles -lm -Wl,--gc-sections -Tcommon/link.ld -flto'

4) Reportable (compliant: O2, no LTO, no fast-math, no inlining/unrolling)
make -C apps clean && make -C apps bin/dhrystone RISCV_FLAGS='$(LLVM_FLAGS) $(LLVM_V_FLAGS) -mcmodel=medany -I$(CURDIR)/common -O2 -fno-inline -fno-inline-functions -fno-inline-functions-called-once -fno-unroll-loops -fno-builtin -fno-builtin-printf $(DEFINES) $(RISCV_WARNINGS)' RISCV_LDFLAGS='-static -nostartfiles -lm -Wl,--gc-sections -Tcommon/link.ld'

5) Reportable (GCC: O2, no LTO, no fast-math, no inlining/unrolling)
# Important: hard-clean .o files to avoid mixing LLVM/GCC object attributes
COMPILER=gcc RISCV_ARCH=rv64gc make -C apps clean && find ./apps -type f -name '*.o' -delete && COMPILER=gcc RISCV_ARCH=rv64gc make -C apps bin/dhrystone RISCV_FLAGS_GCC='-mcmodel=medany -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -I$(CURDIR)/common -static -O2 -fno-inline -fno-inline-functions -fno-inline-functions-called-once -fno-unroll-loops -fno-builtin -fno-builtin-printf $(DEFINES) $(RISCV_WARNINGS)' RISCV_LDFLAGS_GCC='-static -nostartfiles -lm -lgcc -T$(CURDIR)/common/link.ld'

Note:
- If you previously built with LLVM, stale .o files may carry newer ISA attributes (e.g., zicsr) that older GCC binutils cannot merge.
- The find … -delete step ensures a clean slate so GCC-only objects are linked.

Optional: run on Verilator RTL
make -C hardware verilate
app=dhrystone make -C hardware simv