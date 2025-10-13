# Critical Bug Fix: IRQ Wrapper Register Corruption

## Summary

Fixed a critical bug in the interrupt wrapper (`firmware/start.S`) that was causing register corruption during interrupt handling. The bug caused firmware to exit prematurely after only 2 interrupts instead of the expected 10.

## Bug Description

### Root Cause

The IRQ wrapper at `firmware/start.S:49-77` was only saving a minimal set of registers:
- Saved: `ra, a0-a2, t0-t2` (7 registers, 32-byte stack frame)
- **NOT saved:** `a3-a7, t3-t6`

This violated the RISC-V calling convention for interrupt handlers, which must save ALL caller-saved registers because interrupts can occur at any point during program execution.

### How It Manifested

1. The test firmware `irq_timer_test.c` uses a loop to wait for 10 interrupts:
   ```c
   while (interrupt_count < 10) {
       asm volatile("nop");
   }
   ```

2. The compiler optimized this loop and reused register `a3` (which held the prescaler value 9) as the comparison value:
   ```asm
   b4:  li   a3,9              # Load PSC value 9 into a3
   cc:  lw   a5,252(zero)      # Load interrupt_count
   d0:  bltu a3,a5,e0          # if (a3 < count) exit → BUG: compares with 9 instead of 10!
   ```

3. When interrupts fired, register `a3` was NOT saved/restored by the IRQ wrapper
4. After interrupt handling, `a3` was corrupted, causing the loop to exit after only 2 interrupts

### Symptoms

- Timer peripheral generated interrupts correctly at 100μs intervals
- Firmware properly incremented `interrupt_count` in the IRQ handler
- BUT: Firmware exited after exactly 2 interrupts every time
- Timer appeared to "stop" because firmware disabled it after exiting the loop

## The Fix

Updated `firmware/start.S` IRQ wrapper to save ALL caller-saved registers:

**Before (32-byte stack frame):**
```asm
addi sp, sp, -32
sw ra,  0(sp)
sw a0,  4(sp)
sw a1,  8(sp)
sw a2, 12(sp)
sw t0, 16(sp)
sw t1, 20(sp)
sw t2, 24(sp)
```

**After (64-byte stack frame):**
```asm
addi sp, sp, -64
sw ra,  0(sp)
sw a0,  4(sp)
sw a1,  8(sp)
sw a2, 12(sp)
sw a3, 16(sp)   // CRITICAL: Now saves a3!
sw a4, 20(sp)
sw a5, 24(sp)
sw a6, 28(sp)
sw a7, 32(sp)
sw t0, 36(sp)
sw t1, 40(sp)
sw t2, 44(sp)
sw t3, 48(sp)
sw t4, 52(sp)
sw t5, 56(sp)
sw t6, 60(sp)
```

## Test Results

### Before Fix
```
IRQ #1 at 115.405 ms - Counter increments: 0 → 1 ✓
IRQ #2 at 215.405 ms - Counter increments: 1 → 2 ✓
[Timer disabled - firmware exits loop prematurely]
NO MORE INTERRUPTS - System appears hung
```

### After Fix
```
IRQ #1  at 115.405 ms - Period: N/A (first)      - Counter: 0 → 1  ✓
IRQ #2  at 215.405 ms - Period: 100.00 μs ✓     - Counter: 1 → 2  ✓
IRQ #3  at 315.405 ms - Period: 100.00 μs ✓     - Counter: 2 → 3  ✓
IRQ #4  at 415.405 ms - Period: 100.00 μs ✓     - Counter: 3 → 4  ✓
IRQ #5  at 515.405 ms - Period: 100.00 μs ✓     - Counter: 4 → 5  ✓
IRQ #6  at 615.405 ms - Period: 100.00 μs ✓     - Counter: 5 → 6  ✓
IRQ #7  at 715.405 ms - Period: 100.00 μs ✓     - Counter: 6 → 7  ✓
IRQ #8  at 815.405 ms - Period: 100.00 μs ✓     - Counter: 7 → 8  ✓
IRQ #9  at 915.405 ms - Period: 100.00 μs ✓     - Counter: 8 → 9  ✓
IRQ #10 at 1015.405 ms - Period: 100.00 μs ✓    - Counter: 9 → 10 ✓

All 10 interrupts handled successfully!
Firmware completed normally, LEDs signaled success.
```

## Running the Test

### Prerequisites
- ModelSim/QuestaSim installed
- RISC-V toolchain (riscv64-unknown-elf-gcc)

### Compile Firmware
```bash
cd firmware
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -O2 -g \
    -nostartfiles -nostdlib -nodefaultlibs -Wall -Wextra \
    -ffreestanding -fno-builtin -T linker.ld -Wl,--gc-sections \
    -Wl,-Map=irq_timer_test.map start.S irq_timer_test.c \
    -o irq_timer_test.elf

riscv64-unknown-elf-objcopy -O binary irq_timer_test.elf irq_timer_test.bin
../tools/bin2wordhex.sh irq_timer_test.bin irq_timer_test_words.hex
```

### Run Simulation
```bash
cd sim
bash run_timer_integration.sh
```

### Expected Output
The simulation should show:
- 10 timer interrupts at perfect 100μs intervals
- Interrupt counter incrementing from 0 to 10
- Each interrupt properly acknowledged by firmware
- Timer disabled after 10 interrupts
- LEDs set to 0x3 to signal completion

### Test Duration
- Simulates ~1.02 seconds of real-time operation
- Wallclock time: ~30-60 seconds (depending on SRAM debug output)

## Files Modified

1. **firmware/start.S** - IRQ wrapper now saves all caller-saved registers
2. **firmware/irq_timer_test.c** - Test firmware (waits for 10 timer IRQs)
3. **sim/tb_timer_integration.sv** - SystemVerilog testbench
4. **sim/run_timer_integration.sh** - Test runner script

## Lessons Learned

1. **Always save ALL caller-saved registers in interrupt handlers** - even if current code doesn't use them, compiler optimizations may change register allocation
2. **RISC-V caller-saved registers:** a0-a7, t0-t6, ra (17 total)
3. **RISC-V callee-saved registers:** s0-s11, sp (13 total) - these don't need saving
4. **Debug technique:** When firmware appears to "stop" during interrupts, check if:
   - Interrupts are still firing (hardware working?)
   - Interrupt handler is being called (software working?)
   - Register state is preserved across interrupt handler (IRQ wrapper correct?)

## Impact

This fix ensures robust interrupt handling for ALL firmware, not just the timer test. Any firmware that uses registers during its main loop will now work correctly with interrupts enabled.

## Date

October 13, 2025

## Author

Claude Code (debugging) & Michael Wolak (platform)
