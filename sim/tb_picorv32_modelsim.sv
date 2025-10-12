/*
 * ModelSim Testbench for PicoRV32 Firmware Execution
 *
 * Properly loads firmware into SRAM model and tests CPU execution
 */

`timescale 1ns/1ps

module tb_picorv32_modelsim;

    // Clock and reset
    reg EXTCLK;
    reg BUT1, BUT2;
    wire LED1, LED2;

    // UART
    wire UART_TX;
    reg UART_RX;

    // SRAM interface
    wire [17:0] SA;
    wire [15:0] SD;
    wire SRAM_CS_N, SRAM_OE_N, SRAM_WE_N;

    // Test control
    integer cycle_count = 0;
    integer led_changes = 0;
    reg [31:0] last_led_time = 0;
    reg [1:0] prev_leds = 2'b00;
    reg [1:0] expected_pattern [0:3];
    integer pattern_index = 0;
    integer pattern_errors = 0;

    // UART monitoring
    reg [7:0] uart_buffer [0:1023];
    integer uart_count = 0;
    reg uart_active = 0;

    // Initialize expected LED patterns
    initial begin
        expected_pattern[0] = 2'b01;  // LED1 on
        expected_pattern[1] = 2'b10;  // LED2 on
        expected_pattern[2] = 2'b11;  // Both on
        expected_pattern[3] = 2'b00;  // Both off
    end

    //========================================
    // SRAM Model (K6R4016V1D-TC10)
    // 256K x 16-bit = 512KB
    //========================================
    reg [15:0] sram_mem [0:262143];  // 256K words of 16 bits
    reg [15:0] sram_data_out;
    reg sram_output_enable;

    // SRAM tristate data bus
    assign SD = (!SRAM_OE_N && !SRAM_CS_N && sram_output_enable) ? sram_data_out : 16'hzzzz;

    // SRAM behavioral model
    always @(*) begin
        if (!SRAM_CS_N) begin
            if (!SRAM_WE_N) begin
                // Write operation
                sram_mem[SA] = SD;
                sram_output_enable = 0;
            end else if (!SRAM_OE_N) begin
                // Read operation
                sram_data_out = sram_mem[SA];
                sram_output_enable = 1;
            end else begin
                sram_output_enable = 0;
            end
        end else begin
            sram_output_enable = 0;
        end
    end

    // Initialize SRAM to zero
    integer i;
    initial begin
        for (i = 0; i < 262144; i = i + 1) begin
            sram_mem[i] = 16'h0000;
        end
    end

    //========================================
    // DUT Instantiation
    //========================================
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

    //========================================
    // Clock Generation: 100 MHz
    //========================================
    initial begin
        EXTCLK = 0;
        forever #5 EXTCLK = ~EXTCLK;
    end

    //========================================
    // UART Tasks
    //========================================

    // Send one UART character at 115200 baud
    task send_uart_char(input [7:0] char);
        integer j;
        begin
            // Start bit
            UART_RX = 0;
            #8680;  // 8.68us per bit @ 115200

            // 8 data bits
            for (j = 0; j < 8; j = j + 1) begin
                UART_RX = char[j];
                #8680;
            end

            // Stop bit
            UART_RX = 1;
            #8680;
        end
    endtask

    // Send string via UART
    task send_uart_string(input [8*64-1:0] str, input integer len);
        integer j;
        begin
            for (j = 0; j < len; j = j + 1) begin
                send_uart_char(str[j*8 +: 8]);
            end
        end
    endtask

    //========================================
    // Firmware Loading
    //========================================

    task load_firmware_direct(input [8*256-1:0] filename);
        integer fd, bytes_read, addr, byte_val;
        reg [7:0] firmware_bytes [0:131071];
        integer firmware_size;
        begin
            $display("[%0t] Loading firmware: %s", $time, filename);

            // Read binary file
            fd = $fopen(filename, "rb");
            if (fd == 0) begin
                $display("[%0t] ERROR: Cannot open firmware: %s", $time, filename);
                $finish;
            end

            bytes_read = $fread(firmware_bytes, fd);
            $fclose(fd);
            firmware_size = bytes_read;

            $display("[%0t] Firmware size: %0d bytes", $time, firmware_size);

            // Load firmware into SRAM model (16-bit words, little-endian)
            for (addr = 0; addr < firmware_size; addr = addr + 2) begin
                if (addr + 1 < firmware_size) begin
                    sram_mem[addr/2] = {firmware_bytes[addr+1], firmware_bytes[addr]};
                end else begin
                    sram_mem[addr/2] = {8'h00, firmware_bytes[addr]};
                end
            end

            $display("[%0t] Firmware loaded into SRAM", $time);

            // Verify first few words
            $display("First 8 words of SRAM:");
            for (addr = 0; addr < 8; addr = addr + 1) begin
                $display("  [0x%04x] = 0x%04x", addr, sram_mem[addr]);
            end
        end
    endtask

    //========================================
    // UART TX Monitor
    //========================================

    always @(negedge UART_TX) begin
        automatic integer j;
        automatic reg [7:0] rx_byte;

        if (!uart_active) begin
            uart_active = 1;

            // Wait for middle of start bit
            #4340;

            // Sample 8 data bits
            rx_byte = 0;
            for (j = 0; j < 8; j = j + 1) begin
                #8680;
                rx_byte[j] = UART_TX;
            end

            // Wait for stop bit
            #8680;

            // Store and display
            uart_buffer[uart_count] = rx_byte;
            uart_count = uart_count + 1;

            if (rx_byte >= 32 && rx_byte < 127) begin
                $write("%c", rx_byte);
            end else if (rx_byte == 8'h0A) begin
                $display("");
            end else if (rx_byte != 8'h0D) begin
                $write("[0x%02X]", rx_byte);
            end

            uart_active = 0;
        end
    end

    //========================================
    // LED Monitor
    //========================================

    always @(LED1, LED2) begin
        automatic reg [1:0] current_leds;
        current_leds = {LED2, LED1};

        if (current_leds !== prev_leds && cycle_count > 1000) begin
            $display("[%0t] LED change: LED1=%b LED2=%b (cycle %0d, delta=%0d cycles)",
                     $time, LED1, LED2, cycle_count, cycle_count - last_led_time);

            // Check if matches expected pattern
            if (current_leds == expected_pattern[pattern_index]) begin
                $display("  ✓ Matches expected pattern %0d", pattern_index);
            end else begin
                $display("  ✗ ERROR: Expected pattern %0d (2'b%b), got 2'b%b",
                         pattern_index, expected_pattern[pattern_index], current_leds);
                pattern_errors = pattern_errors + 1;
            end

            pattern_index = (pattern_index + 1) % 4;
            led_changes = led_changes + 1;
            last_led_time = cycle_count;
            prev_leds = current_leds;
        end
    end

    //========================================
    // Cycle Counter
    //========================================

    always @(posedge dut.clk) begin
        cycle_count = cycle_count + 1;
    end

    //========================================
    // Main Test Sequence
    //========================================

    initial begin
        $display("==================================================");
        $display("PicoRV32 Firmware Execution Test");
        $display("Firmware: led_blink.bin");
        $display("==================================================");

        // Initialize
        BUT1 = 1;
        BUT2 = 1;
        UART_RX = 1;

        // Wait for global reset
        #100;

        // Load firmware directly into SRAM
        load_firmware_direct("firmware/led_blink.bin");

        // Wait for system initialization
        #10000;

        // Send 'r' command to release CPU from reset
        $display("");
        $display("[%0t] Sending 'r' command to release CPU", $time);
        send_uart_char(8'h72);  // 'r'
        send_uart_char(8'h0D);  // '\r'

        // Wait for CPU to start and LEDs to begin toggling
        $display("[%0t] Waiting for CPU execution...", $time);
        #500000;  // 500us

        // Run for multiple LED cycles
        // Expected: ~1M cycles per LED state at 25 MHz
        // 4 states = 4M cycles = 160ms
        // Run for 20M cycles = 800ms = ~5 complete cycles
        $display("[%0t] Running for 20M cycles (~800ms @ 25MHz)", $time);
        #20000000;  // 20ms real time

        // Check results
        $display("");
        $display("==================================================");
        $display("Test Results:");
        $display("==================================================");
        $display("CPU cycles executed:  %0d", cycle_count);
        $display("LED state changes:    %0d", led_changes);
        $display("Pattern errors:       %0d", pattern_errors);
        $display("UART characters RX:   %0d", uart_count);

        // Expected ~5 complete cycles = 20 LED changes
        if (led_changes >= 16 && led_changes <= 24) begin
            $display("✓ LED toggle count in expected range");
        end else begin
            $display("✗ ERROR: LED toggle count out of range (expected 16-24)");
        end

        if (pattern_errors == 0) begin
            $display("✓ All LED patterns matched expected sequence");
        end else begin
            $display("✗ ERROR: %0d pattern mismatches", pattern_errors);
        end

        if (uart_count > 50) begin
            $display("✓ UART output detected (startup messages + status chars)");
        end else begin
            $display("✗ WARNING: Low UART output count");
        end

        // Overall result
        if (led_changes >= 16 && pattern_errors == 0 && uart_count > 50) begin
            $display("");
            $display("==================================================");
            $display("TEST PASSED ✓");
            $display("==================================================");
        end else begin
            $display("");
            $display("==================================================");
            $display("TEST FAILED ✗");
            $display("==================================================");
        end

        $finish;
    end

    // Timeout watchdog
    initial begin
        #50000000;  // 50ms timeout
        $display("[%0t] TIMEOUT: Test did not complete", $time);
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("picorv32_firmware.vcd");
        $dumpvars(0, tb_picorv32_modelsim);
    end

endmodule
