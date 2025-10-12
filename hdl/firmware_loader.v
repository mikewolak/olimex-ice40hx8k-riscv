//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// firmware_loader.v - Firmware Upload Protocol Handler
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module firmware_loader (
    input wire clk,
    input wire resetn,
    
    // Shell control
    input wire start,
    output reg busy,
    output reg done,
    output reg error,
    output reg [7:0] nak_reason,
    
    // Circular Buffer Interface
    input wire [7:0] buffer_rd_data,
    output reg buffer_rd_en,
    input wire buffer_empty,
    
    // UART TX Interface
    output reg [7:0] uart_tx_data,
    output reg uart_tx_valid,
    input wire uart_tx_ready,
    
    // 16-bit SRAM Interface (matches sram_proc)
    output reg sram_valid,
    input wire sram_ready,
    output reg sram_we,
    output reg [18:0] sram_addr_16,
    output reg [15:0] sram_wdata_16,
    input wire [15:0] sram_rdata_16,
    
    // CPU Control
    output reg cpu_reset
);

    // NAK reason codes
    localparam NAK_SIZE_TOO_LARGE = 8'h01;
    localparam NAK_SIZE_ZERO = 8'h02;
    localparam NAK_CRC_MISMATCH = 8'h03;
    localparam NAK_SRAM_ERROR = 8'h04;
    localparam NAK_TIMEOUT = 8'hFF;
    
    localparam MAX_SRAM_SIZE = 32'h00080000;
    localparam TIMEOUT_CYCLES = 32'd50_000_000;
    
    // States
    localparam STATE_IDLE = 4'h0;
    localparam STATE_WAIT_READY = 4'h1;
    localparam STATE_RECV_SIZE = 4'h2;
    localparam STATE_CHECK_SIZE = 4'h3;
    localparam STATE_RECV_DATA = 4'h4;
    localparam STATE_PREPARE_WRITE = 4'h5;
    localparam STATE_STORE_WORD = 4'h6;
    localparam STATE_RECV_CRC_CMD = 4'h7;
    localparam STATE_RECV_CRC = 4'h8;
    localparam STATE_VERIFY_CRC = 4'h9;
    localparam STATE_SEND_RESP = 4'hA;
    localparam STATE_SEND_CRC = 4'hB;
    localparam STATE_WAIT_TX_DONE = 4'hC;
    localparam STATE_COMPLETE = 4'hD;
    localparam STATE_ERROR = 4'hE;
    
    reg [3:0] state = STATE_IDLE;
    reg [3:0] next_state = STATE_IDLE;
    reg [31:0] packet_size = 32'h0;
    reg [31:0] bytes_received = 32'h0;
    reg [31:0] word_addr = 32'h0;
    reg [15:0] data_word = 16'h0;
    reg byte_in_word = 1'b0;  // 0 = need low byte, 1 = have low byte
    
    // CRC calculation (matching quick_test pattern)
    reg [31:0] crc_din;  // Combinational word to CRC
    reg [23:0] crc_current_word;  // First 3 bytes of current word
    reg [1:0] crc_word_pos;  // 0-3 for position in word
    reg crc_calc_pulse;
    wire [31:0] crc_result;

    reg [1:0] size_byte_count;
    reg [1:0] crc_rx_byte_count;
    reg [1:0] crc_tx_byte_count;
    reg [31:0] expected_crc;
    reg [6:0] chunk_byte_count;  // 7 bits to hold 0-64
    reg [7:0] response_char;
    reg send_response;
    reg [31:0] timeout_counter;
    reg [4:0] ack_counter;  // Rotating ACK counter (0-25 for A-Z)

    reg buffer_read_state;
    reg buffer_data_valid;
    reg [7:0] current_rx_byte;
    
    wire timeout_active = (state == STATE_WAIT_READY) ||
                          (state == STATE_RECV_SIZE) ||
                          (state == STATE_RECV_DATA) ||
                          (state == STATE_RECV_CRC_CMD) ||
                          (state == STATE_RECV_CRC);
    
    // CRC32 module instantiation (matching quick_test)
    crc32_gen crc32_inst (
        .clk(clk),
        .clr_crc(state == STATE_IDLE || state == STATE_WAIT_READY),
        .din(crc_din),  // Use combinational word
        .calc(crc_calc_pulse),
        .crc(crc_result)
    );
    
    always @(posedge clk) begin
        if (!resetn || !busy || !timeout_active) begin
            timeout_counter <= 32'd0;
        end else if (buffer_data_valid) begin
            timeout_counter <= 32'd0;
        end else if (timeout_counter < TIMEOUT_CYCLES) begin
            timeout_counter <= timeout_counter + 1;
        end
    end
    
    wire timeout_expired = (timeout_counter >= TIMEOUT_CYCLES);
    
    // States that need buffer reading
    wire buffer_read_active = (state == STATE_WAIT_READY) ||
                               (state == STATE_RECV_SIZE) ||
                               (state == STATE_RECV_DATA) ||
                               (state == STATE_RECV_CRC_CMD) ||
                               (state == STATE_RECV_CRC);

    // Buffer reader
    always @(posedge clk) begin
        if (!resetn) begin
            buffer_rd_en <= 1'b0;
            buffer_read_state <= 1'b0;
            buffer_data_valid <= 1'b0;
            current_rx_byte <= 8'h00;
        end else begin
            buffer_rd_en <= 1'b0;
            buffer_data_valid <= 1'b0;

            if (busy) begin
                case (buffer_read_state)
                    1'b0: begin
                        // Only START a new read if in a reading state
                        if (buffer_read_active && !buffer_empty) begin
                            buffer_rd_en <= 1'b1;
                            buffer_read_state <= 1'b1;
                        end
                    end
                    1'b1: begin
                        // Always COMPLETE a read in progress, even if buffer_read_active goes FALSE
                        current_rx_byte <= buffer_rd_data;
                        buffer_data_valid <= 1'b1;
                        buffer_read_state <= 1'b0;
                        // synthesis translate_off
                        $display("[BUF] Read byte: 0x%02x", buffer_rd_data);
                        // synthesis translate_on
                    end
                endcase
            end
        end
    end
    
    // Main state machine
    always @(posedge clk) begin
        if (!resetn) begin
            state <= STATE_IDLE;
            next_state <= STATE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            nak_reason <= 8'h00;
            cpu_reset <= 1'b1;
            uart_tx_valid <= 1'b0;
            sram_valid <= 1'b0;
            sram_we <= 1'b0;
            sram_addr_16 <= 19'h0;
            sram_wdata_16 <= 16'h0;
            packet_size <= 32'h0;
            bytes_received <= 32'h0;
            word_addr <= 32'h0;
            chunk_byte_count <= 7'd0;
            send_response <= 1'b0;
            byte_in_word <= 1'b0;
            data_word <= 16'h0;
            crc_word_pos <= 2'h0;
            crc_calc_pulse <= 1'b0;
            crc_current_word <= 24'h0;
            crc_din <= 32'h0;
            ack_counter <= 5'd0;
        end else begin
            done <= 1'b0;
            crc_calc_pulse <= 1'b0;  // Pulse signal, clear each cycle
            
            if (uart_tx_valid && uart_tx_ready) begin
                uart_tx_valid <= 1'b0;
            end
            
            if (!uart_tx_valid && uart_tx_ready && send_response) begin
                uart_tx_data <= response_char;
                uart_tx_valid <= 1'b1;
                send_response <= 1'b0;
            end
            
            if (timeout_expired && busy && state != STATE_COMPLETE && state != STATE_SEND_RESP && state != STATE_ERROR) begin
                response_char <= 8'h4E;
                send_response <= 1'b1;
                nak_reason <= NAK_TIMEOUT;
                next_state <= STATE_ERROR;
                state <= STATE_SEND_RESP;
            end
            
            case (state)
                STATE_IDLE: begin
                    busy <= 1'b0;
                    done <= 1'b0;
                    error <= 1'b0;
                    cpu_reset <= 1'b1;
                    sram_valid <= 1'b0;
                    sram_we <= 1'b0;
                    ack_counter <= 5'd0;  // Reset ACK counter to start at 'A'

                    if (start) begin
                        nak_reason <= 8'h00;
                        busy <= 1'b1;
                        packet_size <= 32'h0;
                        bytes_received <= 32'h0;
                        word_addr <= 32'h0;
                        byte_in_word <= 1'b0;
                        crc_word_pos <= 2'h0;
                        state <= STATE_WAIT_READY;
                    end
                end
                
                STATE_WAIT_READY: begin
                    if (buffer_data_valid && current_rx_byte == 8'h52) begin
                        response_char <= 8'h41 + ack_counter;  // Rotating ACK
                        ack_counter <= (ack_counter == 5'd25) ? 5'd0 : ack_counter + 1;
                        send_response <= 1'b1;
                        size_byte_count <= 2'h0;
                        state <= STATE_RECV_SIZE;
                    end
                end
                
                STATE_RECV_SIZE: begin
                    if (buffer_data_valid) begin
                        case (size_byte_count)
                            2'h0: packet_size[7:0] <= current_rx_byte;
                            2'h1: packet_size[15:8] <= current_rx_byte;
                            2'h2: packet_size[23:16] <= current_rx_byte;
                            2'h3: begin
                                packet_size[31:24] <= current_rx_byte;
                                state <= STATE_CHECK_SIZE;
                            end
                        endcase
                        if (size_byte_count < 2'h3) begin
                            size_byte_count <= size_byte_count + 1;
                        end
                    end
                end
                
                STATE_CHECK_SIZE: begin
                    if (packet_size > MAX_SRAM_SIZE) begin
                        response_char <= 8'h4E;
                        send_response <= 1'b1;
                        nak_reason <= NAK_SIZE_TOO_LARGE;
                        state <= STATE_ERROR;
                    end else if (packet_size == 0) begin
                        response_char <= 8'h4E;
                        send_response <= 1'b1;
                        nak_reason <= NAK_SIZE_ZERO;
                        state <= STATE_ERROR;
                    end else begin
                        response_char <= 8'h41 + ack_counter;  // Rotating ACK
                        ack_counter <= (ack_counter == 5'd25) ? 5'd0 : ack_counter + 1;
                        send_response <= 1'b1;
                        chunk_byte_count <= 7'd0;
                        state <= STATE_RECV_DATA;
                    end
                end
                
                STATE_RECV_DATA: begin
                    if (buffer_data_valid) begin
                        // Build 32-bit CRC word (matching quick_test pattern)
                        case (crc_word_pos)
                            2'd0: begin
                                crc_current_word[7:0] <= current_rx_byte;
                                // synthesis translate_off
                                $display("[FW] CRC byte 0: 0x%02x, pos 0->1", current_rx_byte);
                                // synthesis translate_on
                                crc_word_pos <= 2'd1;
                            end
                            2'd1: begin
                                crc_current_word[15:8] <= current_rx_byte;
                                // synthesis translate_off
                                $display("[FW] CRC byte 1: 0x%02x, pos 1->2", current_rx_byte);
                                // synthesis translate_on
                                crc_word_pos <= 2'd2;
                            end
                            2'd2: begin
                                crc_current_word[23:16] <= current_rx_byte;
                                // synthesis translate_off
                                $display("[FW] CRC byte 2: 0x%02x, pos 2->3", current_rx_byte);
                                // synthesis translate_on
                                crc_word_pos <= 2'd3;
                            end
                            2'd3: begin
                                // Send complete 32-bit word to CRC (like quick_test!)
                                crc_din <= {current_rx_byte, crc_current_word[23:0]};
                                crc_calc_pulse <= 1'b1;
                                // synthesis translate_off
                                $display("[FW] CRC word: 0x%08x (bytes: 0x%02x 0x%02x 0x%02x 0x%02x)",
                                         {current_rx_byte, crc_current_word[23:0]},
                                         crc_current_word[7:0], crc_current_word[15:8], crc_current_word[23:16], current_rx_byte);
                                // synthesis translate_on
                                crc_word_pos <= 2'd0;
                            end
                        endcase

                        // Collect byte for SRAM write
                        if (!byte_in_word) begin
                            data_word[7:0] <= current_rx_byte;
                            byte_in_word <= 1'b1;
                        end else begin
                            data_word[15:8] <= current_rx_byte;
                            byte_in_word <= 1'b0;
                        end

                        bytes_received <= bytes_received + 1;
                        chunk_byte_count <= chunk_byte_count + 1;

                        // Check if we need to write to SRAM (write when we just completed a word)
                        // byte_in_word == 1 means we're on the 2nd byte, which completes a word
                        // bytes_received >= 1 means we have byte 0, and are currently receiving byte 1
                        if ((byte_in_word == 1'b1 && bytes_received >= 1) || bytes_received >= packet_size) begin
                            // Pad last byte if odd packet size
                            if (byte_in_word == 0 && bytes_received >= packet_size) begin
                                data_word[15:8] <= 8'h00;
                            end
                            state <= STATE_PREPARE_WRITE;
                        end

                        // Handle final partial CRC word at end of packet
                        if (bytes_received >= packet_size && crc_word_pos != 2'h0) begin
                            // Pad remaining bytes with zeros and calculate
                            case (crc_word_pos)
                                2'd1: crc_din <= {24'h000000, crc_current_word[7:0]};
                                2'd2: crc_din <= {16'h0000, crc_current_word[15:0]};
                                2'd3: crc_din <= {8'h00, crc_current_word[23:0]};
                            endcase
                            crc_calc_pulse <= 1'b1;
                        end
                    end
                end

                STATE_PREPARE_WRITE: begin
                    // Wait one cycle for data_word to settle after non-blocking assignment
                    state <= STATE_STORE_WORD;
                end

                STATE_STORE_WORD: begin
                    if (!sram_valid) begin
                        sram_addr_16 <= word_addr[18:0];
                        sram_wdata_16 <= data_word;
                        sram_we <= 1'b1;
                        sram_valid <= 1'b1;
                        // synthesis translate_off
                        $display("[FW] STORE_WORD: Writing to sram_addr_16=0x%05x (word_addr=0x%08x) data=0x%04x", word_addr[18:0], word_addr, data_word);
                        // synthesis translate_on
                    end else if (sram_ready) begin
                        sram_valid <= 1'b0;
                        sram_we <= 1'b0;
                        word_addr <= word_addr + 1;

                        if (bytes_received >= packet_size) begin
                            // synthesis translate_off
                            $display("[FW] STORE_WORD: bytes_received=%d >= packet_size=%d, sending ACK, going to CRC_CMD", bytes_received, packet_size);
                            // synthesis translate_on
                            response_char <= 8'h41 + ack_counter;  // Rotating ACK
                            ack_counter <= (ack_counter == 5'd25) ? 5'd0 : ack_counter + 1;
                            send_response <= 1'b1;
                            next_state <= STATE_RECV_CRC_CMD;
                            state <= STATE_SEND_RESP;
                        end else if (chunk_byte_count >= 7'd64) begin
                            // synthesis translate_off
                            $display("[FW] STORE_WORD: chunk_byte_count=%d >= 64, sending chunk ACK", chunk_byte_count);
                            // synthesis translate_on
                            response_char <= 8'h41 + ack_counter;  // Rotating ACK
                            ack_counter <= (ack_counter == 5'd25) ? 5'd0 : ack_counter + 1;
                            send_response <= 1'b1;
                            chunk_byte_count <= 7'd0;
                            next_state <= STATE_RECV_DATA;
                            state <= STATE_SEND_RESP;
                        end else begin
                            // synthesis translate_off
                            $display("[FW] STORE_WORD: bytes=%d, chunk=%d, continuing to RECV_DATA", bytes_received, chunk_byte_count);
                            // synthesis translate_on
                            state <= STATE_RECV_DATA;
                        end
                    end
                end
                
                STATE_RECV_CRC_CMD: begin
                    if (buffer_data_valid && current_rx_byte == 8'h43) begin
                        crc_rx_byte_count <= 2'h0;
                        state <= STATE_RECV_CRC;
                    end
                end
                
                STATE_RECV_CRC: begin
                    if (buffer_data_valid) begin
                        case (crc_rx_byte_count)
                            2'h0: expected_crc[7:0] <= current_rx_byte;
                            2'h1: expected_crc[15:8] <= current_rx_byte;
                            2'h2: expected_crc[23:16] <= current_rx_byte;
                            2'h3: begin
                                expected_crc[31:24] <= current_rx_byte;
                                state <= STATE_VERIFY_CRC;
                            end
                        endcase
                        if (crc_rx_byte_count < 2'h3) begin
                            crc_rx_byte_count <= crc_rx_byte_count + 1;
                        end
                    end
                end
                
                STATE_VERIFY_CRC: begin
                    // synthesis translate_off
                    $display("[FW] CRC Verify: calculated=0x%08x, expected=0x%08x", crc_result, expected_crc);
                    // synthesis translate_on
                    if (crc_result == expected_crc) begin
                        // synthesis translate_off
                        $display("[FW] CRC Match! Sending ACK");
                        // synthesis translate_on
                        response_char <= 8'h41 + ack_counter;  // Rotating ACK
                        ack_counter <= (ack_counter == 5'd25) ? 5'd0 : ack_counter + 1;
                        send_response <= 1'b1;
                        next_state <= STATE_COMPLETE;
                    end else begin
                        // synthesis translate_off
                        $display("[FW] CRC Mismatch! Sending NAK");
                        // synthesis translate_on
                        response_char <= 8'h4E;  // NAK
                        send_response <= 1'b1;
                        nak_reason <= NAK_CRC_MISMATCH;
                        next_state <= STATE_ERROR;
                    end
                    crc_tx_byte_count <= 2'h0;
                    state <= STATE_SEND_RESP;
                end
                
                STATE_SEND_RESP: begin
                    if (!send_response && !uart_tx_valid) begin
                        // After sending ACK/NAK from CRC verification, send the CRC bytes
                        if (next_state == STATE_COMPLETE || next_state == STATE_ERROR) begin
                            state <= STATE_SEND_CRC;
                        end else begin
                            state <= next_state;
                        end
                    end
                end

                STATE_SEND_CRC: begin
                    if (!uart_tx_valid && uart_tx_ready) begin
                        if (crc_tx_byte_count < 2'h3) begin
                            // Send bytes 0-2
                            case (crc_tx_byte_count)
                                2'h0: uart_tx_data <= crc_result[7:0];
                                2'h1: uart_tx_data <= crc_result[15:8];
                                2'h2: uart_tx_data <= crc_result[23:16];
                            endcase
                            uart_tx_valid <= 1'b1;
                            crc_tx_byte_count <= crc_tx_byte_count + 1;
                        end else begin
                            // Send final byte (byte 3)
                            uart_tx_data <= crc_result[31:24];
                            uart_tx_valid <= 1'b1;
                            crc_tx_byte_count <= 2'h0;  // Reset for next upload
                            state <= STATE_WAIT_TX_DONE;  // Wait for TX to complete
                        end
                    end
                end

                STATE_WAIT_TX_DONE: begin
                    // Wait for UART to finish sending the last byte
                    if (!uart_tx_valid) begin
                        state <= next_state;  // Now safe to go to COMPLETE or ERROR
                    end
                end
                
                STATE_COMPLETE: begin
                    cpu_reset <= 1'b0;
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= STATE_IDLE;
                end
                
                STATE_ERROR: begin
                    error <= 1'b1;
                    busy <= 1'b0;
                    cpu_reset <= 1'b1;
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
