//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// shell.v - Interactive Shell Command Processor
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module shell (
    input wire clk,
    input wire resetn,

    input wire [7:0] buffer_rd_data,
    output reg buffer_rd_en,
    input wire buffer_empty,
    output reg buffer_clear,

    output reg [7:0] uart_tx_data,
    output reg uart_tx_valid,
    input wire uart_tx_ready,
    
    output reg sram_proc_start,
    output reg [7:0] sram_proc_cmd,
    output reg [31:0] sram_proc_addr,
    output reg [31:0] sram_proc_data,
    input wire sram_proc_busy,
    input wire sram_proc_done,
    input wire [31:0] sram_proc_result,
    input wire [15:0] sram_proc_result_low,
    input wire [15:0] sram_proc_result_high,
    
    output reg fw_loader_start,
    input wire fw_loader_busy,
    input wire fw_loader_done,
    input wire fw_loader_error,
    input wire [7:0] fw_loader_nak_reason,

    // CPU control
    output reg cpu_run,          // Pulse to release CPU from reset
    output reg cpu_stop,         // Pulse to hold CPU in reset
    output reg mode_restore      // Pulse to switch back to shell mode (for 's' command from shell)
);

    localparam STATE_IDLE = 5'h00;
    localparam STATE_PROMPT = 5'h01;
    localparam STATE_WAIT_INPUT = 5'h02;
    localparam STATE_PARSE_CMD = 5'h03;
    localparam STATE_EXEC_CMD = 5'h04;
    localparam STATE_SEND_OUTPUT = 5'h05;
    localparam STATE_WAIT_SUBPROCESS = 5'h06;
    localparam STATE_ERROR_MSG = 5'h07;
    localparam STATE_CRC_SEND_BYTE = 5'h08;
    localparam STATE_PROMPT_START = 5'h09;
    localparam STATE_WAIT_START_ADDR = 5'h0A;
    localparam STATE_PROMPT_END = 5'h0B;
    localparam STATE_WAIT_END_ADDR = 5'h0C;
    localparam STATE_CRC_EXEC = 5'h0D;
    localparam STATE_CRC_PARSE_START = 5'h0E;
    localparam STATE_CRC_PARSE_END = 5'h0F;
    localparam STATE_CRC_WAIT_FORMAT = 5'h10;
    localparam STATE_SEND_PREP = 5'h11;
    localparam STATE_UPLOAD_DRAIN = 5'h12;
    localparam STATE_CPU_RUN_WAIT_INSTR = 5'h13;
    localparam STATE_WRITE_PARSE = 5'h14;
    localparam STATE_WRITE_EXEC = 5'h15;
    localparam STATE_MEM_READ = 5'h16;
    localparam STATE_MEM_WAIT = 5'h17;
    localparam STATE_MEM_WAIT_FORMAT = 5'h18;
    localparam STATE_MEM_WAIT_FORMAT2 = 5'h19;
    localparam STATE_MEM_SEND_BYTE = 5'h1A;
    localparam STATE_MEM_DISPLAY = 5'h1B;
    localparam STATE_MEM_WAIT_KEY = 5'h1C;
    localparam STATE_MEM_WAIT_OUTPUT = 5'h1D;
    localparam STATE_CPU_RUN = 5'h1E;
    localparam STATE_CPU_RUN_READ_INSTR = 5'h1F;

    localparam CMD_NONE = 8'h00;
    localparam CMD_READ = 8'h01;
    localparam CMD_WRITE = 8'h02;
    localparam CMD_CRC = 8'h04;
    localparam CMD_MEM = 8'h07;
    
    localparam TIMEOUT_CYCLES = 32'd50_000_000;  // Reduced from 200M to save logic

    reg [4:0] state;
    reg [25:0] timeout_counter;  // Reduced from 32 bits (max 67M cycles = 0.67s)
    reg [7:0] command_buffer [0:31];  // Reduced from 128 to save logic cells
    reg [7:0] cmd_length;
    reg [7:0] current_cmd;
    reg buffer_read_state;
    reg buffer_data_valid;
    reg [7:0] current_rx_byte;
    reg [7:0] output_buffer [0:95];  // Increased to 96 bytes for hexdump -C format
    reg [8:0] output_length;
    reg [8:0] output_index;
    reg sram_proc_done_seen;  // Flag to handle sram_proc_done only once
    reg [31:0] shell_assembled_result;

    // CRC command support
    reg [31:0] crc_start_addr;
    reg [31:0] crc_end_addr;
    reg [7:0] addr_input_length;
    reg [31:0] parsed_addr;
    reg [4:0] hex_nibble;  // Temporary for hex parsing

    // WRITE command support
    reg [31:0] write_addr;
    reg [31:0] write_data;

    // MEM command support
    reg [31:0] mem_addr;         // Current display address
    reg [4:0] mem_line_count;    // Lines displayed (0-31)
    reg [5:0] mem_byte_index;    // Byte being sent to UART (0-58)
    reg [31:0] mem_word0, mem_word1, mem_word2, mem_word3;  // 4 words = 16 bytes for current line
    reg [2:0] mem_read_count;    // Track which word we're reading (0-3 for 4 words)
    reg [4:0] parse_index;       // Index for parsing hex address/data (needs to reach 16)
    reg [31:0] sram_result_latched;  // Latched copy of sram_proc_result for stable access

    // Function to convert byte to ASCII (printable or '.')
    function [7:0] byte_to_ascii;
        input [7:0] byte_val;
        begin
            // Check if printable (32-126)
            if (byte_val < 8'd32 || byte_val > 8'd126)
                byte_to_ascii = 8'h2E;  // '.'
            else
                byte_to_ascii = byte_val;
        end
    endfunction

    // CPU RUN command support
    reg [31:0] first_instruction;  // Store first instruction at address 0x00000000
    
    always @(posedge clk) begin
        if (!resetn) begin
            buffer_rd_en <= 1'b0;
            buffer_read_state <= 1'b0;
            buffer_data_valid <= 1'b0;
            current_rx_byte <= 8'h00;
        end else begin
            buffer_rd_en <= 1'b0;
            buffer_data_valid <= 1'b0;
            
            case (buffer_read_state)
                1'b0: begin
                    if (!buffer_empty && (state == STATE_WAIT_INPUT ||
                                          state == STATE_WAIT_START_ADDR ||
                                          state == STATE_WAIT_END_ADDR ||
                                          state == STATE_MEM_WAIT_KEY)) begin
                        buffer_rd_en <= 1'b1;
                        buffer_read_state <= 1'b1;
                    end
                end
                1'b1: begin
                    current_rx_byte <= buffer_rd_data;
                    buffer_data_valid <= 1'b1;
                    buffer_read_state <= 1'b0;
                end
            endcase
        end
    end
    
    wire timeout_active = (state == STATE_WAIT_INPUT) || (state == STATE_WAIT_SUBPROCESS);
    
    always @(posedge clk) begin
        if (!resetn || !timeout_active) begin
            timeout_counter <= 26'd0;
        end else if (buffer_data_valid || sram_proc_done || fw_loader_done || fw_loader_error) begin
            timeout_counter <= 26'd0;
        end else if (timeout_counter < TIMEOUT_CYCLES) begin
            timeout_counter <= timeout_counter + 1;
        end
    end
    
    wire timeout_expired = (timeout_counter >= TIMEOUT_CYCLES);
    
    function [7:0] hex_to_ascii;
        input [3:0] hex;
        begin
            hex_to_ascii = (hex < 10) ? (8'h30 + hex) : (8'h41 + hex - 10);
        end
    endfunction

    // Parse hex ASCII character to 4-bit value
    // Returns 5'h10 for invalid character
    function [4:0] ascii_to_hex;
        input [7:0] ascii;
        begin
            if (ascii >= 8'h30 && ascii <= 8'h39)  // '0'-'9'
                ascii_to_hex = {1'b0, ascii[3:0]};
            else if (ascii >= 8'h41 && ascii <= 8'h46)  // 'A'-'F'
                ascii_to_hex = {1'b0, ascii[3:0] + 4'd9};
            else if (ascii >= 8'h61 && ascii <= 8'h66)  // 'a'-'f'
                ascii_to_hex = {1'b0, ascii[3:0] + 4'd9};
            else
                ascii_to_hex = 5'h10;  // Invalid
        end
    endfunction


    always @(posedge clk) begin
        if (!resetn) begin
            state <= STATE_PROMPT;
            cmd_length <= 8'd0;
            current_cmd <= CMD_NONE;
            output_length <= 9'd0;
            output_index <= 9'd0;
            uart_tx_valid <= 1'b0;
            sram_proc_start <= 1'b0;
            fw_loader_start <= 1'b0;
            buffer_clear <= 1'b0;
            cpu_run <= 1'b0;
            cpu_stop <= 1'b0;
            mode_restore <= 1'b0;
            shell_assembled_result <= 32'h0;
            sram_proc_done_seen <= 1'b0;
            mem_word0 <= 32'h0;
            mem_word1 <= 32'h0;
            mem_word2 <= 32'h0;
            mem_word3 <= 32'h0;
            mem_addr <= 32'h0;
            mem_line_count <= 5'd0;
            mem_read_count <= 3'd0;
        end else begin
            sram_proc_start <= 1'b0;
            fw_loader_start <= 1'b0;
            buffer_clear <= 1'b0;
            cpu_run <= 1'b0;
            cpu_stop <= 1'b0;
            mode_restore <= 1'b0;

            if (uart_tx_valid && uart_tx_ready) begin
                uart_tx_valid <= 1'b0;
            end
            
            case (state)
                STATE_IDLE: begin
                    state <= STATE_PROMPT;
                end
                
                STATE_PROMPT: begin
                    if (!uart_tx_valid && uart_tx_ready) begin
                        if (output_index == 0) begin
                            uart_tx_data <= 8'h3E;
                            uart_tx_valid <= 1'b1;
                            output_index <= 1;
                        end else if (output_index == 1) begin
                            uart_tx_data <= 8'h20;
                            uart_tx_valid <= 1'b1;
                            output_index <= 0;
                            cmd_length <= 0;
                            state <= STATE_WAIT_INPUT;
                        end
                    end
                end
                
                STATE_WAIT_INPUT: begin
                    if (buffer_data_valid) begin
                        if (!uart_tx_valid && uart_tx_ready) begin
                            uart_tx_data <= current_rx_byte;
                            uart_tx_valid <= 1'b1;
                        end
                        
                        if (current_rx_byte == 8'h0D || current_rx_byte == 8'h0A) begin
                            state <= STATE_PARSE_CMD;
                        end else if (cmd_length < 127) begin
                            command_buffer[cmd_length] <= current_rx_byte;
                            cmd_length <= cmd_length + 1;
                        end
                    end
                end
                
                STATE_PARSE_CMD: begin
                    if (cmd_length == 21 &&
                        command_buffer[0] == 8'h63 &&  // 'c'
                        command_buffer[1] == 8'h72 &&  // 'r'
                        command_buffer[2] == 8'h63 &&  // 'c'
                        command_buffer[3] == 8'h20) begin  // ' '
                        // Format: "crc 00000000 00000100" (21 chars: crc + space + 8 + space + 8)
                        current_cmd <= CMD_CRC;
                        parsed_addr <= 32'h0;
                        parse_index <= 0;
                        state <= STATE_CRC_PARSE_START;
                    end else if (cmd_length == 3 &&
                        command_buffer[0] == 8'h63 &&  // 'c'
                        command_buffer[1] == 8'h72 &&  // 'r'
                        command_buffer[2] == 8'h63) begin  // 'c'
                        // Interactive mode "crc" - prompt for addresses
                        current_cmd <= CMD_CRC;
                        state <= STATE_PROMPT_START;
                    end else if (cmd_length == 19 &&
                        command_buffer[0] == 8'h77 &&  // 'w'
                        command_buffer[1] == 8'h20) begin  // ' '
                        // Format: "w 00000000 12345678" (1 + 1 + 8 + 1 + 8 = 19 chars)
                        current_cmd <= CMD_WRITE;
                        parsed_addr <= 32'h0;
                        write_data <= 32'h0;
                        parse_index <= 0;
                        state <= STATE_WRITE_PARSE;
                    end else if (cmd_length == 3 &&
                        command_buffer[0] == 8'h6D &&  // 'm'
                        command_buffer[1] == 8'h65 &&  // 'e'
                        command_buffer[2] == 8'h6D) begin  // 'm'
                        // Memory display command
                        current_cmd <= CMD_MEM;
                        mem_addr <= 32'h00000000;
                        mem_line_count <= 5'd0;
                        mem_read_count <= 3'd0;
                        state <= STATE_MEM_READ;
                    end else if (cmd_length == 6 &&
                        command_buffer[0] == 8'h75 &&  // 'u'
                        command_buffer[1] == 8'h70 &&  // 'p'
                        command_buffer[2] == 8'h6C &&  // 'l'
                        command_buffer[3] == 8'h6F &&  // 'o'
                        command_buffer[4] == 8'h61 &&  // 'a'
                        command_buffer[5] == 8'h64) begin  // 'd'
                        // Drain circular buffer before starting firmware upload
                        state <= STATE_UPLOAD_DRAIN;
                    end else if (cmd_length == 1 && command_buffer[0] == 8'h72) begin  // 'r'
                        // Run: release CPU from reset (first read instruction at address 0)
                        state <= STATE_CPU_RUN_READ_INSTR;
                    end else if (cmd_length == 1 && command_buffer[0] == 8'h73) begin  // 's'
                        // Switch to app: release CPU and switch to app mode
                        // Send message then release CPU (reuse prompt state)
                        output_length <= 9'd28;  // "SWITCHING TO APP MODE\r\n> "
                        output_index <= 9'd0;
                        output_buffer[0] <= 8'h53;   // 'S'
                        output_buffer[1] <= 8'h57;   // 'W'
                        output_buffer[2] <= 8'h49;   // 'I'
                        output_buffer[3] <= 8'h54;   // 'T'
                        output_buffer[4] <= 8'h43;   // 'C'
                        output_buffer[5] <= 8'h48;   // 'H'
                        output_buffer[6] <= 8'h49;   // 'I'
                        output_buffer[7] <= 8'h4E;   // 'N'
                        output_buffer[8] <= 8'h47;   // 'G'
                        output_buffer[9] <= 8'h20;   // ' '
                        output_buffer[10] <= 8'h54;  // 'T'
                        output_buffer[11] <= 8'h4F;  // 'O'
                        output_buffer[12] <= 8'h20;  // ' '
                        output_buffer[13] <= 8'h41;  // 'A'
                        output_buffer[14] <= 8'h50;  // 'P'
                        output_buffer[15] <= 8'h50;  // 'P'
                        output_buffer[16] <= 8'h20;  // ' '
                        output_buffer[17] <= 8'h4D;  // 'M'
                        output_buffer[18] <= 8'h4F;  // 'O'
                        output_buffer[19] <= 8'h44;  // 'D'
                        output_buffer[20] <= 8'h45;  // 'E'
                        output_buffer[21] <= 8'h0D;  // '\r'
                        output_buffer[22] <= 8'h0A;  // '\n'
                        output_buffer[23] <= 8'h3E;  // '>'
                        output_buffer[24] <= 8'h20;  // ' '
                        output_buffer[25] <= 8'h00;
                        output_buffer[26] <= 8'h00;
                        output_buffer[27] <= 8'h00;
                        cpu_run <= 1'b1;       // Release CPU (pulse)
                        mode_restore <= 1'b0;  // Make sure not going to shell mode
                        state <= STATE_SEND_PREP;
                    end else if (cmd_length == 0) begin
                        state <= STATE_PROMPT;
                    end else begin
                        state <= STATE_ERROR_MSG;
                    end
                end
                
                // STATE_EXEC_CMD removed (SRAM test command removed to save logic cells)
                
                STATE_SEND_PREP: begin
                    // Prepare TX data one cycle before asserting valid
                    uart_tx_data <= output_buffer[output_index];
                    state <= STATE_SEND_OUTPUT;
                end

                STATE_SEND_OUTPUT: begin
                    if (!uart_tx_valid && uart_tx_ready) begin
                        if (output_index < output_length) begin
                            // Data already loaded in PREP state, just assert valid
                            // synthesis translate_off
                            if (output_index >= 15 && output_index <= 21) begin
                                $display("[SHELL] SEND[%d]: uart_tx_data=%02x", output_index, uart_tx_data);
                            end
                            // synthesis translate_on
                            uart_tx_valid <= 1'b1;
                            output_index <= output_index + 1;
                            state <= STATE_SEND_PREP;  // Prep next byte
                        end else begin
                            output_index <= 9'd0;
                            if (current_cmd == CMD_MEM) begin
                                state <= STATE_MEM_DISPLAY;
                            end else begin
                                state <= STATE_PROMPT;
                            end
                        end
                    end
                end
                
                // STATE_TEST_WRITE1, STATE_TEST_WRITE2, STATE_TEST_READ removed (SRAM test removed)
                
                STATE_WAIT_SUBPROCESS: begin
                    sram_proc_start <= 1'b0;  // Clear start signal
                    // synthesis translate_off
                    $display("[SHELL] WAIT_SUBPROCESS: sram_proc_done=%b sram_proc_done_seen=%b", sram_proc_done, sram_proc_done_seen);
                    // synthesis translate_on

                    // Use EDGE detection: respond only when sram_proc_done goes HIGH
                    if (sram_proc_done && !sram_proc_done_seen) begin
                        // synthesis translate_off
                        $display("[SHELL] WAIT_SUBPROCESS: sram_proc_done detected, current_cmd=0x%02x (CMD_CRC=0x%02x CMD_WRITE=0x%02x)", current_cmd, CMD_CRC, CMD_WRITE);
                        // synthesis translate_on
                        sram_proc_done_seen <= 1'b1;  // Mark that we've seen done

                        // Transition immediately in SAME cycle
                        if (current_cmd == CMD_CRC) begin
                            // synthesis translate_off
                            $display("[SHELL] Going to STATE_CRC_SEND_BYTE (0x%02x)", STATE_CRC_SEND_BYTE);
                            // synthesis translate_on
                            output_index <= 0;
                            uart_tx_valid <= 1'b0;
                            state <= STATE_CRC_SEND_BYTE;
                        end else if (current_cmd == CMD_WRITE) begin
                            // Send "OK\r\n"
                            output_buffer[0] <= 8'h4F;  // 'O'
                            output_buffer[1] <= 8'h4B;  // 'K'
                            output_buffer[2] <= 8'h0D;  // CR
                            output_buffer[3] <= 8'h0A;  // LF
                            output_length <= 4;
                            output_index <= 0;
                            state <= STATE_SEND_PREP;
                        end else begin
                            // synthesis translate_off
                            $display("[SHELL] Going to STATE_PROMPT");
                            // synthesis translate_on
                            state <= STATE_PROMPT;
                        end
                    end else if (fw_loader_done || fw_loader_error) begin
                        // Firmware upload completed (success or failure)
                        // Print newline and return to prompt
                        output_buffer[0] <= 8'h0D;
                        output_buffer[1] <= 8'h0A;
                        output_length <= 2;
                        output_index <= 0;
                        current_cmd <= CMD_NONE;
                        state <= STATE_SEND_PREP;
                    end
                    // synthesis translate_off
                    $display("[SHELL] End of STATE_WAIT_SUBPROCESS case, current state value=%b", state);
                    // synthesis translate_on
                end

                STATE_PROMPT_START: begin
                    // Prompt for start address: "Start> "
                    if (!uart_tx_valid && uart_tx_ready) begin
                        case (output_index)
                            0: begin uart_tx_data <= 8'h0D; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // CR
                            1: begin uart_tx_data <= 8'h0A; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // LF
                            2: begin uart_tx_data <= 8'h53; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // 'S'
                            3: begin uart_tx_data <= 8'h74; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // 't'
                            4: begin uart_tx_data <= 8'h61; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // 'a'
                            5: begin uart_tx_data <= 8'h72; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // 'r'
                            6: begin uart_tx_data <= 8'h74; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // 't'
                            7: begin uart_tx_data <= 8'h3E; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // '>'
                            8: begin uart_tx_data <= 8'h20; uart_tx_valid <= 1'b1; output_index <= 0; addr_input_length <= 0; parsed_addr <= 32'h0; state <= STATE_WAIT_START_ADDR; end  // ' '
                        endcase
                    end
                end

                STATE_WAIT_START_ADDR: begin
                    if (buffer_data_valid) begin
                        // Echo character
                        if (!uart_tx_valid && uart_tx_ready) begin
                            uart_tx_data <= current_rx_byte;
                            uart_tx_valid <= 1'b1;
                        end

                        if (current_rx_byte == 8'h0D || current_rx_byte == 8'h0A) begin
                            // End of input - save address
                            crc_start_addr <= parsed_addr;
                            state <= STATE_PROMPT_END;
                        end else begin
                            // Parse hex digit
                            if (addr_input_length < 10) begin  // Max 10 chars for "0x12345678"
                                // Skip "0x" prefix
                                if (!(addr_input_length == 0 && current_rx_byte == 8'h30) &&  // Skip '0'
                                    !(addr_input_length == 1 && (current_rx_byte == 8'h78 || current_rx_byte == 8'h58))) begin  // Skip 'x' or 'X'
                                    // Parse hex digit
                                    hex_nibble = ascii_to_hex(current_rx_byte);
                                    if (hex_nibble < 16) begin
                                        parsed_addr <= (parsed_addr << 4) | {28'h0, hex_nibble[3:0]};
                                    end
                                end
                                addr_input_length <= addr_input_length + 1;
                            end
                        end
                    end
                end

                STATE_PROMPT_END: begin
                    // Prompt for end address: "End> "
                    if (!uart_tx_valid && uart_tx_ready) begin
                        case (output_index)
                            0: begin uart_tx_data <= 8'h0D; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // CR
                            1: begin uart_tx_data <= 8'h0A; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // LF
                            2: begin uart_tx_data <= 8'h45; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // 'E'
                            3: begin uart_tx_data <= 8'h6E; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // 'n'
                            4: begin uart_tx_data <= 8'h64; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // 'd'
                            5: begin uart_tx_data <= 8'h3E; uart_tx_valid <= 1'b1; output_index <= output_index + 1; end  // '>'
                            6: begin uart_tx_data <= 8'h20; uart_tx_valid <= 1'b1; output_index <= 0; addr_input_length <= 0; parsed_addr <= 32'h0; state <= STATE_WAIT_END_ADDR; end  // ' '
                        endcase
                    end
                end

                STATE_WAIT_END_ADDR: begin
                    if (buffer_data_valid) begin
                        // Echo character
                        if (!uart_tx_valid && uart_tx_ready) begin
                            uart_tx_data <= current_rx_byte;
                            uart_tx_valid <= 1'b1;
                        end

                        if (current_rx_byte == 8'h0D || current_rx_byte == 8'h0A) begin
                            // End of input - save address and start CRC
                            crc_end_addr <= parsed_addr;
                            state <= STATE_CRC_EXEC;
                        end else begin
                            // Parse hex digit
                            if (addr_input_length < 10) begin
                                if (!(addr_input_length == 0 && current_rx_byte == 8'h30) &&
                                    !(addr_input_length == 1 && (current_rx_byte == 8'h78 || current_rx_byte == 8'h58))) begin
                                    hex_nibble = ascii_to_hex(current_rx_byte);
                                    if (hex_nibble < 16) begin
                                        parsed_addr <= (parsed_addr << 4) | {28'h0, hex_nibble[3:0]};
                                    end
                                end
                                addr_input_length <= addr_input_length + 1;
                            end
                        end
                    end
                end

                STATE_CRC_EXEC: begin
                    // Execute CRC calculation via sram_proc
                    sram_proc_addr <= crc_start_addr;
                    sram_proc_data <= crc_end_addr;
                    sram_proc_cmd <= CMD_CRC;
                    sram_proc_start <= 1'b1;
                    sram_proc_done_seen <= 1'b0;  // Reset done flag for new operation
                    state <= STATE_WAIT_SUBPROCESS;
                end

                STATE_WRITE_PARSE: begin
                    // Parse ONE nibble per clock cycle
                    if (parse_index < 8) begin
                        // Parse address nibble from positions 2-9
                        hex_nibble = ascii_to_hex(command_buffer[2 + parse_index]);
                        if (hex_nibble < 16) begin
                            parsed_addr <= (parsed_addr << 4) | {28'h0, hex_nibble[3:0]};
                        end
                        parse_index <= parse_index + 1;
                    end else if (parse_index < 16) begin
                        // Parse data nibble from positions 11-18 (position 10 is space)
                        hex_nibble = ascii_to_hex(command_buffer[11 + (parse_index - 8)]);
                        if (hex_nibble < 16) begin
                            write_data <= (write_data << 4) | {28'h0, hex_nibble[3:0]};
                        end
                        parse_index <= parse_index + 1;
                    end else begin
                        // Done parsing (parse_index == 16)
                        write_addr <= parsed_addr;
                        state <= STATE_WRITE_EXEC;
                    end
                end

                STATE_WRITE_EXEC: begin
                    // Execute write via sram_proc
                    sram_proc_addr <= write_addr;
                    sram_proc_data <= write_data;
                    sram_proc_cmd <= CMD_WRITE;
                    sram_proc_start <= 1'b1;
                    sram_proc_done_seen <= 1'b0;  // Reset done flag for new operation
                    state <= STATE_WAIT_SUBPROCESS;
                end

                STATE_MEM_READ: begin
                    // Simplified: read one word at a time and display it immediately
                    if (!sram_proc_busy) begin
                        sram_proc_addr <= mem_addr + {27'h0, mem_read_count, 2'b00};
                        sram_proc_cmd <= CMD_READ;
                        sram_proc_start <= 1'b1;
                        state <= STATE_MEM_WAIT;
                    end
                end

                STATE_MEM_WAIT: begin
                    sram_proc_start <= 1'b0;
                    if (sram_proc_done) begin
                        // Use sram_proc_result directly - no need to latch
                        // synthesis translate_off
                        $display("[SHELL] MEM_WAIT: read_count=%0d result=%08x", mem_read_count, sram_proc_result);
                        // synthesis translate_on

                        // Save to word register for this position
                        case (mem_read_count)
                            3'd0: begin
                                mem_word0 <= sram_proc_result;
                                // synthesis translate_off
                                $display("[SHELL] Assigning mem_word0 <= %08x", sram_proc_result);
                                // synthesis translate_on
                            end
                            3'd1: mem_word1 <= sram_proc_result;
                            3'd2: mem_word2 <= sram_proc_result;
                            3'd3: mem_word3 <= sram_proc_result;
                        endcase

                        if (mem_read_count < 3'd3) begin
                            mem_read_count <= mem_read_count + 1;
                            state <= STATE_MEM_READ;
                        end else begin
                            mem_read_count <= 3'd0;
                            state <= STATE_MEM_WAIT_FORMAT;
                        end
                    end
                end

                STATE_MEM_WAIT_FORMAT: begin
                    state <= STATE_MEM_WAIT_FORMAT2;
                end

                STATE_MEM_WAIT_FORMAT2: begin
                    // synthesis translate_off
                    $display("[SHELL] Entering DISPLAY: mem_word0=%08x mem_word1=%08x mem_word2=%08x mem_word3=%08x",
                             mem_word0, mem_word1, mem_word2, mem_word3);
                    // synthesis translate_on

                    // Use direct UART output instead of output_buffer to avoid synthesis issues
                    mem_byte_index <= 0;
                    uart_tx_valid <= 1'b0;
                    state <= STATE_MEM_SEND_BYTE;
                end

                STATE_MEM_WAIT_OUTPUT: begin
                    // Wait one cycle for output_buffer assignments to take effect
                    // synthesis translate_off
                    $display("[SHELL] WAIT_OUTPUT: buffer[16]=%02x buffer[17]=%02x buffer[19]=%02x buffer[20]=%02x",
                             output_buffer[16], output_buffer[17], output_buffer[19], output_buffer[20]);
                    // synthesis translate_on
                    output_index <= 0;
                    uart_tx_data <= output_buffer[0];  // Pre-load first byte
                    state <= STATE_SEND_OUTPUT;
                end

                STATE_MEM_SEND_BYTE: begin
                    // Send one byte at a time directly to UART TX
                    // synthesis translate_off
                    $display("[SHELL] SEND_BYTE: index=%d uart_tx_valid=%b uart_tx_ready=%b", mem_byte_index, uart_tx_valid, uart_tx_ready);
                    // synthesis translate_on

                    if (!uart_tx_valid && uart_tx_ready) begin
                        // UART ready for next byte
                        if (mem_byte_index > 58) begin
                            // Done with this line
                            state <= STATE_MEM_DISPLAY;
                        end else begin
                            case (mem_byte_index)
                                // Address (8 nibbles)
                                0: uart_tx_data <= (mem_addr[31:28] < 4'd10) ? (8'h30 + {4'd0, mem_addr[31:28]}) : (8'h41 + {4'd0, mem_addr[31:28]} - 8'd10);
                                1: uart_tx_data <= (mem_addr[27:24] < 4'd10) ? (8'h30 + {4'd0, mem_addr[27:24]}) : (8'h41 + {4'd0, mem_addr[27:24]} - 8'd10);
                                2: uart_tx_data <= (mem_addr[23:20] < 4'd10) ? (8'h30 + {4'd0, mem_addr[23:20]}) : (8'h41 + {4'd0, mem_addr[23:20]} - 8'd10);
                                3: uart_tx_data <= (mem_addr[19:16] < 4'd10) ? (8'h30 + {4'd0, mem_addr[19:16]}) : (8'h41 + {4'd0, mem_addr[19:16]} - 8'd10);
                                4: uart_tx_data <= (mem_addr[15:12] < 4'd10) ? (8'h30 + {4'd0, mem_addr[15:12]}) : (8'h41 + {4'd0, mem_addr[15:12]} - 8'd10);
                                5: uart_tx_data <= (mem_addr[11:8] < 4'd10) ? (8'h30 + {4'd0, mem_addr[11:8]}) : (8'h41 + {4'd0, mem_addr[11:8]} - 8'd10);
                                6: uart_tx_data <= (mem_addr[7:4] < 4'd10) ? (8'h30 + {4'd0, mem_addr[7:4]}) : (8'h41 + {4'd0, mem_addr[7:4]} - 8'd10);
                                7: uart_tx_data <= (mem_addr[3:0] < 4'd10) ? (8'h30 + {4'd0, mem_addr[3:0]}) : (8'h41 + {4'd0, mem_addr[3:0]} - 8'd10);
                                8: uart_tx_data <= 8'h20;  // Space
                                9: uart_tx_data <= 8'h20;  // Space

                                // Word 0 bytes 0-3
                                10: uart_tx_data <= (mem_word0[7:4] < 4'd10) ? (8'h30 + {4'd0, mem_word0[7:4]}) : (8'h41 + {4'd0, mem_word0[7:4]} - 8'd10);
                                11: uart_tx_data <= (mem_word0[3:0] < 4'd10) ? (8'h30 + {4'd0, mem_word0[3:0]}) : (8'h41 + {4'd0, mem_word0[3:0]} - 8'd10);
                                12: uart_tx_data <= 8'h20;
                                13: uart_tx_data <= (mem_word0[15:12] < 4'd10) ? (8'h30 + {4'd0, mem_word0[15:12]}) : (8'h41 + {4'd0, mem_word0[15:12]} - 8'd10);
                                14: uart_tx_data <= (mem_word0[11:8] < 4'd10) ? (8'h30 + {4'd0, mem_word0[11:8]}) : (8'h41 + {4'd0, mem_word0[11:8]} - 8'd10);
                                15: uart_tx_data <= 8'h20;
                                16: uart_tx_data <= (mem_word0[23:20] < 4'd10) ? (8'h30 + {4'd0, mem_word0[23:20]}) : (8'h41 + {4'd0, mem_word0[23:20]} - 8'd10);
                                17: uart_tx_data <= (mem_word0[19:16] < 4'd10) ? (8'h30 + {4'd0, mem_word0[19:16]}) : (8'h41 + {4'd0, mem_word0[19:16]} - 8'd10);
                                18: uart_tx_data <= 8'h20;
                                19: uart_tx_data <= (mem_word0[31:28] < 4'd10) ? (8'h30 + {4'd0, mem_word0[31:28]}) : (8'h41 + {4'd0, mem_word0[31:28]} - 8'd10);
                                20: uart_tx_data <= (mem_word0[27:24] < 4'd10) ? (8'h30 + {4'd0, mem_word0[27:24]}) : (8'h41 + {4'd0, mem_word0[27:24]} - 8'd10);
                                21: uart_tx_data <= 8'h20;

                                // Word 1 bytes 4-7
                                22: uart_tx_data <= (mem_word1[7:4] < 4'd10) ? (8'h30 + {4'd0, mem_word1[7:4]}) : (8'h41 + {4'd0, mem_word1[7:4]} - 8'd10);
                                23: uart_tx_data <= (mem_word1[3:0] < 4'd10) ? (8'h30 + {4'd0, mem_word1[3:0]}) : (8'h41 + {4'd0, mem_word1[3:0]} - 8'd10);
                                24: uart_tx_data <= 8'h20;
                                25: uart_tx_data <= (mem_word1[15:12] < 4'd10) ? (8'h30 + {4'd0, mem_word1[15:12]}) : (8'h41 + {4'd0, mem_word1[15:12]} - 8'd10);
                                26: uart_tx_data <= (mem_word1[11:8] < 4'd10) ? (8'h30 + {4'd0, mem_word1[11:8]}) : (8'h41 + {4'd0, mem_word1[11:8]} - 8'd10);
                                27: uart_tx_data <= 8'h20;
                                28: uart_tx_data <= (mem_word1[23:20] < 4'd10) ? (8'h30 + {4'd0, mem_word1[23:20]}) : (8'h41 + {4'd0, mem_word1[23:20]} - 8'd10);
                                29: uart_tx_data <= (mem_word1[19:16] < 4'd10) ? (8'h30 + {4'd0, mem_word1[19:16]}) : (8'h41 + {4'd0, mem_word1[19:16]} - 8'd10);
                                30: uart_tx_data <= 8'h20;
                                31: uart_tx_data <= (mem_word1[31:28] < 4'd10) ? (8'h30 + {4'd0, mem_word1[31:28]}) : (8'h41 + {4'd0, mem_word1[31:28]} - 8'd10);
                                32: uart_tx_data <= (mem_word1[27:24] < 4'd10) ? (8'h30 + {4'd0, mem_word1[27:24]}) : (8'h41 + {4'd0, mem_word1[27:24]} - 8'd10);
                                33: uart_tx_data <= 8'h20;

                                // Word 2 bytes 8-11
                                34: uart_tx_data <= (mem_word2[7:4] < 4'd10) ? (8'h30 + {4'd0, mem_word2[7:4]}) : (8'h41 + {4'd0, mem_word2[7:4]} - 8'd10);
                                35: uart_tx_data <= (mem_word2[3:0] < 4'd10) ? (8'h30 + {4'd0, mem_word2[3:0]}) : (8'h41 + {4'd0, mem_word2[3:0]} - 8'd10);
                                36: uart_tx_data <= 8'h20;
                                37: uart_tx_data <= (mem_word2[15:12] < 4'd10) ? (8'h30 + {4'd0, mem_word2[15:12]}) : (8'h41 + {4'd0, mem_word2[15:12]} - 8'd10);
                                38: uart_tx_data <= (mem_word2[11:8] < 4'd10) ? (8'h30 + {4'd0, mem_word2[11:8]}) : (8'h41 + {4'd0, mem_word2[11:8]} - 8'd10);
                                39: uart_tx_data <= 8'h20;
                                40: uart_tx_data <= (mem_word2[23:20] < 4'd10) ? (8'h30 + {4'd0, mem_word2[23:20]}) : (8'h41 + {4'd0, mem_word2[23:20]} - 8'd10);
                                41: uart_tx_data <= (mem_word2[19:16] < 4'd10) ? (8'h30 + {4'd0, mem_word2[19:16]}) : (8'h41 + {4'd0, mem_word2[19:16]} - 8'd10);
                                42: uart_tx_data <= 8'h20;
                                43: uart_tx_data <= (mem_word2[31:28] < 4'd10) ? (8'h30 + {4'd0, mem_word2[31:28]}) : (8'h41 + {4'd0, mem_word2[31:28]} - 8'd10);
                                44: uart_tx_data <= (mem_word2[27:24] < 4'd10) ? (8'h30 + {4'd0, mem_word2[27:24]}) : (8'h41 + {4'd0, mem_word2[27:24]} - 8'd10);
                                45: uart_tx_data <= 8'h20;

                                // Word 3 bytes 12-15
                                46: uart_tx_data <= (mem_word3[7:4] < 4'd10) ? (8'h30 + {4'd0, mem_word3[7:4]}) : (8'h41 + {4'd0, mem_word3[7:4]} - 8'd10);
                                47: uart_tx_data <= (mem_word3[3:0] < 4'd10) ? (8'h30 + {4'd0, mem_word3[3:0]}) : (8'h41 + {4'd0, mem_word3[3:0]} - 8'd10);
                                48: uart_tx_data <= 8'h20;
                                49: uart_tx_data <= (mem_word3[15:12] < 4'd10) ? (8'h30 + {4'd0, mem_word3[15:12]}) : (8'h41 + {4'd0, mem_word3[15:12]} - 8'd10);
                                50: uart_tx_data <= (mem_word3[11:8] < 4'd10) ? (8'h30 + {4'd0, mem_word3[11:8]}) : (8'h41 + {4'd0, mem_word3[11:8]} - 8'd10);
                                51: uart_tx_data <= 8'h20;
                                52: uart_tx_data <= (mem_word3[23:20] < 4'd10) ? (8'h30 + {4'd0, mem_word3[23:20]}) : (8'h41 + {4'd0, mem_word3[23:20]} - 8'd10);
                                53: uart_tx_data <= (mem_word3[19:16] < 4'd10) ? (8'h30 + {4'd0, mem_word3[19:16]}) : (8'h41 + {4'd0, mem_word3[19:16]} - 8'd10);
                                54: uart_tx_data <= 8'h20;
                                55: uart_tx_data <= (mem_word3[31:28] < 4'd10) ? (8'h30 + {4'd0, mem_word3[31:28]}) : (8'h41 + {4'd0, mem_word3[31:28]} - 8'd10);
                                56: uart_tx_data <= (mem_word3[27:24] < 4'd10) ? (8'h30 + {4'd0, mem_word3[27:24]}) : (8'h41 + {4'd0, mem_word3[27:24]} - 8'd10);

                                // CR LF
                                57: uart_tx_data <= 8'h0D;
                                58: uart_tx_data <= 8'h0A;
                                default: uart_tx_data <= 8'h00;
                            endcase
                            uart_tx_valid <= 1'b1;
                            mem_byte_index <= mem_byte_index + 1;
                        end
                    end
                end


                STATE_MEM_DISPLAY: begin
                    // After all output sent, check if we need more lines or wait for key
                    mem_line_count <= mem_line_count + 1;
                    mem_addr <= mem_addr + 32'd16;  // Next 16 bytes
                    mem_read_count <= 3'd0;  // Reset for next line read

                    if (mem_line_count >= 5'd31) begin
                        // Displayed 32 lines, wait for key
                        state <= STATE_MEM_WAIT_KEY;
                    end else begin
                        // Read next line
                        state <= STATE_MEM_READ;
                    end
                end

                STATE_MEM_WAIT_KEY: begin
                    // Wait for space or 'q'
                    if (buffer_data_valid) begin
                        if (current_rx_byte == 8'h20) begin  // Space
                            mem_line_count <= 5'd0;
                            mem_read_count <= 3'd0;
                            state <= STATE_MEM_READ;
                        end else if (current_rx_byte == 8'h71) begin  // 'q'
                            state <= STATE_PROMPT;
                        end
                    end
                end

                STATE_CRC_PARSE_START: begin
                    // Parse start address from "crc 00000000 00000100"
                    // Format: "crc <8-hex-start> <8-hex-end>"
                    // Parse 8 hex digits starting at position 4
                    if (parse_index < 8) begin
                        hex_nibble = ascii_to_hex(command_buffer[4 + parse_index]);
                        if (hex_nibble < 16) begin
                            parsed_addr <= (parsed_addr << 4) | {28'h0, hex_nibble[3:0]};
                        end
                        parse_index <= parse_index + 1;
                    end else begin
                        // Done parsing start address
                        crc_start_addr <= parsed_addr;
                        parsed_addr <= 32'h0;
                        parse_index <= 0;
                        state <= STATE_CRC_PARSE_END;
                    end
                end

                STATE_CRC_PARSE_END: begin
                    // Parse end address - 8 hex digits starting at position 13 (4 + 8 + 1 space)
                    // "crc 00000000 00000100"
                    //      ^        ^
                    //      4        13
                    if (parse_index < 8) begin
                        hex_nibble = ascii_to_hex(command_buffer[13 + parse_index]);
                        if (hex_nibble < 16) begin
                            parsed_addr <= (parsed_addr << 4) | {28'h0, hex_nibble[3:0]};
                        end
                        parse_index <= parse_index + 1;
                    end else begin
                        // Done parsing end address - execute CRC
                        crc_end_addr <= parsed_addr;
                        // synthesis translate_off
                        $display("[SHELL] CRC command: start=0x%08x end=0x%08x", crc_start_addr, parsed_addr);
                        // synthesis translate_on
                        state <= STATE_CRC_EXEC;
                    end
                end

                STATE_UPLOAD_DRAIN: begin
                    // Clear circular buffer before firmware upload
                    buffer_clear <= 1'b1;
                    fw_loader_start <= 1'b1;
                    state <= STATE_WAIT_SUBPROCESS;
                end

                STATE_CPU_RUN_READ_INSTR: begin
                    // Read first instruction from address 0x00000000
                    if (!sram_proc_busy) begin
                        sram_proc_addr <= 32'h00000000;
                        sram_proc_cmd <= CMD_READ;
                        sram_proc_start <= 1'b1;
                        state <= STATE_CPU_RUN_WAIT_INSTR;
                    end
                end

                STATE_CPU_RUN_WAIT_INSTR: begin
                    sram_proc_start <= 1'b0;
                    if (sram_proc_done) begin
                        // Store the first instruction
                        first_instruction <= sram_proc_result;
                        state <= STATE_CPU_RUN;
                    end
                end

                STATE_CPU_RUN: begin
                    // synthesis translate_off
                    $display("[SHELL] *** IN STATE_CPU_RUN case - STATE_CPU_RUN=0x%02x, actual state=0x%02x *** first_instruction=0x%08x", STATE_CPU_RUN, state, first_instruction);
                    // synthesis translate_on
                    // Release CPU from reset - pulse cpu_run
                    cpu_run <= 1'b1;

                    // Send confirmation message: "RELEASING CPU, FIRST INSTRUCTION: 0xXXXXXXXX\r\n"
                    output_buffer[0] <= "R";
                    output_buffer[1] <= "E";
                    output_buffer[2] <= "L";
                    output_buffer[3] <= "E";
                    output_buffer[4] <= "A";
                    output_buffer[5] <= "S";
                    output_buffer[6] <= "I";
                    output_buffer[7] <= "N";
                    output_buffer[8] <= "G";
                    output_buffer[9] <= " ";
                    output_buffer[10] <= "C";
                    output_buffer[11] <= "P";
                    output_buffer[12] <= "U";
                    output_buffer[13] <= ",";
                    output_buffer[14] <= " ";
                    output_buffer[15] <= "F";
                    output_buffer[16] <= "I";
                    output_buffer[17] <= "R";
                    output_buffer[18] <= "S";
                    output_buffer[19] <= "T";
                    output_buffer[20] <= " ";
                    output_buffer[21] <= "I";
                    output_buffer[22] <= "N";
                    output_buffer[23] <= "S";
                    output_buffer[24] <= "T";
                    output_buffer[25] <= "R";
                    output_buffer[26] <= "U";
                    output_buffer[27] <= "C";
                    output_buffer[28] <= "T";
                    output_buffer[29] <= "I";
                    output_buffer[30] <= "O";
                    output_buffer[31] <= "N";
                    output_buffer[32] <= ":";
                    output_buffer[33] <= " ";
                    output_buffer[34] <= "0";
                    output_buffer[35] <= "x";
                    // Format 32-bit instruction as hex (8 hex digits)
                    output_buffer[36] <= hex_to_ascii(first_instruction[31:28]);
                    output_buffer[37] <= hex_to_ascii(first_instruction[27:24]);
                    output_buffer[38] <= hex_to_ascii(first_instruction[23:20]);
                    output_buffer[39] <= hex_to_ascii(first_instruction[19:16]);
                    output_buffer[40] <= hex_to_ascii(first_instruction[15:12]);
                    output_buffer[41] <= hex_to_ascii(first_instruction[11:8]);
                    output_buffer[42] <= hex_to_ascii(first_instruction[7:4]);
                    output_buffer[43] <= hex_to_ascii(first_instruction[3:0]);
                    output_buffer[44] <= 8'h0D;  // '\r'
                    output_buffer[45] <= 8'h0A;  // '\n'
                    output_length <= 9'd46;
                    output_index <= 9'd0;
                    state <= STATE_SEND_PREP;  // Prep first byte
                end

                STATE_CRC_WAIT_FORMAT: begin
                    // Format CRC result into output_buffer: "\r\nCRC32: 0xXXXXXXXX\r\n"
                    // synthesis translate_off
                    $display("[SHELL] CRC_WAIT_FORMAT: Formatting result=0x%08x", sram_proc_result);
                    // synthesis translate_on

                    output_buffer[0] = 8'h0D;  // CR
                    output_buffer[1] = 8'h0A;  // LF
                    output_buffer[2] = 8'h43;  // 'C'
                    output_buffer[3] = 8'h52;  // 'R'
                    output_buffer[4] = 8'h43;  // 'C'
                    output_buffer[5] = 8'h33;  // '3'
                    output_buffer[6] = 8'h32;  // '2'
                    output_buffer[7] = 8'h3A;  // ':'
                    output_buffer[8] = 8'h20;  // ' '
                    output_buffer[9] = 8'h30;  // '0'
                    output_buffer[10] = 8'h78; // 'x'
                    output_buffer[11] = hex_to_ascii(sram_proc_result[31:28]);
                    output_buffer[12] = hex_to_ascii(sram_proc_result[27:24]);
                    output_buffer[13] = hex_to_ascii(sram_proc_result[23:20]);
                    output_buffer[14] = hex_to_ascii(sram_proc_result[19:16]);
                    output_buffer[15] = hex_to_ascii(sram_proc_result[15:12]);
                    output_buffer[16] = hex_to_ascii(sram_proc_result[11:8]);
                    output_buffer[17] = hex_to_ascii(sram_proc_result[7:4]);
                    output_buffer[18] = hex_to_ascii(sram_proc_result[3:0]);
                    output_buffer[19] = 8'h0D; // CR
                    output_buffer[20] = 8'h0A; // LF

                    output_length <= 9'd21;
                    output_index <= 0;
                    sram_proc_done_seen <= 1'b0;  // Clear flag for next operation
                    state <= STATE_SEND_PREP;
                end

                STATE_ERROR_MSG: begin
                    output_buffer[0] <= 8'h45;
                    output_buffer[1] <= 8'h52;
                    output_buffer[2] <= 8'h52;
                    output_buffer[3] <= 8'h0D;
                    output_buffer[4] <= 8'h0A;
                    output_length <= 5;
                    output_index <= 0;
                    state <= STATE_SEND_PREP;
                end

                STATE_CRC_SEND_BYTE: begin
                    // Send CRC result: "\r\nCRC32: 0xXXXXXXXX\r\n"
                    // synthesis translate_off
                    $display("[SHELL] *** IN STATE_CRC_SEND_BYTE (0x%02x) ***: output_index=%d uart_tx_valid=%b uart_tx_ready=%b sram_proc_result=0x%08x", STATE_CRC_SEND_BYTE, output_index, uart_tx_valid, uart_tx_ready, sram_proc_result);
                    // synthesis translate_on
                    if (output_index == 0) begin
                        sram_proc_done_seen <= 1'b0;  // Clear flag on first cycle only
                    end
                    if (!uart_tx_valid && uart_tx_ready) begin
                        if (output_index >= 21) begin
                            current_cmd <= CMD_NONE;
                            output_index <= 0;
                            uart_tx_valid <= 1'b0;
                            state <= STATE_PROMPT;
                        end else begin
                            case (output_index)
                                0: uart_tx_data <= 8'h0D;  // CR
                                1: uart_tx_data <= 8'h0A;  // LF
                                2: uart_tx_data <= 8'h43;  // 'C'
                                3: uart_tx_data <= 8'h52;  // 'R'
                                4: uart_tx_data <= 8'h43;  // 'C'
                                5: uart_tx_data <= 8'h33;  // '3'
                                6: uart_tx_data <= 8'h32;  // '2'
                                7: uart_tx_data <= 8'h3A;  // ':'
                                8: uart_tx_data <= 8'h20;  // ' '
                                9: uart_tx_data <= 8'h30;  // '0'
                                10: uart_tx_data <= 8'h78; // 'x'
                                11: uart_tx_data <= hex_to_ascii(sram_proc_result[31:28]);
                                12: uart_tx_data <= hex_to_ascii(sram_proc_result[27:24]);
                                13: uart_tx_data <= hex_to_ascii(sram_proc_result[23:20]);
                                14: uart_tx_data <= hex_to_ascii(sram_proc_result[19:16]);
                                15: uart_tx_data <= hex_to_ascii(sram_proc_result[15:12]);
                                16: uart_tx_data <= hex_to_ascii(sram_proc_result[11:8]);
                                17: uart_tx_data <= hex_to_ascii(sram_proc_result[7:4]);
                                18: uart_tx_data <= hex_to_ascii(sram_proc_result[3:0]);
                                19: uart_tx_data <= 8'h0D; // CR
                                20: uart_tx_data <= 8'h0A; // LF
                                default: uart_tx_data <= 8'h00;
                            endcase
                            uart_tx_valid <= 1'b1;
                            output_index <= output_index + 1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
