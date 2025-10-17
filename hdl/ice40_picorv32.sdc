#==============================================================================
# Olimex iCE40HX8K-EVB RISC-V Platform
# Timing Constraints (SDC format for NextPNR)
#
# Copyright (c) October 2025 Michael Wolak
# Email: mikewolak@gmail.com, mike@epromfoundry.com
#
# NOT FOR COMMERCIAL USE
# Educational and research purposes only
#==============================================================================

# Primary external clock input: 100 MHz crystal oscillator
# Period = 10.0 ns (100 MHz)
# Note: This is divided by 2 internally to generate 50 MHz system clock
create_clock -period 10.0 -name EXTCLK [get_ports {EXTCLK}]

# Internal system clock net: 50 MHz (derived from EXTCLK / 2)
# Period = 20.0 ns (50 MHz)
# This is the critical clock domain that drives PicoRV32 CPU and peripherals
# NextPNR limitation: Cannot use create_generated_clock, so constrain the net directly
create_clock -period 20.0 -name clk [get_nets {clk}]

# Note: NextPNR has limited SDC support
# Unsupported commands: set_input_delay, set_output_delay, set_false_path, create_generated_clock
# Only create_clock is fully supported for iCE40 devices

# For manual I/O timing analysis:
# - SRAM interface: K6R4016V1D-TC10 has 10ns access time
# - UART baud rate: 115200 (8.68us per bit)
# - Button inputs: Asynchronous, debounced in firmware
