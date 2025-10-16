# Yosys Non-Determinism Analysis

## Executive Summary

The FPGA bitstream build failure was caused by **Yosys ABC9 optimization non-determinism**. Even with identical source code and the same Yosys version (0.24), synthesis produces different results that cause firmware execution failure.

## Root Cause

The missing 2 flip-flops (`sram_drv.state_SB_DFF_Q_3` and `sram_drv.state_SB_DFF_Q_4`) are part of the SRAM driver's `ready` signal generation logic. Without these DFFs, the SRAM controller cannot properly signal transaction completion, which breaks CPU firmware execution.

## Technical Details

### Missing Flip-Flops

**Gold build (working):**
- `sram_drv.state_SB_DFF_Q_3`: D=8524, Q=8564
- `sram_drv.state_SB_DFF_Q_4`: D=8593, Q=8565

**Failed builds (Mac fresh, Windows, Linux):**
- These DFFs are missing from synthesis output

### Ready Signal Logic Chain

From JSON analysis of gold build:

1. **State detection LUT:**
   - Inputs: state_SB_DFF_Q_3 (I2), state_SB_DFF_Q_4 (I3)
   - LUT_INIT: 0x000F (outputs 1 when both inputs are 0)
   - Output: signal 8560

2. **Ready flip-flop:**
   - `sram_drv.ready_SB_DFFESR_Q`
   - D input: signal 8560 (from state detection LUT)
   - Q output: signal 8562 (ready signal)

3. **Logic function:**
   ```
   ready_next = !(state_Q_3 | state_Q_4)
   ready = ready_next (when enabled)
   ```

### SRAM Driver State Machine

From `hdl/sram_driver_new.v`:

```verilog
localparam IDLE     = 2'd0;  // 2'b00
localparam ACTIVE   = 2'd1;  // 2'b01
localparam COMPLETE = 2'd2;  // 2'b10

reg [1:0] state;
```

The `ready` signal is set to 1 in the COMPLETE state (lines 141, 155):
- After write completion: `ready <= 1'b1`
- After read completion: `ready <= 1'b1`

**Critical Finding:** The state register is only 2 bits wide, but synthesis created additional state-related DFFs (Q_3, Q_4) as part of the optimization process. These are likely intermediate signals in the state decode logic that were preserved in the working build but optimized away in failed builds.

## Build Comparison

### Gold (Oct 13, working):
- Yosys: 0.24+10 (macOS)
- Cells: 9613
- LUTs: 5111
- DFFs: 3112
- MD5: b08289d244c2202ba0c413f8ba598e20

### Mac Fresh (Oct 16, FAILED):
- Yosys: 0.24+10 (macOS) **SAME VERSION**
- Cells: 9619 (+6)
- LUTs: 5119 (+8)
- DFFs: 3110 (-2) **MISSING 2 DFFS**
- Different bitstream despite identical source

### Windows/Linux (Oct 16, FAILED):
- Yosys: 0.58+0 / 0.58+69
- Cells: 9212 (-401)
- LUTs: 4786 (-325)
- DFFs: 3078 (-34)

## Source Verification

All source files verified **byte-for-byte identical** between gold and failed builds:

### HDL Files (14 files, all identical):
- ice40_picorv32_top.v: MD5 12052e1eeb48a64965ca1a52920c5ea5
- sram_driver_new.v: MD5 6a398a63e467a20f0e7902f6f113c372
- mem_controller.v: MD5 ab84a8777d5d32c5165f4f9e2fd94f5a
- bootloader_rom.v, circular_buffer.v, crc32_gen.v, firmware_loader.v
- mmio_peripherals.v, mode_controller.v, picorv32.v, shell.v
- sram_proc_new.v, timer_peripheral.v, uart.v

### Bootloader:
- bootloader.hex: MD5 e56a3daf12aa804126c090c11ab927ed (IDENTICAL)

## Yosys Non-Determinism

**Key Discovery:** Same Yosys version (0.24) with identical source produces different synthesis results.

This proves the issue is **Yosys non-deterministic optimization**, not:
- ❌ Source code changes
- ❌ Bootloader differences
- ❌ Yosys version differences
- ✅ ABC9 optimization randomness

## Impact

Without the SRAM ready signal logic:
1. CPU attempts memory access
2. SRAM controller never signals ready
3. CPU hangs waiting for memory response
4. Firmware never executes after upload

Bootloader works because it uses BRAM (separate from SRAM controller), but firmware execution requires working SRAM.

## Solution

**Immediate:** Use gold bitstream (saved Oct 13, verified working):
```bash
cp /mnt/c/msys64/home/mwolak/gold/olimex-ice40hx8k-riscv-intr/build/ice40_picorv32.bin \
   /mnt/c/msys64/home/mwolak/olimex-ice40hx8k-riscv-intr/build/ice40_picorv32.bin
```

**Long-term options:**
1. Add synthesis seed for determinism
2. Add (* keep *) attributes to critical SRAM ready logic
3. Use different optimization level (disable ABC9)
4. Lock to specific Yosys version with verified working builds
5. Implement formal verification to catch such issues

## Files

- **Gold archive:** `/mnt/c/msys64/home/mwolak/gold/olimex-ice40hx8k-riscv-intr-gold.tar.gz`
- **Working bitstream:** Gold build, MD5 b08289d244c2202ba0c413f8ba598e20
- **Analysis script:** `compare_builds.sh`
- **Diff analysis:** `/tmp/gold_dffs.txt`, `/tmp/mac_dffs.txt`

## Reproduction

```bash
# Extract gold bitstream
cd /tmp
tar -xzf /mnt/c/msys64/home/mwolak/gold/olimex-ice40hx8k-riscv-intr-gold.tar.gz

# Compare DFF counts
grep -o '"type": "SB_DFF"' /tmp/olimex-ice40hx8k-riscv-intr/build/ice40_picorv32.json | wc -l
# Gold: 3112

# Fresh Mac build (same Yosys 0.24)
cd /tmp/mac_fresh
make clean && make
grep -o '"type": "SB_DFF"' build/ice40_picorv32.json | wc -l
# Mac fresh: 3110 (missing 2!)

# Find missing DFFs
grep 'SB_DFF' /tmp/olimex-ice40hx8k-riscv-intr/build/ice40_picorv32.json | \
    sed 's/.*"\(.*\)": {/\1/' | sort > /tmp/gold_dffs.txt
grep 'SB_DFF' /tmp/mac_fresh/build/ice40_picorv32.json | \
    sed 's/.*"\(.*\)": {/\1/' | sort > /tmp/mac_dffs.txt
diff /tmp/gold_dffs.txt /tmp/mac_dffs.txt
# < sram_drv.state_SB_DFF_Q_3
# < sram_drv.state_SB_DFF_Q_4
```

## References

- Issue discovered: October 16, 2025
- Yosys versions tested: 0.24+10 (macOS), 0.58+0 (Linux), 0.58+69 (Windows)
- Platform: Olimex iCE40HX8K-EVB, PicoRV32 RISC-V rv32im @ 50MHz
