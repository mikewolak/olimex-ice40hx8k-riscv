# PicoRV32 Interrupt System Guide

## Overview

This firmware directory includes full interrupt support for the PicoRV32 CPU with the custom timer peripheral.

**Key Features:**
- Hardware timer interrupts @ 60 Hz
- PicoRV32 custom IRQ instructions
- Assembly IRQ handler in `start.S`
- Example timer clock demo in `timer_clock.c`

---

## Files

| File | Description |
|------|-------------|
| `start.S` | Startup code with IRQ vector at 0x10 |
| `picorv32_irq.h` | PicoRV32 custom interrupt instruction macros (heavily commented) |
| `timer_regs.h` | Timer peripheral register definitions |
| `timer_clock.c` | Demo: 60 Hz clock with HH:MM:SS:FF display |

---

## Interrupt Architecture

### Hardware Flow

1. **IRQ Occurs**: Timer (or other peripheral) asserts IRQ line
2. **CPU Entry** (automatic):
   - Saves PC+4 to q0 (return address)
   - Saves IRQ mask to q1 (interrupt state)
   - Disables all interrupts (mask = 0xFFFFFFFF)
   - Jumps to 0x10 (IRQ vector)
3. **Assembly Handler** (`start.S:irq_vec`):
   - Saves ra, a0-a2, t0-t2 to stack
   - Reads IRQ bitmask from q1
   - Calls C handler with IRQ bitmask as argument
4. **C Handler** (`irq_handler(uint32_t irqs)`):
   - Checks which IRQ bit is set
   - **CRITICAL:** Clears interrupt source at peripheral
   - Updates application state
   - Returns
5. **Assembly Handler** (continued):
   - Restores registers from stack
   - Executes `retirq` instruction
6. **CPU Exit** (automatic):
   - Restores PC from q0
   - Restores IRQ mask from q1 (re-enables interrupts)

---

## Custom Instructions

PicoRV32 uses **non-standard RISC-V instructions** for interrupt handling (opcode 0x0B):

| Instruction | Opcode | Funct7 | Funct3 | Description |
|-------------|--------|---------|---------|-------------|
| `getq rd, qs` | 0x0B | 0x00 | 0x4 | Get IRQ shadow register q0-q3 |
| `setq qd, rs` | 0x0B | 0x01 | 0x2 | Set IRQ shadow register q0-q3 |
| `retirq` | 0x0B | 0x02 | 0x0 | Return from interrupt |
| `maskirq rd, rs` | 0x0B | 0x03 | 0x6 | Mask interrupts (rd=old mask) |
| `waitirq` | 0x0B | 0x04 | 0x4 | Wait for interrupt (low power) |
| `timer rd, rs` | 0x0B | 0x05 | 0x6 | Read/write CPU cycle timer |

**See `picorv32_irq.h` for heavily commented inline assembly macros.**

---

## Shadow Registers (Q-Registers)

PicoRV32 provides 4 IRQ shadow registers when `ENABLE_IRQ_QREGS=1`:

| Register | Purpose | Set By |
|----------|---------|--------|
| **q0** | Return PC | Hardware (on IRQ entry) |
| **q1** | IRQ mask | Hardware (on IRQ entry) |
| **q2** | User register | Software (optional save) |
| **q3** | User register | Software (optional save) |

---

## Timer Peripheral

### Register Map (Base: 0x80000020)

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | CR | Control: [0]=Enable, [1]=One-shot |
| 0x04 | SR | Status: [0]=UIF (write 1 to clear) |
| 0x08 | PSC | Prescaler (16-bit) |
| 0x0C | ARR | Auto-reload value (32-bit) |
| 0x10 | CNT | Current counter (read-only) |

### Configuration

**Interrupt Rate Formula:**
```
IRQ Frequency = SYSCLK / (PSC + 1) / (ARR + 1)
```

**Example (60 Hz):**
```c
// 50 MHz / 50 / 16667 = 59.998 Hz ≈ 60 Hz
TIMER_PSC = 49;    // Divide by 50 → 1 MHz tick rate
TIMER_ARR = 16666; // 1 MHz / 16667 ≈ 60 Hz
```

---

## Writing an Interrupt Handler

### Step 1: Add IRQ Handler Function

Create `irq_handler()` in your C code:

```c
void irq_handler(uint32_t irqs) {
    // Check which IRQ fired
    if (irqs & (1 << 0)) {
        // Timer interrupt (IRQ[0])

        // CRITICAL: Clear interrupt source!
        TIMER_SR = TIMER_SR_UIF;

        // Your interrupt handling code here
        // ...
    }
}
```

**IMPORTANT:** You MUST clear the interrupt source, or the IRQ will fire continuously!

### Step 2: Enable Interrupts at Startup

```c
int main(void) {
    // Configure timer
    timer_init();
    timer_config(49, 16666);  // 60 Hz

    // Enable interrupts (clear IRQ mask)
    uint32_t dummy;
    __asm__ volatile (".insn r 0x0B, 6, 3, %0, %1, x0"
                      : "=r"(dummy) : "r"(0));

    // Start timer
    timer_start();

    // Main loop
    while (1) {
        // Your code here
    }
}
```

### Step 3: Build and Test

```bash
make TARGET=your_firmware single-target
```

---

## Timer Clock Demo

The `timer_clock.c` demo shows a complete working example:

- 60 Hz timer interrupt
- Clock display (HH:MM:SS:FF format)
- Real-time UART updates
- Minimal CPU overhead

**To build:**
```bash
make TARGET=timer_clock single-target
```

**To run:**
```bash
cd tools/uploader
./fw_upload -p COM8 ../../firmware/timer_clock.hex
```

Expected output (updates 60 times per second):
```
00:00:00:00
00:00:00:01
00:00:00:02
...
```

---

## Troubleshooting

### Interrupt Not Firing

1. **Check IRQ vector location:** Must be at 0x10
   ```bash
   riscv64-unknown-elf-objdump -d your_firmware.elf | grep irq_vec
   ```
   Should show: `00000010 <irq_vec>:`

2. **Verify IRQ is enabled:**
   - IRQ mask: 0 = enabled, 1 = disabled
   - Use `maskirq` to check current mask
   - Make sure bit 0 is clear (timer IRQ)

3. **Check timer configuration:**
   - Timer enabled (CR bit 0 = 1)
   - PSC and ARR set correctly
   - Interrupt not masked

### Interrupt Fires Continuously

- **Most common cause:** Forgot to clear interrupt source!
- Add `TIMER_SR = TIMER_SR_UIF;` in your handler
- Check that write completes (volatile pointer)

### System Hangs

- **Stack overflow:** IRQ handler uses 32 bytes of stack
- **Infinite loop in handler:** Keep handlers short
- **Nested interrupts:** PicoRV32 disables IRQs on entry (safe)

---

## Memory Map Reference

| Address Range | Device | Description |
|---------------|--------|-------------|
| 0x00000000 - 0x0007FFFF | SRAM | 512 KB application memory |
| 0x80000000 | UART TX DATA | Write byte to transmit |
| 0x80000004 | UART TX STATUS | Bit 0: TX busy |
| 0x80000008 | UART RX DATA | Read received byte |
| 0x8000000C | UART RX STATUS | Bit 0: RX empty |
| 0x80000010 | LED CONTROL | Bit 0: LED1, Bit 1: LED2 |
| 0x80000020 | TIMER CR | Timer control |
| 0x80000024 | TIMER SR | Timer status (interrupt flag) |
| 0x80000028 | TIMER PSC | Timer prescaler |
| 0x8000002C | TIMER ARR | Timer auto-reload |
| 0x80000030 | TIMER CNT | Timer counter (read-only) |

---

## Performance Notes

- **IRQ latency:** ~10-15 cycles (hardware save + jump)
- **Handler overhead:** ~50-100 cycles (register save/restore + C call)
- **Timer @ 60 Hz:** 0.12% CPU time (60 × 100 cycles / 50 MHz)
- **Minimum period:** ~1 µs (limited by handler execution time)

---

## Next Steps

1. **Add more peripherals:** UART RX, GPIO interrupts
2. **Implement RTOS:** Use timer for task scheduling
3. **DMA-style transfers:** Use interrupts for bulk I/O
4. **Power management:** Use `waitirq` to sleep between IRQs

---

**Questions? See:**
- `picorv32_irq.h` - Heavily commented instruction macros
- `timer_regs.h` - Timer peripheral definitions
- `start.S` - Assembly IRQ handler implementation
- `timer_clock.c` - Complete working example
