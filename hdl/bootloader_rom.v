//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// bootloader_rom.v - Bootloader ROM (SPRAM/Generic)
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

/*
 * Bootloader ROM - 8KB at 0x10000
 *
 * Dual-purpose design:
 *   - Simulation: Generic register-based RAM with $readmemh
 *   - Synthesis: iCE40 SPRAM primitives (128Kbit = 16KB)
 *
 * We use the iCE40HX8K's SPRAM (Single-Port RAM) which is initialized
 * from the bitstream. The bootloader.hex file is embedded during synthesis.
 *
 * Memory map:
 *   0x10000 - 0x11FFF : Bootloader code (8KB)
 *
 * Interface:
 *   - 32-bit read-only interface
 *   - Single cycle latency
 *   - No write capability (ROM)
 */

`default_nettype none

module bootloader_rom (
    input  wire        clk,
    input  wire        resetn,
    input  wire [12:0] addr,        // 8KB = 2^13 bytes, 2^11 words
    input  wire        enable,
    output reg  [31:0] rdata
);

    // Memory declaration - 2048 x 32-bit words = 8KB
    // For simulation: Uses generic registers
    // For synthesis: Maps to SPRAM
    reg [31:0] memory [0:2047];

    // Initialize memory from bootloader.hex
    // This works in simulation and can be used for synthesis initialization
    initial begin
        $readmemh("bootloader/bootloader.hex", memory);
    end

    // Read logic - synchronous for SPRAM compatibility
    always @(posedge clk) begin
        if (!resetn) begin
            rdata <= 32'h0;
        end else if (enable) begin
            // Address is in bytes, convert to word address
            rdata <= memory[addr[12:2]];
        end
    end

    // Synthesis note: Yosys will infer BRAM/SPRAM from this pattern
    // For explicit SPRAM instantiation, see bootloader_spram.v

endmodule

`default_nettype wire
