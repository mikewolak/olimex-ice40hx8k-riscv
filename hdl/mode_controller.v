//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// mode_controller.v - Mode Controller (SHELL/APP)
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

/*
 * Mode Controller
 * Controls switching between Shell mode and Application (CPU) mode
 *
 * Mode Register (32-bit):
 *   Bit 0: Mode select (0 = Shell, 1 = Application/CPU)
 *   Bits 31-1: Reserved (read as 0)
 *
 * Default: Shell mode (bit 0 = 0)
 * Either Shell or CPU can write to switch modes
 */

module mode_controller (
    input wire clk,
    input wire resetn,

    // Shell control interface
    input wire shell_mode_switch,      // Pulse to switch to app mode (from 'r' command)
    input wire shell_mode_restore,     // Pulse to switch to shell mode (from 's' command)

    // CPU/MMIO control interface
    input wire cpu_mode_write,         // CPU writes to mode register
    input wire [31:0] cpu_mode_wdata,  // Data from CPU
    output reg [31:0] mode_reg_rdata,  // Read data for CPU

    // Mode output
    output reg app_mode                // 0 = Shell, 1 = Application
);

    // Mode register - bit 0 only
    reg mode_bit;

    always @(posedge clk) begin
        if (!resetn) begin
            mode_bit <= 1'b0;          // Default to Shell mode
            app_mode <= 1'b0;
        end else begin
            // Priority: Shell commands > CPU writes
            if (shell_mode_switch) begin
                // Shell 'r' command - switch to app mode
                mode_bit <= 1'b1;
                app_mode <= 1'b1;
            end else if (shell_mode_restore) begin
                // Shell 's' command - switch to shell mode
                mode_bit <= 1'b0;
                app_mode <= 1'b0;
            end else if (cpu_mode_write) begin
                // CPU writes to mode register
                mode_bit <= cpu_mode_wdata[0];
                app_mode <= cpu_mode_wdata[0];
            end else begin
                // Hold current mode
                app_mode <= mode_bit;
            end
        end
    end

    // Read data - always return current mode bit
    always @(*) begin
        mode_reg_rdata = {31'h0, mode_bit};
    end

endmodule
