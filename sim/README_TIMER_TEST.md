# Timer Interrupt Integration Test

## Quick Start

To run the timer interrupt test:

```bash
cd sim
bash run_timer_integration.sh
```

## What This Test Does

This test validates that:
1. Timer peripheral generates interrupts at correct 100μs intervals
2. Firmware IRQ handler executes and acknowledges interrupts
3. Interrupt counter increments properly (0 → 10)
4. System remains stable across multiple interrupts
5. Firmware completes without crashing

## Test Components

- **Testbench:** `tb_timer_integration.sv` - SystemVerilog testbench
- **Test Runner:** `run_timer_integration.sh` - Compilation and simulation script
- **Firmware:** `../firmware/irq_timer_test.c` - C code that waits for 10 timer IRQs
- **Compiled Firmware:** `../firmware/irq_timer_test_words.hex` - 32-bit word format for testbench

## Expected Output

The test should show:
```
TIMER IRQ #1  at 115.405 ms - Period: N/A (first IRQ)
TIMER IRQ #2  at 215.405 ms - Period: 100.00 μs ✓
TIMER IRQ #3  at 315.405 ms - Period: 100.00 μs ✓
TIMER IRQ #4  at 415.405 ms - Period: 100.00 μs ✓
TIMER IRQ #5  at 515.405 ms - Period: 100.00 μs ✓
TIMER IRQ #6  at 615.405 ms - Period: 100.00 μs ✓
TIMER IRQ #7  at 715.405 ms - Period: 100.00 μs ✓
TIMER IRQ #8  at 815.405 ms - Period: 100.00 μs ✓
TIMER IRQ #9  at 915.405 ms - Period: 100.00 μs ✓
TIMER IRQ #10 at 1015.405 ms - Period: 100.00 μs ✓

[TEST SUCCESS] Firmware completed, counter reached 10
```

## Test Duration

- **Simulated time:** ~1.02 seconds
- **Wall clock time:** ~30-60 seconds (depends on SRAM debug output)

## Timer Configuration

The test configures the timer with:
- **Clock:** 50 MHz system clock
- **Prescaler (PSC):** 9 → divides by 10 → 5 MHz tick rate
- **Auto-reload (ARR):** 499 → 500 ticks per interrupt
- **IRQ Period:** 50 MHz / 10 / 500 = 10 kHz = **100 μs**

## Troubleshooting

### Test Times Out
- Check if ModelSim/QuestaSim is installed and in PATH
- Verify RISC-V toolchain compiled firmware correctly
- Check that `irq_timer_test_words.hex` exists in firmware directory

### Wrong Number of Interrupts
- If < 10 interrupts: Check that IRQ wrapper saves ALL registers (see `firmware/start.S`)
- If IRQ periods are incorrect: Verify timer configuration (PSC=9, ARR=499)

### Compilation Errors
- Ensure SystemVerilog modules are found: `../hdl/*.v`
- Check that work library is created: `vlib work`

## Related Documentation

See `../docs/INTERRUPT_BUG_FIX.md` for:
- Detailed analysis of the register corruption bug
- Explanation of the fix in `firmware/start.S`
- Before/after test results
- RISC-V interrupt handling best practices

## Requirements

- ModelSim/QuestaSim (vlog, vsim)
- RISC-V toolchain (riscv64-unknown-elf-gcc)
- SystemVerilog support (for testbench)
