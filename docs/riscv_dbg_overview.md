# RISC-V Debug Module Overview (corev_apu / riscv-dbg 0.13)

This document summarizes the key Debug Module CSRs and System Bus Access (SBA) registers used by the `corev_apu` / `riscv-dbg` integration, and provides a **step-by-step bring-up checklist** for verifying the debug unit on Ara/CVA6.

The content here is aligned with the RISC-V Debug Specification v0.13 and the implementation in [`dm_pkg.sv`](hardware/deps/cva6/corev_apu/riscv-dbg/src/dm_pkg.sv) and [`dm_csrs.sv`](hardware/deps/cva6/corev_apu/riscv-dbg/src/dm_csrs.sv).

---

## 1. DMI Register Map (key addresses)

| Name        | Address (hex) | Width | Description                                     |
| ----------- | ------------- | ----- | ----------------------------------------------- |
| `dmcontrol` | 0x10          | 32    | Main control register for DM and harts         |
| `dmstatus`  | 0x11          | 32    | Status of DM and all/any harts                 |
| `hartinfo`  | 0x12          | 32    | Hart capabilities / debug scratch info         |
| `abstractcs`| 0x16          | 32    | Abstract command status/control                |
| `command`   | 0x17          | 32    | Abstract command register                      |
| `abstractauto` | 0x18       | 32    | Auto-execution triggers for abstract commands  |
| `progbuf0`..`progbufN` | 0x20.. | 32 | Program buffer words                           |
| `data0`..`dataN` | 0x04..   | 32    | Abstract command data words                    |
| `sbcs`      | 0x38          | 32    | System Bus Access Control/Status               |
| `sbaddress0`| 0x39          | 32    | SBA address bits [31:0]                        |
| `sbaddress1`| 0x3a          | 32    | SBA address bits [63:32]                       |
| `sbdata0`   | 0x3c          | 32    | SBA data word 0                                |
| `sbdata1`.. | impl.-dep.    | 32    | Optional additional SBA data words             |

*Note:* Address values are the DMI addresses used by OpenOCD’s `riscv dmi_read` / `riscv dmi_write` commands.

---

## 2. `dmcontrol` (0x10)

### Bitfields

| Bits   | Name        | R/W  | Description                                                                 |
| ------ | ----------- | ---- | --------------------------------------------------------------------------- |
| 31     | `haltreq`   | W    | Write 1 to request all selected harts to halt                               |
| 30     | `resumereq` | W    | Write 1 to request all selected harts to resume                             |
| 29     | `hartreset` | R/W  | Optional hart-local reset (not typically used in CVA6 integration)         |
| 28     | `ackhavereset` | W  | Write 1 to clear `dmstatus.{anyhavereset, allhavereset}`                   |
| 27     | `hasel`     | R/W  | Hart selection mode (0 = implicit hart 0, 1 = use `hartsello/selhi`)      |
| 26:16  | `hartsello` | R/W  | Low bits of hart index selection                                            |
| 25:16  | (overlap)   |      | Full hart selection is implementation-defined width                         |
| 15:6   | `hartselhi` | R/W  | High bits of hart index selection                                           |
| 5      | `setresethaltreq` | W | Set resethaltreq (halt at reset)                                          |
| 4      | `clrresethaltreq` | W | Clear resethaltreq                                                         |
| 3      | `ndmreset`  | R/W  | Non-DM reset: resets the SoC / hart(s), but keeps DM and DMI alive         |
| 2      | *reserved*  |      |                                                                             |
| 1      | *reserved*  |      |                                                                             |
| 0      | `dmactive`  | R/W  | When 1, the Debug Module is active; must be set before using other fields  |

### Usage notes

- To **enable the DM**, set `dmactive=1`:
  - `dmcontrol = 0x00000001`.
- To **issue a pure halt request** without reset:
  - `dmcontrol = 0x80000001` (dmactive=1, haltreq=1).
- To **apply a non-DM reset** while holding the core in reset:
  - Assert `ndmreset=1` while `dmactive=1`: `dmcontrol = 0x00000003`.
- Always keep `dmactive=1` as long as you want debugging enabled.

In practice you rarely need to hand-type these values; the OpenOCD helper script [`utils/debug_utils.tcl`](utils/debug_utils.tcl) provides small wrappers:
- [`dm_enable()`](utils/debug_utils.tcl:155) &rarr; `dmcontrol.dmactive = 1`
- [`dm_pulse_ndmreset()`](utils/debug_utils.tcl:161) &rarr; `dmactive=1, ndmreset` pulse (0x3 &rarr; 0x1)
- [`dm_haltreq()`](utils/debug_utils.tcl:168) &rarr; `dmactive=1, haltreq=1`
- [`dm_status()`](utils/debug_utils.tcl:173) &rarr; read and print `dmstatus`

---

## 3. `dmstatus` (0x11)

### Bitfields

> The exact bit positions are defined in the 0.13 spec and the corev_apu implementation, but in practice you mostly care about the **per-field meaning** below.

| Bits | Name              | R/W | Description                                                                                 |
| ---- | ----------------- | --- | ------------------------------------------------------------------------------------------- |
| 31   | `impebreak`       | R   | Implementation may support implicit `ebreak` at end of program buffer                      |
| 30   | `allhavereset`    | R   | 1 if **all selected harts** have seen a reset since last `dmcontrol.ackhavereset`          |
| 29   | `anyhavereset`    | R   | 1 if **any selected hart** has seen a reset since last `dmcontrol.ackhavereset`           |
| 28   | `allresumeack`    | R   | 1 if all selected harts have acknowledged a previous `resumereq`                          |
| 27   | `anyresumeack`    | R   | 1 if any selected hart has acknowledged a previous `resumereq`                            |
| 26   | `allnonexistent`  | R   | 1 if *all* selected harts are non-existent (typically 0 in a single-hart system)          |
| 25   | `anynonexistent`  | R   | 1 if *any* selected hart is non-existent                                                   |
| 24   | `allunavail`      | R   | 1 if all selected harts are currently unavailable                                          |
| 23   | `anyunavail`      | R   | 1 if any selected hart is currently unavailable                                            |
| 22   | `allrunning`      | R   | 1 if all selected harts are currently running                                              |
| 21   | `anyrunning`      | R   | 1 if any selected hart is currently running                                                |
| 20   | `allhalted`       | R   | 1 if all selected harts are currently halted                                               |
| 19   | `anyhalted`       | R   | 1 if any selected hart is currently halted                                                 |
| 18   | `authenticated`   | R   | 1 if debug authentication (if implemented) has succeeded                                   |
| 17   | `authbusy`        | R   | 1 while authentication is in progress                                                      |
| 16   | `hasresethaltreq` | R   | 1 if the DM implements `resethaltreq` functionality                                       |
| 15   | `confstrptrvalid` | R   | 1 if a configuration string pointer (CSR) is provided                                      |
| 14:4 | *impl.-dependent* | R   | Reserved / implementation-defined fields (e.g. `nscratch` in some implementations)        |
| 3:0  | `version`         | R   | DM spec version; for 0.13 this must be `2`                                                 |

For Ara/CVA6 with a **single hart**, the “allX” and “anyX” bits are effectively the same value:

- `allhalted == anyhalted`
- `allrunning == anyrunning`
- etc.

The design still drives both, to remain compatible with multi-hart systems.

### Usage notes

- After issuing a halt request (via `haltreq` in `dmcontrol`), you should see:
  - `allhalted = 1`, `anyhalted = 1`
  - `allrunning = 0`, `anyrunning = 0`
- After issuing `resumereq` and the hart resumes:
  - `allrunning = 1`, `anyrunning = 1`
  - `allhalted = 0`, `anyhalted = 0`
  - `anyresumeack` (and in a single-hart system, `allresumeack`) should eventually go 1.
- If `allunavail` or `anynonexistent` are unexpected, your hart selection or `unavailable_i` wiring is wrong.
- The helper `dm_status` procedure in `utils/debug_utils.tcl` is a convenient shorthand for:
  - `riscv dmi_read 0x11` plus a formatted print of the raw value. Use it while debugging halt/resume flows.

---

## 4. `abstractcs` (0x16)

### Bitfields

| Bits   | Name       | R/W | Description                                                                 |
| ------ | ---------- | --- | --------------------------------------------------------------------------- |
| 31:29  | *reserved* | R   |                                                                             |
| 28:24  | `cmderr`   | R/W | Abstract command error code (W1C)                                           |
| 23:16  | `progbufsize` | R | Size of program buffer in 32-bit words                                     |
| 15:12  | *reserved* | R   |                                                                             |
| 11:0   | `datacount`| R   | Number of `data` registers implemented                                      |

### `cmderr` values (typical)

| Value | Meaning                      |
| ----- | ---------------------------- |
| 0     | No error                     |
| 1     | Busy (command while busy)    |
| 2     | Not supported                |
| 3     | Error in program buffer exec |
| 4     | Reserved                     |
| 5     | Reserved                     |
| 6     | Reserved                     |
| 7     | Other error                  |

### Usage notes

- Always clear `cmderr` by writing the same bit pattern back (W1C semantics). For example:
  - `riscv dmi_write 0x16 0x02000000` (to clear cmderr = 1).
- If abstract commands (e.g. register access) fail:
  - Read `abstractcs` to see `cmderr`.
  - Clear it, correct the cause, and retry.

At the moment there is no dedicated helper for `abstractcs`/`cmderr` in [`utils/debug_utils.tcl`](utils/debug_utils.tcl), but you can trivially wrap the sequences above in your own Tcl procs if you find yourself using them often.

---

## 5. `command` (0x17)

The `command` CSR encodes which abstract command to execute. For register access (the most common case):

### Bitfields (`cmdtype = 0` → Access Register)

| Bits   | Name         | Description                                        |
| ------ | ------------ | -------------------------------------------------- |
| 31:24  | `cmdtype`    | 0 = Access Register                                |
| 23:20  | `aarsize`    | Register access size: 2=32-bit, 3=64-bit, etc.    |
| 19     | `postexec`   | Run `progbuf` after access                         |
| 18     | `transfer`   | 1 = move between register and `data0..`           |
| 17     | `write`      | 1 = write to hart, 0 = read from hart             |
| 16     | `regno[16]`  | High bit of regno (bank selection)                |
| 15:0   | `regno[15:0]`| Lower bits of register number                      |

Common sequences:

- Read GPR x1 into `data0` (RV64):

```tcl
# Set aarsize=3 (64-bit), transfer=1, write=0, regno=x1 (0x1001)
riscv dmi_write 0x17 0x00221001
# Poll abstractcs.busy, then read data0
riscv dmi_read 0x04
```

- Write `data0` into GPR x1:

```tcl
riscv dmi_write 0x04 0xDEADBEEF   ;# data0
riscv dmi_write 0x17 0x00621001   ;# aarsize=3, transfer=1, write=1, regno=x1
```

These are currently shown as explicit `riscv dmi_*` commands; if you end up using specific access patterns frequently (e.g. reading a fixed GPR), consider creating small wrapper procs in [`utils/debug_utils.tcl`](utils/debug_utils.tcl) similar to [`dm_enable()`](utils/debug_utils.tcl:155) / [`dm_haltreq()`](utils/debug_utils.tcl:168).

---

## 6. `sbcs` (0x38) – System Bus Control/Status

### Bitfields

| Bits   | Name          | R/W  | Description                                                                               |
| ------ | ------------- | ---- | ----------------------------------------------------------------------------------------- |
| 31     | `sbbusyerror` | R/W1C| Set if a new SBA request was attempted while `sbbusy=1`                                  |
| 30:29  | *reserved*    |      |                                                                                           |
| 28:23  | `sbaccess8`/`sbaccess16`/`sbaccess32`/`sbaccess64`/`sbaccess128` | R | Supported access sizes                       |
| 22     | `sberror`     | R/W1C| Indicates an SBA error (non-zero)                                                        |
| 21     | *reserved*    |      |                                                                                           |
| 20     | `sbreadonaddr`| R/W  | When 1, SBA read is triggered when `sbaddress` is written                                |
| 19     | `sbautoincrement` | R/W | When 1, `sbaddress` auto-increments after each access                                 |
| 18     | `sbreadondata`| R/W  | When 1, SBA read is triggered when `sbdata` is read                                      |
| 17:15  | `sbaccess`    | R/W  | Encodes access size: 0=8b, 1=16b, 2=32b, 3=64b, etc.                                     |
| 14     | *reserved*    |      |                                                                                           |
| 13:12  | `sbbusy`      | R    | 1 when an SBA access is in progress                                                      |
| 11:0   | *implementation-dependent* |   |                                                                                       |

*Note:* Exact bit positions for `sbreadonaddr`, `sbaccess`, etc. are implementation-specific but follow the 0.13 spec; here they match what your working SBA sequences configured.

### Typical working configuration (32-bit accesses with read-back)

From your manual working flow and `load_sba.tcl`:

```tcl
# Configure SBCS:
# - sbreadonaddr   = 1
# - sbaccess       = 2  (32-bit)
# - clear sbbusyerror and sberror via W1C
set sbcs_cfg [expr { (1 << 20) | (2 << 17) | (1 << 22) | (0x7 << 12) }]
riscv dmi_write 0x38 $sbcs_cfg
riscv dmi_read  0x38
```

### Clearing SBA errors only (without changing mode fields)

Sometimes you want to clear `sbbusyerror` / `sberror` **without** reprogramming `sbreadonaddr`, `sbaccess`, etc. The implementation supports a pure W1C “clear errors” pattern:

```tcl
# Clear sbbusyerror/sberror and implementation-defined error bits, keep mode fields as-is
set clear_errors_cfg [expr { (1 << 21) | (1 << 23) | (0x7 << 12) }]
riscv dmi_write 0x38 $clear_errors_cfg
riscv dmi_read  0x38
```

For convenience, the OpenOCD helper script [`utils/debug_utils.tcl`](utils/debug_utils.tcl:1) provides:

```tcl
sba_config_32      ;# Configure SBCS for 32-bit + sbreadonaddr and clear errors
sba_clear_errors   ;# Only clear sbbusyerror/sberror (using clear_errors_cfg)
sba_status         ;# Read back SBCS (0x38)
```

---

## 7. SBA address and data registers

| Name         | Address | Description                           |
| ------------ | ------- | ------------------------------------- |
| `sbaddress0` | 0x39    | Lower 32 bits of system bus address  |
| `sbaddress1` | 0x3a    | Upper 32 bits of system bus address  |
| `sbdata0`    | 0x3c    | SBA data word 0                      |

Pattern for a 64-bit address and 32-bit access:

- Write address:

```tcl
riscv dmi_write 0x39 [expr {$addr & 0xffffffff}]
riscv dmi_write 0x3a [expr {($addr >> 32) & 0xffffffff}]
```

- For a write:

```tcl
riscv dmi_write 0x3c $word
```

- For a read (with `sbreadonaddr=1`):

```tcl
riscv dmi_write 0x39 [expr {$addr & 0xffffffff}]
riscv dmi_write 0x3a [expr {($addr >> 32) & 0xffffffff}]
set actual [riscv dmi_read 0x3c]
```

The helper procs in [`utils/debug_utils.tcl`](utils/debug_utils.tcl) wrap this boilerplate:
- [`sba_read32()`](utils/debug_utils.tcl:55) uses `sbaddress0/1` and `sbdata0` to perform a 32-bit read
- [`sba_write32()`](utils/debug_utils.tcl:66) performs a 32-bit write
- [`read_mem()`](utils/debug_utils.tcl:80) and [`write_mem()`](utils/debug_utils.tcl:93) build on these to access multiple consecutive words

---

## 8. Structured bring-up and verification steps

This section collects a **checklist** to verify the debug unit and SBA integration on Ara/CVA6 with OpenOCD.

### 8.1. DM and DMI sanity check

1. **Connect OpenOCD and telnet:**

   ```bash
   openocd -f hardware/fpga/boards/axku5/axku5.cfg
   telnet localhost 4444
   ```

2. **Load helper procs (recommended):**

   ```tcl
   source utils/debug_utils.tcl
   ```

3. **Read basic CSRs:**

   Either manually:

   ```tcl
   riscv dmi_read 0x10   ;# dmcontrol
   riscv dmi_read 0x11   ;# dmstatus
   ```

   or with helpers:

   ```tcl
   dm_enable      ;# sets dmactive=1
   dm_status      ;# prints dmstatus
   ```

   - Expect `dmcontrol.dmactive` = 1 after enabling.
   - Expect `dmstatus.version` = 2, `dmstatus.authenticated` = 1.

4. **Enable DM and apply ndmreset:**

   Manually:

   ```tcl
   riscv dmi_write 0x10 0x00000003  ;# dmactive=1, ndmreset=1
   riscv dmi_write 0x10 0x00000001  ;# dmactive=1, ndmreset=0
   ```

   or with the helper:

   ```tcl
   dm_pulse_ndmreset
   ```

5. **Request a halt:**

   Manually:

   ```tcl
   riscv dmi_write 0x10 0x80000001  ;# dmactive=1, haltreq=1
   riscv dmi_read  0x11             ;# dmstatus
   ```

   or via helper:

   ```tcl
   dm_haltreq
   dm_status
   ```

   - Verify `dmstatus.allhalted = 1` and `allrunning = 0`.

### 8.2. SBA verification

1. **Configure SBCS for 32-bit accesses:**

   Use your known-good pattern:

   ```tcl
   set sbcs_cfg [expr { (1 << 20) | (2 << 17) | (1 << 22) | (0x7 << 12) }]
   riscv dmi_write 0x38 $sbcs_cfg
   riscv dmi_read  0x38
   ```

   or simply:

   ```tcl
   sba_config_32
   ```

2. **Test L2 SRAM writes/reads via SBA:**

   Manual DMI sequence:

   ```tcl
   # Write 0x11223344 to 0x80000000 and read back
   riscv dmi_write 0x39 0x80000000
   riscv dmi_write 0x3a 0x00000000
   riscv dmi_write 0x3c 0x11223344
   riscv dmi_write 0x39 0x80000000
   riscv dmi_write 0x3a 0x00000000
   riscv dmi_read  0x3c
   ```

   or via helpers:

   ```tcl
   sba_write32 0x80000000 0x11223344
   sba_read32  0x80000000
   ```

   - Expect `0x11223344`.

3. **Test a UART register via SBA:**

   Manual:

   ```tcl
   # Example: read UART status at 0xC0000008
   set addr 0xC0000008
   riscv dmi_write 0x39 [expr {$addr & 0xffffffff}]
   riscv dmi_write 0x3a [expr {($addr >> 32) & 0xffffffff}]
   set status [riscv dmi_read 0x3c]
   echo [format "UART_STATUS = 0x%08x" $status]
   ```

   or using helpers that encode the same base/offsets as the RTL:

   ```tcl
   uart_status_once
   # or, to poll a few times:
   uart_status_loop 10
   ```

   This verifies SBA can access peripherals via the AXI fabric.

4. **Run bulk load with `utils/load_sba.tcl`:**

   ```tcl
   source utils/load_sba.tcl
   load_sba apps/bin/hello_world_uart.bin 0x80000000
   ```

   - Expect “All words verified correctly.”
   - At the end, read `sbcs` again and ensure `sbbusyerror` / `sberror` are 0 (e.g. `sba_status` plus `sba_clear_errors` if needed).

### 8.3. Debug ROM and debug entry checks

1. **Dump DEBUG window via SBA:**

   Manual loop:

   ```tcl
   for {set a 0x1A110000} {$a < 0x1A110040} {incr a 4} {
       riscv dmi_write 0x39 [expr {$a & 0xffffffff}]
       riscv dmi_write 0x3a [expr {($a >> 32) & 0xffffffff}]
       set w [riscv dmi_read 0x3c]
       echo [format "DEBUG[0x%08x] = 0x%08x" $a $w]
   }
   ```

   or with the generic memory helper (after `sba_config_32`):

   ```tcl
   read_mem 0x1A110000 16   ;# 16 words = 64 bytes
   ```

   - Check that the contents match the expected debug ROM.

2. **Check the “halt landing pad”:**

   - CVA6 is configured to jump to `DebugBase + HaltAddress`:

     ```text
     DebugBase   = 0x1A11_0000
     HaltAddress = 0x0000_0800
     Target PC   = 0x1A11_0800
     ```

   - Dump around 0x1A11_0800 via SBA and verify you see valid instructions.

3. **Observe PC when halted (via GDB):**

   ```gdb
   target extended-remote localhost:3333
   monitor reset halt
   info registers pc
   ```

   - If PC is not in the DEBUG region when `dmstatus.allhalted=1`, debug entry is not behaving as expected.

### 8.4. Abstract command debug

1. **Read `abstractcs` and clear `cmderr`:**

   ```tcl
   riscv dmi_read 0x16           ;# abstractcs
   # If cmderr != 0: clear it by writing the bit(s)
   riscv dmi_write 0x16 0x1F000000  ;# example to clear any cmderr[4:0]
   ```

   (There is no dedicated helper yet; you can add one in [`utils/debug_utils.tcl`](utils/debug_utils.tcl) if you find yourself doing this often.)

2. **Try a simple register read via abstract command:**

   ```tcl
   # Read x1 into data0 (64-bit example, adjust as needed)
   riscv dmi_write 0x17 0x00221001  ;# Access Reg, aarsize=3, transfer=1, write=0, regno=x1
   # Poll abstractcs.busy; then:
   riscv dmi_read 0x04              ;# data0
   ```

3. **If it fails:**

   - Read `abstractcs` again and check `cmderr`.
   - Use SBA + DMSTATUS + PC to determine if the hart is in the correct debug state when you issue the command.

---

This file should give you both:

- A quick **bit-level reference** for the relevant debug CSRs (DMCONTROL, DMSTATUS, ABSTRACTCS, COMMAND, SBCS, SBA regs).
- A practical **step-by-step sequence** to bring up and debug the riscv-dbg + OpenOCD environment on the FPGA, leveraging the now fully integrated SBA path.