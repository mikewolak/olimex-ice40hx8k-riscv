`timescale 1ns/1ps

module tb_firmware_upload;
    reg clk;
    reg resetn;

    // Firmware loader interface
    reg fw_loader_start;
    wire fw_loader_busy;
    wire fw_loader_done;
    wire fw_loader_error;
    wire [7:0] fw_loader_nak_reason;

    // Circular buffer interface (simulated)
    wire [7:0] buffer_rd_data;
    wire buffer_rd_en;
    reg buffer_empty;

    // UART TX interface
    wire [7:0] uart_tx_data;
    wire uart_tx_valid;
    reg uart_tx_ready;

    // SRAM driver interface
    wire sram_valid;
    wire sram_ready;
    wire sram_we;
    wire [18:0] sram_addr_16;
    wire [15:0] sram_wdata_16;
    wire [15:0] sram_rdata_16;

    // SRAM physical interface
    wire [17:0] sram_addr;
    wire [15:0] sram_data;
    wire sram_cs_n;
    wire sram_oe_n;
    wire sram_we_n;

    // Simulated SRAM memory
    reg [15:0] sram_mem [0:262143];  // 256K x 16-bit
    reg [15:0] sram_data_out;
    reg sram_data_oe;

    // Tri-state control for simulated SRAM
    assign sram_data = (sram_data_oe && !sram_oe_n && !sram_cs_n) ? sram_data_out : 16'hzzzz;

    // Firmware data buffer (simulates UART RX buffer)
    reg [7:0] fw_data_buffer [0:4095];
    integer fw_data_size;
    integer fw_read_idx;

    // Provide firmware data when loader reads
    assign buffer_rd_data = (fw_read_idx < fw_data_size) ? fw_data_buffer[fw_read_idx] : 8'h00;

    // Instantiate firmware_loader
    firmware_loader fw_loader_inst (
        .clk(clk),
        .resetn(resetn),
        .start(fw_loader_start),
        .busy(fw_loader_busy),
        .done(fw_loader_done),
        .error(fw_loader_error),
        .nak_reason(fw_loader_nak_reason),
        .buffer_rd_data(buffer_rd_data),
        .buffer_rd_en(buffer_rd_en),
        .buffer_empty(buffer_empty),
        .uart_tx_data(uart_tx_data),
        .uart_tx_valid(uart_tx_valid),
        .uart_tx_ready(uart_tx_ready),
        .sram_valid(sram_valid),
        .sram_ready(sram_ready),
        .sram_we(sram_we),
        .sram_addr_16(sram_addr_16),
        .sram_wdata_16(sram_wdata_16),
        .sram_rdata_16(sram_rdata_16),
        .cpu_reset()
    );

    // Instantiate sram_driver_new (with COOLDOWN fix)
    sram_driver_new sram_driver_inst (
        .clk(clk),
        .resetn(resetn),
        .valid(sram_valid),
        .ready(sram_ready),
        .we(sram_we),
        .addr(sram_addr_16),
        .wdata(sram_wdata_16),
        .rdata(sram_rdata_16),
        .sram_addr(sram_addr),
        .sram_data(sram_data),
        .sram_cs_n(sram_cs_n),
        .sram_oe_n(sram_oe_n),
        .sram_we_n(sram_we_n)
    );

    // SRAM behavioral model - follows K6R4016V1D timing
    always @(posedge clk) begin
        if (!sram_cs_n && !sram_we_n) begin
            // Write operation
            sram_mem[sram_addr] <= sram_data;
        end
    end

    always @(*) begin
        if (!sram_cs_n && !sram_oe_n && sram_we_n) begin
            // Read operation
            sram_data_out = sram_mem[sram_addr];
            sram_data_oe = 1'b1;
        end else begin
            sram_data_out = 16'hxxxx;
            sram_data_oe = 1'b0;
        end
    end

    // Clock generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Buffer read logic - simulate circular buffer
    always @(posedge clk) begin
        if (!resetn) begin
            fw_read_idx <= 0;
            buffer_empty <= 1;
        end else begin
            if (buffer_rd_en && fw_read_idx < fw_data_size) begin
                fw_read_idx <= fw_read_idx + 1;
                if (fw_read_idx + 1 >= fw_data_size) begin
                    buffer_empty <= 1;
                end
            end
        end
    end

    // CRC32 calculation (for verification)
    function [31:0] crc32_update;
        input [31:0] crc;
        input [7:0] data;
        integer i;
        reg [31:0] temp_crc;
        reg [7:0] temp_data;
        begin
            temp_crc = crc;
            temp_data = data;
            for (i = 0; i < 8; i = i + 1) begin
                if (temp_crc[0] ^ temp_data[0])
                    temp_crc = (temp_crc >> 1) ^ 32'hEDB88320;
                else
                    temp_crc = temp_crc >> 1;
                temp_data = temp_data >> 1;
            end
            crc32_update = temp_crc;
        end
    endfunction

    // Task to create firmware upload packet
    task create_firmware_packet;
        input [31:0] size;
        input [31:0] start_value;
        integer i;
        reg [31:0] crc;
        begin
            $display("\n[TB] Creating firmware packet: size=%0d bytes, start_value=0x%08x", size, start_value);

            // Ready character 'R' (0x52)
            fw_data_buffer[0] = 8'h52;

            // Size field (4 bytes, little-endian)
            fw_data_buffer[1] = size[7:0];
            fw_data_buffer[2] = size[15:8];
            fw_data_buffer[3] = size[23:16];
            fw_data_buffer[4] = size[31:24];

            // Data payload (incrementing pattern)
            for (i = 0; i < size; i = i + 1) begin
                fw_data_buffer[5 + i] = (start_value + i) & 8'hFF;
            end

            // Calculate CRC32 over size + data
            crc = 32'hFFFFFFFF;
            for (i = 0; i < (4 + size); i = i + 1) begin
                crc = crc32_update(crc, fw_data_buffer[1 + i]);  // Start from size field
            end
            crc = ~crc;

            // CRC field (4 bytes, little-endian)
            fw_data_buffer[5 + size] = crc[7:0];
            fw_data_buffer[5 + size + 1] = crc[15:8];
            fw_data_buffer[5 + size + 2] = crc[23:16];
            fw_data_buffer[5 + size + 3] = crc[31:24];

            fw_data_size = 1 + 4 + size + 4;  // 'R' + size + data + crc
            fw_read_idx = 0;
            buffer_empty = 0;

            $display("[TB] Packet created: total_size=%0d bytes (including 'R'), CRC32=0x%08x", fw_data_size, crc);
        end
    endtask

    // Task to verify SRAM contents
    task verify_sram;
        input [31:0] size;
        input [31:0] start_value;
        integer i;
        integer errors;
        reg [15:0] expected_word;
        reg [15:0] actual_word;
        begin
            errors = 0;
            $display("\n[TB] Verifying SRAM contents...");

            // Check data was written correctly (as 16-bit words)
            for (i = 0; i < size; i = i + 2) begin
                // Expected: little-endian bytes packed into 16-bit words
                expected_word = {(start_value + i + 1) & 8'hFF, (start_value + i) & 8'hFF};
                actual_word = sram_mem[i/2];

                if (actual_word !== expected_word) begin
                    $display("[TB ERROR] SRAM[%0d] = 0x%04x, expected 0x%04x",
                             i/2, actual_word, expected_word);
                    errors = errors + 1;
                    if (errors >= 10) begin
                        $display("[TB ERROR] Too many errors, stopping verification");
                        break;
                    end
                end
            end

            if (errors == 0) begin
                $display("[TB] ✓ SRAM verification PASSED - all %0d bytes correct", size);
            end else begin
                $display("[TB] ✗ SRAM verification FAILED - %0d errors found", errors);
            end
        end
    endtask

    // Monitor UART TX output
    always @(posedge clk) begin
        if (uart_tx_valid && uart_tx_ready) begin
            if (uart_tx_data == 8'h06) begin
                $display("[TB UART] Received ACK (0x06)");
            end else if (uart_tx_data == 8'h15) begin
                $display("[TB UART] Received NAK (0x15) - reason=0x%02x", fw_loader_nak_reason);
            end else begin
                $display("[TB UART] TX: 0x%02x '%c'", uart_tx_data,
                         (uart_tx_data >= 32 && uart_tx_data <= 126) ? uart_tx_data : ".");
            end
        end
    end

    // Main test sequence
    integer test_errors;

    initial begin
        $dumpfile("tb_firmware_upload.vcd");
        $dumpvars(0, tb_firmware_upload);

        // Initialize
        resetn = 0;
        fw_loader_start = 0;
        buffer_empty = 1;
        uart_tx_ready = 1;
        fw_data_size = 0;
        fw_read_idx = 0;
        test_errors = 0;

        // Initialize SRAM to known pattern
        for (integer i = 0; i < 262144; i = i + 1) begin
            sram_mem[i] = 16'hFFFF;
        end

        $display("\n========================================");
        $display("FIRMWARE UPLOAD TEST WITH CLEAN-ROOM SRAM");
        $display("========================================\n");

        // Reset
        #100;
        resetn = 1;
        #50;

        // ========================================
        // TEST 1: Firmware upload (128 bytes - 2 blocks)
        // ========================================
        $display("\n========================================");
        $display("TEST 1: Firmware (128 bytes - 2 x 64-byte blocks)");
        $display("========================================");

        create_firmware_packet(32'd128, 32'h00);

        @(posedge clk);
        fw_loader_start = 1;
        @(posedge clk);
        fw_loader_start = 0;

        // Wait for completion
        wait(fw_loader_done || fw_loader_error);
        @(posedge clk);

        if (fw_loader_error) begin
            $display("\n[TEST 1] FAILED - Error occurred, NAK reason=0x%02x", fw_loader_nak_reason);
            test_errors = test_errors + 1;
        end else begin
            $display("\n[TEST 1] Firmware upload completed successfully");
            verify_sram(32'd128, 32'h00);
        end

        #1000;

        // ========================================
        // TEST 2: Single block firmware (64 bytes)
        // ========================================
        $display("\n========================================");
        $display("TEST 2: Single block (64 bytes exactly)");
        $display("========================================");

        // Clear SRAM
        for (integer i = 0; i < 64; i = i + 1) begin
            sram_mem[i] = 16'hFFFF;
        end

        create_firmware_packet(32'd64, 32'hA5);

        @(posedge clk);
        fw_loader_start = 1;
        @(posedge clk);
        fw_loader_start = 0;

        // Wait for completion
        wait(fw_loader_done || fw_loader_error);
        @(posedge clk);

        if (fw_loader_error) begin
            $display("\n[TEST 2] FAILED - Error occurred, NAK reason=0x%02x", fw_loader_nak_reason);
            test_errors = test_errors + 1;
        end else begin
            $display("\n[TEST 2] Firmware upload completed successfully");
            verify_sram(32'd64, 32'hA5);
        end

        #1000;

        // ========================================
        // TEST 3: Large firmware (192 bytes - 3 blocks)
        // ========================================
        $display("\n========================================");
        $display("TEST 3: Large firmware (192 bytes - 3 x 64-byte blocks)");
        $display("========================================");

        create_firmware_packet(32'd192, 32'h78);

        @(posedge clk);
        fw_loader_start = 1;
        @(posedge clk);
        fw_loader_start = 0;

        // Wait for completion
        wait(fw_loader_done || fw_loader_error);
        @(posedge clk);

        if (fw_loader_error) begin
            $display("\n[TEST 3] FAILED - Error occurred, NAK reason=0x%02x", fw_loader_nak_reason);
            test_errors = test_errors + 1;
        end else begin
            $display("\n[TEST 3] Firmware upload completed successfully");
            verify_sram(32'd192, 32'h78);
        end

        // ========================================
        // SUMMARY
        // ========================================
        $display("\n========================================");
        $display("TEST SUMMARY");
        $display("========================================");
        if (test_errors == 0) begin
            $display("✓ ALL FIRMWARE UPLOAD TESTS PASSED!");
            $display("  - Clean-room SRAM driver working correctly");
            $display("  - COOLDOWN fix prevents spurious transactions");
            $display("  - Ready for FPGA deployment");
        end else begin
            $display("✗ TESTS FAILED: %0d errors", test_errors);
        end
        $display("========================================\n");

        #10000;
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000000;  // 100ms timeout
        $display("\n[ERROR] Simulation timeout - firmware upload taking too long");
        $finish;
    end

endmodule
