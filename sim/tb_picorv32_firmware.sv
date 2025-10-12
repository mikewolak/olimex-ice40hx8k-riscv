/*
 * ModelSim Testbench for PicoRV32 Firmware Test
 * Tests LED blink firmware execution on PicoRV32 CPU
 */

`timescale 1ns/1ps

module tb_picorv32_firmware;

    // Clock and reset
    reg EXTCLK;
    reg BUT1, BUT2;
    wire LED1, LED2;

    // UART
    wire UART_TX;
    reg UART_RX;

    // SRAM
    wire [17:0] SA;
    wire [15:0] SD;
    wire SRAM_CS_N, SRAM_OE_N, SRAM_WE_N;

    // UART monitoring
    reg [7:0] uart_rx_buffer [0:4095];
    integer uart_rx_count = 0;
    reg uart_monitor_enable = 1;

    // Test control
    integer cycle_count = 0;
    integer led_toggle_count = 0;
    reg [31:0] led_state_time = 0;

    // DUT instantiation
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
    initial begin
        EXTCLK = 0;
        forever #5 EXTCLK = ~EXTCLK;  // 10ns period = 100 MHz
    end

    // UART RX character sender task
    task send_uart_char(input [7:0] char);
        integer i;
        begin
            // Start bit
            UART_RX = 0;
            #8680;  // 115200 baud = 8.68us per bit

            // 8 data bits
            for (i = 0; i < 8; i = i + 1) begin
                UART_RX = char[i];
                #8680;
            end

            // Stop bit
            UART_RX = 1;
            #8680;
        end
    endtask

    // UART RX string sender task
    task send_uart_string(input [8*64-1:0] str, input integer len);
        integer i;
        begin
            for (i = 0; i < len; i = i + 1) begin
                send_uart_char(str[i*8 +: 8]);
            end
        end
    endtask

    // Load firmware via firmware loader protocol
    task load_firmware(input [8*256-1:0] filename);
        integer fd, bytes_read, i;
        reg [7:0] firmware_data [0:131071];  // 128 KB max
        integer firmware_size;
        reg [31:0] size_le;
        reg [31:0] crc_value;
        begin
            $display("[%0t] Loading firmware: %s", $time, filename);

            // Read firmware binary
            fd = $fopen(filename, "rb");
            if (fd == 0) begin
                $display("[%0t] ERROR: Cannot open firmware file: %s", $time, filename);
                $finish;
            end

            firmware_size = 0;
            bytes_read = $fread(firmware_data, fd);
            $fclose(fd);
            firmware_size = bytes_read;

            $display("[%0t] Firmware size: %0d bytes", $time, firmware_size);

            // Send 'upload' command to shell
            #1000;
            send_uart_char(8'h75);  // 'u'
            send_uart_char(8'h70);  // 'p'
            send_uart_char(8'h6C);  // 'l'
            send_uart_char(8'h6F);  // 'o'
            send_uart_char(8'h61);  // 'a'
            send_uart_char(8'h64);  // 'd'
            send_uart_char(8'h0D);  // '\r'

            // Wait for shell to start firmware loader
            #50000;

            // Send firmware upload protocol:
            // 'R' + Size (4B LE) + Data + CRC32 (4B LE)

            // 1. Send 'R' ready character
            send_uart_char(8'h52);  // 'R'

            // 2. Send size (little-endian)
            size_le = firmware_size;
            send_uart_char(size_le[7:0]);
            send_uart_char(size_le[15:8]);
            send_uart_char(size_le[23:16]);
            send_uart_char(size_le[31:24]);

            // 3. Send firmware data in 64-byte blocks
            for (i = 0; i < firmware_size; i = i + 1) begin
                send_uart_char(firmware_data[i]);
                if ((i % 64) == 63) begin
                    // Wait for ACK after each 64-byte block
                    #100000;
                end
            end

            // Pad to 64-byte boundary
            while ((firmware_size % 64) != 0) begin
                send_uart_char(8'h00);
                firmware_size = firmware_size + 1;
            end

            // 4. Send CRC32 (simplified - just send zeros for now)
            crc_value = 32'h00000000;
            send_uart_char(crc_value[7:0]);
            send_uart_char(crc_value[15:8]);
            send_uart_char(crc_value[23:16]);
            send_uart_char(crc_value[31:24]);

            // Wait for firmware loader to complete
            #200000;

            $display("[%0t] Firmware upload complete", $time);
        end
    endtask

    // Load firmware from hex file (for $readmemh)
    task load_firmware_hex(input [8*256-1:0] filename);
        integer i;
        reg [31:0] mem_data [0:131071];  // 128K words
        integer mem_words;
        begin
            $display("[%0t] Loading firmware hex: %s", $time, filename);
            $readmemh(filename, mem_data);

            // Count non-zero words
            mem_words = 0;
            for (i = 0; i < 131072; i = i + 1) begin
                if (mem_data[i] !== 32'hxxxxxxxx && mem_data[i] !== 32'h00000000) begin
                    mem_words = i + 1;
                end
            end

            $display("[%0t] Loaded %0d words from hex file", $time, mem_words);

            // Manually write to SRAM via shell commands
            // For now, just use firmware loader protocol with converted data
            // TODO: Implement direct SRAM write
        end
    endtask

    // Monitor UART TX output
    always @(negedge UART_TX) begin
        if (uart_monitor_enable) begin
            automatic integer i;
            automatic reg [7:0] rx_char;

            // Wait for start bit
            #4340;  // Half bit time

            // Sample 8 data bits
            rx_char = 0;
            for (i = 0; i < 8; i = i + 1) begin
                #8680;
                rx_char[i] = UART_TX;
            end

            // Wait for stop bit
            #8680;

            // Store character
            uart_rx_buffer[uart_rx_count] = rx_char;
            uart_rx_count = uart_rx_count + 1;

            // Display printable characters
            if (rx_char >= 32 && rx_char < 127) begin
                $write("%c", rx_char);
            end else if (rx_char == 8'h0A) begin
                $display("");
            end else if (rx_char == 8'h0D) begin
                // Carriage return - ignore
            end else begin
                $write("[0x%02X]", rx_char);
            end
        end
    end

    // Monitor LED state changes
    reg prev_led1 = 0;
    reg prev_led2 = 0;

    always @(LED1, LED2) begin
        if (LED1 !== prev_led1 || LED2 !== prev_led2) begin
            $display("[%0t] LED state change: LED1=%b LED2=%b (cycle %0d)",
                     $time, LED1, LED2, cycle_count);
            led_toggle_count = led_toggle_count + 1;
            led_state_time = cycle_count;
            prev_led1 = LED1;
            prev_led2 = LED2;
        end
    end

    // Cycle counter (25 MHz system clock)
    always @(posedge dut.clk) begin
        cycle_count = cycle_count + 1;
    end

    // Main test sequence
    initial begin
        $display("========================================");
        $display("PicoRV32 Firmware Test");
        $display("========================================");

        // Initialize
        BUT1 = 1;
        BUT2 = 1;
        UART_RX = 1;

        // Wait for reset
        #1000;

        // Load firmware binary (if available)
        // Uncomment when firmware is compiled:
        // load_firmware("firmware/led_blink.bin");

        // Alternative: Load from hex file
        // load_firmware_hex("firmware/led_blink.hex");

        // For now, skip firmware load and just test the shell
        $display("[%0t] NOTE: Firmware loading skipped - need to compile firmware first", $time);
        $display("[%0t] Testing shell 'r' command to release CPU", $time);

        // Wait for system to initialize
        #100000;

        // Send 'r' command to release CPU from reset
        $display("[%0t] Sending 'r' command", $time);
        send_uart_char(8'h72);  // 'r'
        send_uart_char(8'h0D);  // '\r'

        // Run for a long time to see LED toggles
        // At 25 MHz, 1 second = 25M cycles
        // LED pattern should change every ~1M cycles
        $display("[%0t] Running simulation for 20M cycles (~0.8 seconds)", $time);

        // Wait for LED activity
        #200000000;  // 200us in real time

        // Check results
        $display("");
        $display("========================================");
        $display("Test Results:");
        $display("========================================");
        $display("Total LED state changes: %0d", led_toggle_count);
        $display("UART characters received: %0d", uart_rx_count);

        if (led_toggle_count > 0) begin
            $display("SUCCESS: LED activity detected");
        end else begin
            $display("WARNING: No LED activity - firmware may not be loaded");
        end

        if (uart_rx_count > 10) begin
            $display("SUCCESS: UART output detected");
        end else begin
            $display("WARNING: Minimal UART output");
        end

        $display("========================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500000000;  // 500ms timeout
        $display("[%0t] TIMEOUT: Simulation timeout reached", $time);
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("picorv32_firmware.vcd");
        $dumpvars(0, tb_picorv32_firmware);
    end

endmodule
