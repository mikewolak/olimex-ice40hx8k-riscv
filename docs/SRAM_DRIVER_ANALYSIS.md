# SRAM Driver Analysis: K6R4016V1D-TC10

## Overview

This document analyzes the current SRAM driver implementation (`hdl/sram_driver_new.v` and `hdl/sram_proc_new.v`) against the Samsung K6R4016V1D-TC10 datasheet specifications to identify optimization opportunities.

## SRAM Chip Specifications

**Part Number:** K6R4016V1D-TC10 (256K × 16-bit, 512KB total)
**Manufacturer:** Samsung Electronics
**Technology:** 3.3V CMOS SRAM
**Speed Grade:** 10ns (TC10)
**Package:** 44-pin TSOP2 on Olimex iCE40HX8K-EVB

## Critical Timing Parameters (from Datasheet)

### READ CYCLE (K6R4016V1D-10)
| Parameter | Symbol | Min | Max | Unit | Description |
|-----------|--------|-----|-----|------|-------------|
| Read Cycle Time | tRC | 10 | - | ns | Minimum time between read cycles |
| Address Access Time | tAA | - | 10 | ns | Address valid to data valid |
| Chip Select to Output | tCO | - | 10 | ns | CS low to data valid |
| Output Enable to Valid | tOE | - | 5 | ns | OE low to data valid |
| Chip Enable to Low-Z | tLZ | 3 | - | ns | CS low to output driver enable |
| Chip Disable to High-Z | tHZ | 0 | 5 | ns | CS high to output tri-state |
| Output Hold from Addr Change | tOH | 3 | - | ns | Data hold after address change |

### WRITE CYCLE (K6R4016V1D-10)
| Parameter | Symbol | Min | Max | Unit | Description |
|-----------|--------|-----|-----|------|-------------|
| Write Cycle Time | tWC | 10 | - | ns | Minimum time between write cycles |
| Chip Select to End of Write | tCW | 7 | - | ns | CS low to WE high |
| Address Set-up Time | tAS | 0 | - | ns | Address valid before write |
| Address Valid to End of Write | tAW | 7 | - | ns | Address stable during write |
| Write Pulse Width (OE High) | tWP | 7 | - | ns | WE low pulse width |
| Write Pulse Width (OE Low) | tWP1 | 10 | - | ns | WE low pulse width (outputs enabled) |
| Write Recovery Time | tWR | 0 | - | ns | WE high to next cycle |
| Data to Write Time Overlap | tDW | 5 | - | ns | Data valid before WE high |
| Data Hold from Write Time | tDH | 0 | - | ns | Data hold after WE high |

**KEY INSIGHT:** The chip can perform read or write operations in as little as **10ns minimum cycle time**.

## Current Implementation Analysis

### System Clock
- **Frequency:** 50 MHz
- **Period:** 20 ns per clock cycle

### Current Driver Architecture (sram_driver_new.v)

**FSM States:**
```
IDLE (0) → SETUP (1) → ACTIVE (2) → RECOVERY (3) → COOLDOWN (4) → IDLE
```

**Timing per 16-bit Access:**
- **IDLE:** Waiting for valid request (variable duration)
- **SETUP:** 1 cycle (20ns) - Address setup, assert CS, prepare control signals
- **ACTIVE:** 1 cycle (20ns) - Assert WE for write OR sample data for read
- **RECOVERY:** 1 cycle (20ns) - Write recovery / read data capture
- **COOLDOWN:** 1 cycle (20ns) - Mandatory 1-cycle gap after transaction
- **Total:** 5 cycles = **100ns per 16-bit access**

### Current Memory Controller Architecture (sram_proc_new.v)

**32-bit Read Performance:**
- STATE_READ_LOW: Issue first 16-bit read (5 cycles)
- STATE_READ_WAIT1: Wait for ready (1 cycle)
- STATE_READ_SETUP_HIGH: Setup second read (1 cycle)
- STATE_READ_HIGH: Issue second 16-bit read (5 cycles)
- STATE_READ_WAIT2: Wait for data (1 cycle)
- STATE_COMPLETE: Assemble result (1 cycle)
- **Total: ~15 cycles = 300ns per 32-bit read**

**32-bit Write Performance:**
- **Full word (wstrb=4'b1111):** 2 × 16-bit writes = ~14 cycles = 280ns
- **Byte write (wstrb!=4'b1111):** Read-modify-write = ~29 cycles = 580ns

## Timing Compliance Analysis

Current implementation timing vs. datasheet requirements:

| Requirement | Datasheet Min/Max | Current Implementation | Margin | Compliant? |
|-------------|-------------------|------------------------|--------|------------|
| tAS (Address Setup) | 0ns min | 20ns | +20ns | ✓ YES (over-provisioned) |
| tAA (Address Access) | 10ns max | 40ns available | +30ns | ✓ YES (conservative) |
| tWP (Write Pulse) | 7ns min | 20ns | +13ns | ✓ YES (over-provisioned) |
| tDW (Data Setup) | 5ns min | 20ns+ | +15ns | ✓ YES (over-provisioned) |
| tWR (Write Recovery) | 0ns min | 20ns | +20ns | ✓ YES (over-provisioned) |
| tRC (Read Cycle) | 10ns min | 100ns | +90ns | ✓ YES (very conservative) |
| tWC (Write Cycle) | 10ns min | 100ns | +90ns | ✓ YES (very conservative) |

**Analysis:** Current implementation is **timing-compliant** but extremely **over-provisioned** with safety margins of 5-10x the minimum requirements.

## Optimization Opportunities

### Theoretical Maximum Performance at 50MHz

Given the 20ns clock period and 10ns chip access time:

**Optimized 16-bit Read (2 cycles = 40ns):**
```
Cycle 1 (SETUP):
  - Assert address
  - Assert CS low
  - Assert OE low
  - tAA = 10ns max, but we have 20ns

Cycle 2 (CAPTURE):
  - Data is valid (tAA satisfied after 10ns, now at 20ns+)
  - Latch data
  - Deassert CS (if desired)
  - Return to IDLE
```

**Optimized 16-bit Write (2 cycles = 40ns):**
```
Cycle 1 (SETUP):
  - Assert address
  - Assert data
  - Assert CS low
  - Assert WE low
  - tAS = 0ns (no setup required)
  - tDW = 5ns min (need data stable 5ns before WE high)

Cycle 2 (COMPLETE):
  - Hold WE low for at least 7ns (tWP satisfied at 20ns+)
  - Hold data stable
  - Deassert WE high
  - tWR = 0ns (no recovery needed)
  - Return to IDLE
```

**Optimized 32-bit Read (5-6 cycles = 100-120ns):**
- Instead of 15 cycles, could achieve in 5-6 cycles
- Read low word: 2 cycles
- Read high word: 2 cycles
- Assembly: 1 cycle
- Overhead: ~1 cycle
- **Improvement: 2.5-3x faster**

**Optimized 32-bit Write (4-5 cycles = 80-100ns):**
- Instead of 14 cycles, could achieve in 4-5 cycles
- Write low word: 2 cycles
- Write high word: 2 cycles
- Overhead: ~1 cycle
- **Improvement: 2.8-3.5x faster**

### Why Is COOLDOWN Required?

The current implementation includes a mandatory COOLDOWN state. Analyzing the code comments in `sram_driver_new.v`:

```verilog
// COOLDOWN: Mandatory 1-cycle gap after transaction
// This ensures we don't immediately transition to another access
```

**Purpose:**
1. Provides clean CS deassert timing (tHZ = 0-5ns satisfied with 20ns)
2. Ensures no bus contention on bidirectional data bus
3. Allows internal SRAM precharge (though datasheet shows tWR = 0ns)
4. Conservative design for stability

**Question:** Is COOLDOWN strictly necessary per datasheet timing?
**Answer:** NO - Datasheet shows tWR = 0ns min and tRC = 10ns min, meaning back-to-back accesses are allowed. However, COOLDOWN provides safety margin for:
- Bidirectional bus turnaround
- Signal settling time
- Timing closure margin

### Conservative vs. Aggressive Optimization

**Option 1: Conservative (3-cycle access)**
- Maintain safety margins
- Keep bidirectional bus turnaround time
- Reduce from 5 cycles to 3 cycles
- **Performance gain: 1.67x faster**

**Option 2: Moderate (2-cycle access)**
- Meet datasheet minimums with small margin
- Careful bus control for bidirection signals
- Reduce from 5 cycles to 2 cycles
- **Performance gain: 2.5x faster**

**Option 3: Aggressive (pipelined)**
- Remove IDLE states between accesses
- Pipeline address and data phases
- Requires significant redesign
- **Performance gain: 3-4x faster** (with burst access)

## Impact on System Performance

Current CPU memory bandwidth (estimated):

**Read Performance:**
- 32-bit read: 15 cycles = 300ns
- Bandwidth: 4 bytes / 300ns = 13.3 MB/s

**Write Performance:**
- 32-bit write (full): 14 cycles = 280ns
- Bandwidth: 4 bytes / 280ns = 14.3 MB/s
- 32-bit write (byte): 29 cycles = 580ns
- Bandwidth: 4 bytes / 580ns = 6.9 MB/s

**Optimized Performance (2-cycle driver):**
- 32-bit read: 5 cycles = 100ns
- Bandwidth: 4 bytes / 100ns = **40 MB/s** (3x improvement)
- 32-bit write (full): 5 cycles = 100ns
- Bandwidth: 4 bytes / 100ns = **40 MB/s** (2.9x improvement)

**Impact on RISC-V CPU:**
- Fewer wait states for memory access
- Faster instruction fetch
- Improved interrupt latency
- Better overall system responsiveness

## Recommendations

### Short-term: 3-Cycle Implementation (Conservative)

**Pros:**
- Minimal risk
- 1.67x performance improvement
- Maintains safety margins
- Easy to verify

**Implementation:**
```
IDLE → SETUP (1 cycle) → ACTIVE (1 cycle) → COMPLETE (1 cycle) → IDLE
```

**Changes required:**
- Merge RECOVERY into ACTIVE
- Merge COOLDOWN into COMPLETE
- Adjust ready signal timing

### Medium-term: 2-Cycle Implementation (Moderate)

**Pros:**
- 2.5x performance improvement
- Meets datasheet specs with margin
- Significant system speedup

**Cons:**
- Requires careful verification
- Bidirectional bus timing critical
- May need signal settling analysis

**Implementation:**
```
IDLE → SETUP (1 cycle) → COMPLETE (1 cycle) → IDLE
```

**Changes required:**
- Combine setup and active phases
- Remove explicit recovery/cooldown
- Tighten bus turnaround timing

### Long-term: Pipelined Implementation (Aggressive)

**Pros:**
- 3-4x performance improvement
- Maximizes SRAM bandwidth
- Supports burst access

**Cons:**
- Major redesign effort
- Complex state machine
- Harder to verify
- May require timing closure iteration

## Testing Strategy

For any optimization:

1. **Simulation Testing:**
   - Run existing bootloader testbench
   - Run timer interrupt test
   - Add stress tests for back-to-back accesses
   - Verify read-modify-write sequences

2. **Timing Analysis:**
   - Use icetime to verify timing closure
   - Check setup/hold margins on SRAM pins
   - Verify bidirectional bus timing

3. **Hardware Testing:**
   - Test on FPGA with led_blink firmware
   - Test timer interrupt firmware (stress test)
   - Test interactive UART shell (data integrity)
   - Run memory test patterns

4. **Regression Testing:**
   - Ensure bootloader still functions
   - Verify interrupt handling unchanged
   - Check all existing firmware

## Conclusion

**Current State:** The SRAM driver is timing-compliant but highly conservative, using 100ns (5 cycles) per 16-bit access despite the chip supporting 10ns minimum cycle time.

**Optimization Potential:** 2-3x performance improvement is achievable with moderate risk by reducing to 2-3 cycles per access.

**Recommendation:** Start with **3-cycle implementation** as a safe first step, then evaluate **2-cycle implementation** after validation.

**System Impact:** Memory bandwidth could improve from ~13 MB/s to ~30-40 MB/s, significantly benefiting CPU performance, interrupt latency, and overall system responsiveness.

## Files Analyzed

- `hdl/sram_driver_new.v` - Physical SRAM interface (200 lines)
- `hdl/sram_proc_new.v` - 32-bit memory controller (460 lines)
- `reference/ds_k6r4016v1d_rev40.pdf` - Samsung K6R4016V1D datasheet

## Date

October 13, 2025

## Author

Michael Wolak
