# Firmware Validation Report

## Compilation Success

**Toolchain:** `riscv64-unknown-elf-gcc`
**Architecture:** RV32E
**ABI:** ilp32e
**Optimization:** -O2

## Binary Output

```
Firmware: led_blink.bin
Size: 436 bytes
Text: 436 bytes
Data: 0 bytes
BSS: 77,824 bytes (heap allocation)
```

## Memory Layout Verification

### Program Headers
```
Type: LOAD
VirtAddr: 0x00000000  ✓ CORRECT - Starts at SRAM base
PhysAddr: 0x00000000
FileSiz:  0x001B4 (436 bytes)
MemSiz:   0x131B4 (78,260 bytes including heap)
```

### Section Layout
```
.text:  0x00000000 - 0x000001B3 (436 bytes)  ✓ Code at start
.data:  0x000001B4 (0 bytes)                 ✓ No initialized data
.bss:   0x000001B4 (0 bytes)                 ✓ No BSS
.heap:  0x000001B4 - 0x000131B3 (77,824 bytes = 15% of 512KB) ✓
```

## Startup Code Verification

### Entry Point
```assembly
00000000 <_start>:
   0:	00080117    auipc	sp,0x80        # Load __stack_top
   4:	00010113    mv	sp,sp           # sp = 0x00080000 ✓
```

**Stack pointer = 0x00080000** ✓ CORRECT - Top of 512KB SRAM

### BSS Clearing
```assembly
   8:	1b400293    li	t0,436          # __bss_start
   c:	1b400313    li	t1,436          # __bss_end

00000010 <clear_bss>:
  10:	0062d863    bge	t0,t1,20 <done_clear_bss>
  14:	0002a023    sw	zero,0(t0)
  18:	00428293    addi	t0,t0,4
  1c:	ff5ff06f    j	10 <clear_bss>
```

**BSS range: 0x1B4 - 0x1B4 (empty)** ✓ CORRECT

### Main Call
```assembly
00000020 <done_clear_bss>:
  20:	034000ef    jal	ra,54 <main>
```

**Calls main at 0x54** ✓ CORRECT

## MMIO Address Verification

### UART Addresses
```assembly
# UART_TX_STATUS (0x80000004)
  38:	00472783    lw	a5,4(a4)   # 80000004 <__stack_top+0x7ff80004>
                                    ✓ CORRECT ADDRESS

# UART_TX_DATA (0x80000000)
  44:	00d72023    sw	a3,0(a4)   # a4 = 0x80000000
                                    ✓ CORRECT ADDRESS
```

### LED Control Address
```assembly
# LED_CONTROL (0x80000010)
  6c:	800007b7    lui	a5,0x80000
  74:	01078613    addi	a2,a5,16  # 80000010 <__stack_top+0x7ff80010>
  94:	00162023    sw	ra,0(a2)   # Write to LED_CONTROL
                                    ✓ CORRECT ADDRESS
```

## LED Pattern Verification

```assembly
# Pattern 1: LED1 on (0x01)
  78:	00100093    li	ra,1
  94:	00162023    sw	ra,0(a2)     # LED_CONTROL = 0x01 ✓

# Pattern 2: LED2 on (0x02)
  84:	00200293    li	t0,2
  ...	            sw	t0,0(a2)     # LED_CONTROL = 0x02 ✓

# Pattern 3: Both on (0x03)
  8c:	00300513    li	a0,3
  ...             sw	a0,0(a2)     # LED_CONTROL = 0x03 ✓

# Pattern 4: Both off (0x00)
  ...             sw	zero,0(a2)   # LED_CONTROL = 0x00 ✓
```

## UART Output Verification

### Startup Messages
```
String 1: "PicoRV32 LED Blink Test\r\n"    - Address 0x17C
String 2: "LED1 and LED2 alternating\r\n"  - Address 0x198
```

### Status Characters
```
'1' (0x31) - LED1 pattern
'2' (0x32) - LED2 pattern
'3' (0x33) - Both LEDs pattern
'0' (0x30) - LEDs off pattern
```

## Timing Parameters

### Delay Loop
```c
delay(1000000);  // ~1M cycles per LED state

At 25 MHz:
1,000,000 cycles = 40 milliseconds per state
4 states × 40ms = 160ms per complete cycle
~6.25 Hz toggle frequency
```

## Summary

✅ **Entry point**: 0x00000000
✅ **Stack pointer**: 0x00080000 (top of 512KB SRAM)
✅ **UART_TX_DATA**: 0x80000000
✅ **UART_TX_STATUS**: 0x80000004
✅ **LED_CONTROL**: 0x80000010
✅ **LED patterns**: 0x01, 0x02, 0x03, 0x00
✅ **Strings embedded**: "PicoRV32 LED Blink Test", "LED1 and LED2 alternating"
✅ **Binary size**: 436 bytes (fits easily in 512KB SRAM)

## Files Generated

- `led_blink.elf` - ELF executable with debug symbols
- `led_blink.bin` - Raw binary (436 bytes)
- `led_blink.hex` - Verilog $readmemh format
- `led_blink.lst` - Disassembly listing
- `led_blink.map` - Linker map file

## Ready for Simulation

The firmware is **VALIDATED** and ready for ModelSim simulation testing.
