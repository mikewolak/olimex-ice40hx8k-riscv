//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// sram_proc_optimized.v - OPTIMIZED SRAM Memory Controller
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//
// OPTIMIZATION: Reduced from 11-cycle to 7-cycle per 32-bit access (36% faster!)
// KEY CHANGES:
// - Eliminated STATE_READ_WAIT1, STATE_READ_SETUP_HIGH (redundant)
// - Eliminated STATE_WRITE_WAIT1, STATE_WRITE_SETUP_HIGH (redundant)
// - Single STATE_WAIT between low/high accesses for handshaking
// - valid assertion aligned with driver's first cycle for immediate start
//
// TIMING: 7 cycles per 32-bit read/write (was 11 cycles)
// - Cycle 1: LOW word (assert valid+addr)
// - Cycles 2-3: Driver responds (2-cycle driver)
// - Cycle 4: WAIT (handshake)
// - Cycle 5: HIGH word (assert valid+addr)
// - Cycles 6-7: Driver responds
// = 140ns @ 50MHz instead of 220ns
//==============================================================================

module sram_proc_optimized (
    input wire clk,
    input wire resetn,

    // Command interface
    input wire start,
    input wire [7:0] cmd,
    input wire [31:0] addr_in,      // Byte address
    input wire [31:0] data_in,      // 32-bit data
    input wire [3:0] mem_wstrb,     // Write strobes: [3]=byte3, [2]=byte2, [1]=byte1, [0]=byte0
    output reg busy,
    output reg done,
    output reg [31:0] result,
    output reg [15:0] result_low,
    output reg [15:0] result_high,

    // UART interface (unused in this version, for future expansion)
    input wire [7:0] rx_byte,
    input wire rx_valid,
    output reg [7:0] tx_data,
    output reg tx_valid,
    input wire tx_ready,

    // SRAM driver interface
    output reg sram_valid,
    input wire sram_ready,
    output reg sram_we,
    output reg [18:0] sram_addr_16,    // 16-bit word address
    output reg [15:0] sram_wdata_16,
    input wire [15:0] sram_rdata_16
);

    // Command codes
    localparam CMD_NONE  = 8'h00;
    localparam CMD_READ  = 8'h01;
    localparam CMD_WRITE = 8'h02;
    localparam CMD_CRC   = 8'h04;

    // States (OPTIMIZED - removed redundant wait/setup states)
    localparam STATE_IDLE = 4'h0;
    localparam STATE_READ_LOW = 4'h1;
    localparam STATE_WAIT = 4'h2;           // Single wait state between low/high
    localparam STATE_READ_HIGH = 4'h3;
    localparam STATE_COMPLETE = 4'h4;
    localparam STATE_DONE = 4'h5;

    localparam STATE_WRITE_LOW = 4'h6;
    localparam STATE_WRITE_HIGH = 4'h7;

    localparam STATE_CRC_INIT = 5'd8;
    localparam STATE_CRC_READ_LOW = 5'd9;
    localparam STATE_CRC_READ_HIGH = 5'd10;
    localparam STATE_CRC_CALC = 5'd11;

    // Read-Modify-Write states for byte/halfword writes
    localparam STATE_WRITE_RMW_READ_LOW = 5'd12;
    localparam STATE_WRITE_RMW_READ_HIGH = 5'd13;
    localparam STATE_WRITE_RMW_MERGE = 5'd14;

    reg [4:0] state;
    reg [7:0] current_cmd;
    reg [31:0] current_addr;
    reg [31:0] current_data;
    reg [3:0] current_wstrb;
    reg [15:0] temp_low_word;
    reg [31:0] old_data;         // Original data from SRAM for RMW

    // CRC32 support
    reg [31:0] crc_value;
    reg [31:0] crc_start_addr;
    reg [31:0] crc_end_addr;
    reg [31:0] crc_current_addr;
    reg [31:0] read_word;

    // CRC32 calculation (Ethernet polynomial)
    function [31:0] crc32_update;
        input [31:0] crc;
        input [31:0] data;
        integer i;
        reg [31:0] temp_crc;
        reg [31:0] temp_data;
        begin
            temp_crc = crc;
            temp_data = data;
            for (i = 0; i < 32; i = i + 1) begin
                if (temp_crc[0] ^ temp_data[0])
                    temp_crc = (temp_crc >> 1) ^ 32'hEDB88320;
                else
                    temp_crc = temp_crc >> 1;
                temp_data = temp_data >> 1;
            end
            crc32_update = temp_crc;
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            state <= STATE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            result <= 32'h0;
            result_low <= 16'h0;
            result_high <= 16'h0;
            sram_valid <= 1'b0;
            sram_we <= 1'b0;
            sram_addr_16 <= 19'h0;
            sram_wdata_16 <= 16'h0;
            current_cmd <= CMD_NONE;
            current_addr <= 32'h0;
            current_data <= 32'h0;
            current_wstrb <= 4'h0;
            temp_low_word <= 16'h0;
            old_data <= 32'h0;
            crc_value <= 32'hFFFFFFFF;
            tx_valid <= 1'b0;
        end else begin
            // Clear done pulse after one cycle
            done <= 1'b0;
            tx_valid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    busy <= 1'b0;
                    sram_valid <= 1'b0;
                    sram_we <= 1'b0;

                    if (start && !busy) begin
                        busy <= 1'b1;
                        current_cmd <= cmd;
                        current_addr <= addr_in;
                        current_data <= data_in;
                        current_wstrb <= mem_wstrb;

                        // synthesis translate_off
                        $display("[SRAM_PROC] START: cmd=0x%02x addr=0x%08x data=0x%08x wstrb=0x%01x",
                                 cmd, addr_in, data_in, mem_wstrb);
                        // synthesis translate_on

                        case (cmd)
                            CMD_READ: state <= STATE_READ_LOW;
                            CMD_WRITE: begin
                                // Full word write (wstrb = 4'b1111)? Use fast path
                                // Otherwise need read-modify-write
                                if (mem_wstrb == 4'b1111)
                                    state <= STATE_WRITE_LOW;
                                else
                                    state <= STATE_WRITE_RMW_READ_LOW;
                            end
                            CMD_CRC: begin
                                crc_start_addr <= addr_in;
                                crc_end_addr <= data_in;
                                state <= STATE_CRC_INIT;
                            end
                            default: begin
                                busy <= 1'b0;
                                done <= 1'b1;
                            end
                        endcase
                    end
                end

                // ============ READ OPERATION (OPTIMIZED) ============
                // Read 32-bit word as two 16-bit SRAM accesses (7 cycles total)
                STATE_READ_LOW: begin
                    // Cycle 1: Assert valid+address immediately (edge-aligned with driver)
                    sram_addr_16 <= current_addr[18:1];  // Low 16-bit word address
                    sram_we <= 1'b0;
                    sram_valid <= 1'b1;

                    // synthesis translate_off
                    $display("[SRAM_PROC] READ_LOW: byte_addr=0x%08x word_addr=0x%05x",
                             current_addr, current_addr[18:1]);
                    // synthesis translate_on

                    if (sram_ready) begin
                        // Cycle 2: Driver completed, capture low word
                        temp_low_word <= sram_rdata_16;

                        // synthesis translate_off
                        $display("[SRAM_PROC] READ_LOW complete: data=0x%04x", sram_rdata_16);
                        // synthesis translate_on

                        state <= STATE_WAIT;
                    end
                end

                STATE_WAIT: begin
                    // Cycle 3: Single wait cycle to deassert valid and setup high address
                    sram_valid <= 1'b0;
                    sram_addr_16 <= current_addr[18:1] + 18'd1;  // High 16-bit word address

                    if (current_cmd == CMD_WRITE) begin
                        // Setup for write high
                        sram_wdata_16 <= current_data[31:16];
                        sram_we <= 1'b0;
                        state <= STATE_WRITE_HIGH;

                        // synthesis translate_off
                        $display("[SRAM_PROC] WAIT: Setup WRITE high word_addr=0x%05x data=0x%04x",
                                 current_addr[18:1] + 18'd1, current_data[31:16]);
                        // synthesis translate_on
                    end else begin
                        // Setup for read high
                        sram_we <= 1'b0;
                        state <= STATE_READ_HIGH;

                        // synthesis translate_off
                        $display("[SRAM_PROC] WAIT: Setup READ high word_addr=0x%05x",
                                 current_addr[18:1] + 18'd1);
                        // synthesis translate_on
                    end
                end

                STATE_READ_HIGH: begin
                    // Cycle 4: Assert valid+address immediately (edge-aligned with driver)
                    sram_valid <= 1'b1;

                    // synthesis translate_off
                    $display("[SRAM_PROC] READ_HIGH: Starting high word read");
                    // synthesis translate_on

                    if (sram_ready) begin
                        // Cycle 5: Driver completed, capture high word
                        read_word[31:16] <= sram_rdata_16;
                        read_word[15:0] <= temp_low_word;
                        sram_valid <= 1'b0;

                        // synthesis translate_off
                        $display("[SRAM_PROC] READ_HIGH complete: data=0x%04x", sram_rdata_16);
                        // synthesis translate_on

                        state <= STATE_COMPLETE;
                    end
                end

                STATE_COMPLETE: begin
                    // Cycle 6: Assemble result and signal done (combined to save a cycle)
                    result_low <= read_word[15:0];
                    result_high <= read_word[31:16];
                    result <= read_word;
                    done <= 1'b1;
                    busy <= 1'b0;

                    // synthesis translate_off
                    $display("[SRAM_PROC] COMPLETE: result=0x%08x (done)", read_word);
                    // synthesis translate_on

                    state <= STATE_IDLE;
                end

                // ============ WRITE OPERATION (OPTIMIZED) ============
                // Write 32-bit word as two 16-bit SRAM accesses (7 cycles total)
                STATE_WRITE_LOW: begin
                    // Cycle 1: Assert valid+address+data immediately
                    sram_addr_16 <= current_addr[18:1];  // Low 16-bit word address
                    sram_wdata_16 <= current_data[15:0];
                    sram_we <= 1'b1;
                    sram_valid <= 1'b1;

                    // synthesis translate_off
                    $display("[SRAM_PROC] WRITE_LOW: byte_addr=0x%08x word_addr=0x%05x data=0x%04x",
                             current_addr, current_addr[18:1], current_data[15:0]);
                    // synthesis translate_on

                    if (sram_ready) begin
                        // Cycle 2: Driver completed write
                        // synthesis translate_off
                        $display("[SRAM_PROC] WRITE_LOW complete");
                        // synthesis translate_on

                        state <= STATE_WAIT;
                    end
                end

                STATE_WRITE_HIGH: begin
                    // Cycle 4: Assert valid+address+data immediately
                    sram_we <= 1'b1;
                    sram_valid <= 1'b1;

                    // synthesis translate_off
                    $display("[SRAM_PROC] WRITE_HIGH: word_addr=0x%05x data=0x%04x",
                             current_addr[18:1] + 18'd1, current_data[31:16]);
                    // synthesis translate_on

                    if (sram_ready) begin
                        // Cycle 5: Driver completed write
                        result <= 32'h00000000;
                        sram_valid <= 1'b0;
                        sram_we <= 1'b0;
                        done <= 1'b1;
                        busy <= 1'b0;

                        // synthesis translate_off
                        $display("[SRAM_PROC] WRITE_HIGH complete (done)");
                        // synthesis translate_on

                        state <= STATE_IDLE;
                    end
                end

                // ============ READ-MODIFY-WRITE for BYTE/HALFWORD WRITES (OPTIMIZED) ============
                STATE_WRITE_RMW_READ_LOW: begin
                    // Read low 16-bit word to get current value
                    sram_addr_16 <= current_addr[18:1];
                    sram_we <= 1'b0;
                    sram_valid <= 1'b1;

                    // synthesis translate_off
                    $display("[SRAM_PROC] RMW_READ_LOW: word_addr=0x%05x", current_addr[18:1]);
                    // synthesis translate_on

                    if (sram_ready) begin
                        old_data[15:0] <= sram_rdata_16;
                        // Reuse STATE_WAIT but branch to RMW_READ_HIGH
                        // For this we'll go directly and use a flag or different approach
                        sram_valid <= 1'b0;
                        sram_addr_16 <= current_addr[18:1] + 18'd1;
                        state <= STATE_WRITE_RMW_READ_HIGH;

                        // synthesis translate_off
                        $display("[SRAM_PROC] RMW_READ_LOW complete: data=0x%04x", sram_rdata_16);
                        // synthesis translate_on
                    end
                end

                STATE_WRITE_RMW_READ_HIGH: begin
                    // Read high 16-bit word to get current value
                    sram_valid <= 1'b1;

                    // synthesis translate_off
                    $display("[SRAM_PROC] RMW_READ_HIGH: word_addr=0x%05x", current_addr[18:1] + 18'd1);
                    // synthesis translate_on

                    if (sram_ready) begin
                        old_data[31:16] <= sram_rdata_16;
                        sram_valid <= 1'b0;
                        state <= STATE_WRITE_RMW_MERGE;

                        // synthesis translate_off
                        $display("[SRAM_PROC] RMW_READ_HIGH complete: data=0x%04x", sram_rdata_16);
                        // synthesis translate_on
                    end
                end

                STATE_WRITE_RMW_MERGE: begin
                    // Merge new data with old data based on write strobes
                    // wstrb[0] = byte 0 (bits 7:0)
                    // wstrb[1] = byte 1 (bits 15:8)
                    // wstrb[2] = byte 2 (bits 23:16)
                    // wstrb[3] = byte 3 (bits 31:24)
                    current_data[7:0]   <= current_wstrb[0] ? current_data[7:0]   : old_data[7:0];
                    current_data[15:8]  <= current_wstrb[1] ? current_data[15:8]  : old_data[15:8];
                    current_data[23:16] <= current_wstrb[2] ? current_data[23:16] : old_data[23:16];
                    current_data[31:24] <= current_wstrb[3] ? current_data[31:24] : old_data[31:24];

                    // synthesis translate_off
                    $display("[SRAM_PROC] RMW_MERGE: old=0x%08x new=0x%08x wstrb=0x%01x",
                             old_data, current_data, current_wstrb);
                    // synthesis translate_on

                    // Now proceed with normal write sequence
                    state <= STATE_WRITE_LOW;
                end

                // ============ CRC32 OPERATION ============
                STATE_CRC_INIT: begin
                    crc_value <= 32'hFFFFFFFF;
                    crc_current_addr <= crc_start_addr;
                    state <= STATE_CRC_READ_LOW;
                end

                STATE_CRC_READ_LOW: begin
                    // Start or continue CRC loop - setup address
                    if (!sram_valid) begin
                        sram_addr_16 <= crc_current_addr[18:1];  // 18-bit word address
                        sram_we <= 1'b0;
                        sram_valid <= 1'b1;
                    end else if (sram_ready) begin
                        temp_low_word <= sram_rdata_16;
                        sram_valid <= 1'b0;  // Clear valid immediately when ready seen
                        state <= STATE_CRC_READ_HIGH;
                    end
                end

                STATE_CRC_READ_HIGH: begin
                    // Wait for valid to go low
                    state <= STATE_CRC_SETUP_HIGH;
                end

                STATE_CRC_SETUP_HIGH: begin
                    // Setup high read address
                    sram_addr_16 <= crc_current_addr[18:1] + 18'd1;  // Next 18-bit word address
                    sram_we <= 1'b0;
                    state <= STATE_CRC_CALC;
                end

                STATE_CRC_CALC: begin
                    // Assert valid for high read
                    if (!sram_valid) begin
                        sram_valid <= 1'b1;
                    end else if (sram_ready) begin
                        // Got high word, assemble and update CRC
                        read_word[15:0] <= temp_low_word;
                        read_word[31:16] <= sram_rdata_16;
                        crc_value <= crc32_update(crc_value, {sram_rdata_16, temp_low_word});
                        crc_current_addr <= crc_current_addr + 4;
                        sram_valid <= 1'b0;  // Clear valid immediately when ready seen

                        if (crc_current_addr + 4 >= crc_end_addr) begin
                            result <= ~crc32_update(crc_value, {sram_rdata_16, temp_low_word});
                            state <= STATE_DONE;
                        end else begin
                            state <= STATE_CRC_READ_LOW;
                        end
                    end
                end

                // ============ DONE STATE (Used by CRC only) ============
                STATE_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    sram_valid <= 1'b0;
                    sram_we <= 1'b0;

                    // synthesis translate_off
                    $display("[SRAM_PROC] DONE: result=0x%08x", result);
                    // synthesis translate_on

                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    // ========================================================================
    // OPTIMIZATION SUMMARY
    // ========================================================================
    // 32-bit Memory Access Performance:
    //
    // OLD (11 cycles):
    //   Cycle 1:  STATE_READ_LOW (setup)
    //   Cycle 2:  Driver ACTIVE
    //   Cycle 3:  Driver COMPLETE (ready=1)
    //   Cycle 4:  STATE_READ_WAIT1
    //   Cycle 5:  STATE_READ_SETUP_HIGH
    //   Cycle 6:  STATE_READ_HIGH (setup)
    //   Cycle 7:  Driver ACTIVE
    //   Cycle 8:  Driver COMPLETE (ready=1)
    //   Cycle 9:  STATE_READ_WAIT2
    //   Cycle 10: STATE_COMPLETE
    //   Cycle 11: STATE_DONE
    //
    // NEW (7 cycles - 36% faster!):
    //   Cycle 1:  STATE_READ_LOW (assert valid+addr, edge-aligned)
    //   Cycle 2:  Driver COMPLETE (ready=1, capture low word)
    //   Cycle 3:  STATE_WAIT (deassert valid, setup high addr)
    //   Cycle 4:  STATE_READ_HIGH (assert valid+addr, edge-aligned)
    //   Cycle 5:  Driver COMPLETE (ready=1, capture high word)
    //   Cycle 6:  STATE_COMPLETE (assemble result, signal done)
    //   Cycle 7:  STATE_IDLE
    //
    // Key changes:
    //   - Eliminated redundant WAIT1/SETUP_HIGH/WAIT2 states
    //   - Assert valid+address immediately (edge-aligned with driver)
    //   - Single STATE_WAIT between low/high accesses
    //   - Signal done directly in final state (no separate DONE cycle)
    //
    // Performance impact on 50MHz PicoRV32:
    //   - Memory access: 220ns → 140ns (36% faster)
    //   - Mandelbrot benchmark: ~0.06 M iter/s → ~0.10 M iter/s expected
    // ========================================================================

endmodule
