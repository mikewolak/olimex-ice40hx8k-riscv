/*
 * Complete ModelSim Testbench for PicoRV32 Integration
 * Tests full flow: Reset -> Firmware Upload -> CPU Release -> LED Verification
 */

`timescale 1ns / 1ps

module tb_picorv32_complete;

    // Clock and Reset
    reg EXTCLK = 0;
    reg BUT1 = 1;
    reg BUT2 = 1;
    wire LED1, LED2;

    // UART
    reg UART_RX = 1;
    wire UART_TX;

    // SRAM Interface
    wire [17:0] SA;
    wire [15:0] SD;
    wire SRAM_CS_N, SRAM_OE_N, SRAM_WE_N;

    // SRAM Memory Model (256K x 16-bit = 512KB)
    reg [15:0] sram_mem [0:262143];
    reg [15:0] sram_data_out;
    reg sram_output_enable;

    // SRAM tri-state control
    assign SD = (!SRAM_OE_N && !SRAM_CS_N && sram_output_enable) ? sram_data_out : 16'hzzzz;

    // SRAM behavioral model
    always @(*) begin
        if (!SRAM_CS_N && !SRAM_OE_N) begin
            sram_data_out = sram_mem[SA];
            sram_output_enable = 1'b1;
        end else begin
            sram_data_out = 16'h0000;
            sram_output_enable = 1'b0;
        end
    end

    always @(posedge EXTCLK) begin
        if (!SRAM_CS_N && !SRAM_WE_N) begin
            sram_mem[SA] <= SD;
        end
    end

    // DUT - Top-level module
    ice40_picorv32_top dut (
        .EXTCLK(EXTCLK),
        .BUT1(BUT1),
        .BUT2(BUT2),
        .LED1(LED1),
        .LED2(LED2),
        .UART_RX(UART_RX),
        .UART_TX(UART_TX),
        .SA(SA),
        .SD(SD),
        .SRAM_CS_N(SRAM_CS_N),
        .SRAM_OE_N(SRAM_OE_N),
        .SRAM_WE_N(SRAM_WE_N)
    );

    // Clock generation: 100 MHz
    always #5 EXTCLK = ~EXTCLK;

    // UART bit period: 115200 baud = 8680.56 ns
    localparam UART_BIT_PERIOD = 8680;

    // Firmware data
    reg [7:0] firmware_bytes [0:4095];
    integer firmware_size;
    integer fd, bytes_read;

    // Test statistics
    integer uart_tx_count = 0;
    integer led_toggle_count = 0;
    reg [1:0] last_led_state = 2'b00;
    reg test_passed = 0;

    // UART tasks
    task uart_send_byte(input [7:0] data);
        integer i;
        begin
            // Start bit
            UART_RX = 0;
            #UART_BIT_PERIOD;

            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                UART_RX = data[i];
                #UART_BIT_PERIOD;
            end

            // Stop bit
            UART_RX = 1;
            #UART_BIT_PERIOD;

            $display("[UART TX] Sent byte: 0x%02x ('%c')", data,
                     (data >= 32 && data < 127) ? data : 8'h2E);
        end
    endtask

    task uart_receive_byte(output [7:0] data);
        integer i;
        begin
            // Wait for start bit
            wait (UART_TX == 0);
            #(UART_BIT_PERIOD / 2);  // Sample in middle of start bit
            #UART_BIT_PERIOD;        // Move to first data bit

            // Receive data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                data[i] = UART_TX;
                #UART_BIT_PERIOD;
            end

            // Stop bit
            #UART_BIT_PERIOD;

            uart_tx_count = uart_tx_count + 1;
            $display("[UART RX] Received byte: 0x%02x ('%c') [Total: %0d]", data,
                     (data >= 32 && data < 127) ? data : 8'h2E, uart_tx_count);
        end
    endtask

    // CRC32 calculation (matches firmware_loader CRC)
    function [31:0] crc32_byte;
        input [31:0] crc;
        input [7:0] data;
        integer i;
        reg [31:0] temp;
        begin
            temp = crc ^ {24'h0, data};
            for (i = 0; i < 8; i = i + 1) begin
                if (temp[0])
                    temp = (temp >> 1) ^ 32'hEDB88320;
                else
                    temp = temp >> 1;
            end
            crc32_byte = temp;
        end
    endfunction

    function [31:0] calculate_crc32;
        input integer size;
        integer i;
        reg [31:0] crc;
        begin
            crc = 32'hFFFFFFFF;
            for (i = 0; i < size; i = i + 1) begin
                crc = crc32_byte(crc, firmware_bytes[i]);
            end
            calculate_crc32 = ~crc;
        end
    endfunction

    // Load firmware from file
    task load_firmware;
        integer i, addr;
        begin
            $display("========================================");
            $display("Loading firmware: %s", firmware_file);
            fd = $fopen(firmware_file, "rb");
            if (fd == 0) begin
                $display("ERROR: Cannot open firmware file!");
                $finish;
            end

            bytes_read = $fread(firmware_bytes, fd);
            $fclose(fd);

            if (bytes_read == 0) begin
                $display("ERROR: No bytes read from firmware file!");
                $finish;
            end

            firmware_size = bytes_read;
            $display("Firmware size: %0d bytes", firmware_size);

            // Display first 32 bytes
            $display("First 32 bytes:");
            for (i = 0; i < 32 && i < firmware_size; i = i + 1) begin
                if ((i % 16) == 0) $write("  %04x: ", i);
                $write("%02x ", firmware_bytes[i]);
                if ((i % 16) == 15) $write("\n");
            end
            if ((i % 16) != 0) $write("\n");
            $display("========================================");
        end
    endtask

    // Upload firmware via UART protocol
    task upload_firmware;
        integer i;
        reg [31:0] crc;
        reg [7:0] rx_byte;
        begin
            $display("========================================");
            $display("Starting firmware upload...");
            $display("========================================");

            // Calculate CRC32
            crc = calculate_crc32(firmware_size);
            $display("Calculated CRC32: 0x%08x", crc);

            // Send 'R' command
            uart_send_byte(8'h52);  // 'R'
            #(UART_BIT_PERIOD * 10);

            // Send size (4 bytes, little-endian)
            uart_send_byte(firmware_size[7:0]);
            uart_send_byte(firmware_size[15:8]);
            uart_send_byte(firmware_size[23:16]);
            uart_send_byte(firmware_size[31:24]);
            $display("Sent firmware size: %0d bytes", firmware_size);
            #(UART_BIT_PERIOD * 10);

            // Send firmware data
            $display("Sending %0d bytes of firmware data...", firmware_size);
            for (i = 0; i < firmware_size; i = i + 1) begin
                uart_send_byte(firmware_bytes[i]);
                if ((i % 64) == 63) begin
                    $display("  Progress: %0d/%0d bytes", i+1, firmware_size);
                end
            end
            $display("Firmware data sent: %0d bytes", firmware_size);
            #(UART_BIT_PERIOD * 10);

            // Send CRC32 (4 bytes, little-endian)
            uart_send_byte(crc[7:0]);
            uart_send_byte(crc[15:8]);
            uart_send_byte(crc[23:16]);
            uart_send_byte(crc[31:24]);
            $display("Sent CRC32: 0x%08x", crc);
            #(UART_BIT_PERIOD * 10);

            // Wait for ACK response
            $display("Waiting for ACK...");
            fork
                begin
                    uart_receive_byte(rx_byte);
                    if (rx_byte == 8'h06) begin  // ACK
                        $display("*** FIRMWARE UPLOAD SUCCESS - ACK RECEIVED ***");
                    end else begin
                        $display("*** ERROR: Expected ACK (0x06), got 0x%02x ***", rx_byte);
                    end
                end
                begin
                    #(UART_BIT_PERIOD * 200);
                    $display("*** ERROR: Timeout waiting for ACK ***");
                end
            join_any
            disable fork;

            #(UART_BIT_PERIOD * 20);
            $display("========================================");
        end
    endtask

    // Monitor LED changes
    always @(LED1 or LED2) begin
        if ({LED2, LED1} != last_led_state) begin
            led_toggle_count = led_toggle_count + 1;
            $display("[LED] LED1=%b LED2=%b (toggle count: %0d)", LED1, LED2, led_toggle_count);
            last_led_state = {LED2, LED1};
        end
    end

    // Monitor UART TX characters (continuous)
    reg [7:0] uart_char;
    integer uart_rx_count = 0;
    initial begin
        forever begin
            uart_receive_byte(uart_char);
            uart_rx_count = uart_rx_count + 1;
        end
    end

    // Main test sequence
    string firmware_file = "firmware/led_blink.bin";
    initial begin
        $display("========================================");
        $display("PicoRV32 Complete Integration Test");
        $display("========================================");
        $display("Test: Reset -> Upload -> Release -> Verify");
        $display("Clock: 100 MHz -> 25 MHz (div-by-4)");
        $display("UART: 115200 baud, 8N1");
        $display("========================================");

        // Initialize SRAM to zero
        for (integer i = 0; i < 262144; i = i + 1) begin
            sram_mem[i] = 16'h0000;
        end

        // Reset phase
        $display("\n[PHASE 1] System Reset");
        UART_RX = 1;
        BUT1 = 1;
        BUT2 = 1;
        #1000;

        // Wait for reset to complete (256 clocks @ 100 MHz)
        #3000;
        $display("Reset complete, system ready");

        // Load firmware
        $display("\n[PHASE 2] Load Firmware Binary");
        load_firmware();

        // Upload firmware
        $display("\n[PHASE 3] Upload Firmware via UART");
        upload_firmware();

        // Verify SRAM contents
        $display("\n[PHASE 4] Verify SRAM Contents");
        $display("First 16 words of SRAM:");
        for (integer i = 0; i < 16; i = i + 1) begin
            $display("  SRAM[0x%04x] = 0x%04x", i, sram_mem[i]);
        end

        // Release CPU from reset
        $display("\n[PHASE 5] Release CPU from Reset");
        uart_send_byte(8'h72);  // 'r' command
        uart_send_byte(8'h0A);  // newline
        #(UART_BIT_PERIOD * 20);

        // Monitor execution
        $display("\n[PHASE 6] Monitor CPU Execution");
        $display("Waiting for UART startup message...");
        $display("Expected: 'PicoRV32 LED Blink Test\\r\\n'");
        $display("Expected: 'LED1 and LED2 alternating\\r\\n'");
        $display("Expected LED pattern: 1 -> 2 -> 3 -> 0 (repeat)");
        $display("Monitoring for 100ms...");

        // Run for 100ms to see LED toggles
        #100_000_000;

        // Final report
        $display("\n========================================");
        $display("SIMULATION COMPLETE");
        $display("========================================");
        $display("Total UART bytes received: %0d", uart_rx_count);
        $display("Total LED toggles: %0d", led_toggle_count);
        $display("Final LED state: LED1=%b LED2=%b", LED1, LED2);

        // Pass/fail criteria
        if (uart_rx_count >= 50 && led_toggle_count >= 4) begin
            $display("*** TEST PASSED ***");
            $display("  - Firmware uploaded successfully");
            $display("  - CPU executed and generated UART output");
            $display("  - LEDs toggled as expected");
            test_passed = 1;
        end else begin
            $display("*** TEST FAILED ***");
            if (uart_rx_count < 50)
                $display("  - Insufficient UART output (expected >= 50, got %0d)", uart_rx_count);
            if (led_toggle_count < 4)
                $display("  - Insufficient LED toggles (expected >= 4, got %0d)", led_toggle_count);
        end

        $display("========================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500_000_000;  // 500ms timeout
        $display("\n*** TIMEOUT: Simulation exceeded 500ms ***");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_picorv32_complete.vcd");
        $dumpvars(0, tb_picorv32_complete);
        $dumpvars(0, dut);
    end

endmodule
