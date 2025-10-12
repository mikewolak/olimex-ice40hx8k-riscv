/*
 * Simplified ModelSim Testbench for PicoRV32 Integration
 * Direct SRAM load -> CPU Release -> LED Verification
 */

`timescale 1ns / 1ps

module tb_picorv32_direct;

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
    integer uart_chars = 0;
    integer led_toggle_count = 0;
    reg [1:0] last_led_state = 2'b00;
    reg test_passed = 0;
    reg [7:0] uart_message [0:255];
    integer uart_msg_idx = 0;

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
        end
    endtask

    // Monitor UART TX
    task uart_monitor_byte;
        reg [7:0] data;
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

            // Store character
            uart_message[uart_msg_idx] = data;
            uart_msg_idx = uart_msg_idx + 1;
            uart_chars = uart_chars + 1;

            $write("%c", data);
            if (data == 8'h0A) begin  // Newline
                $write("\n");
            end
        end
    endtask

    // Load firmware directly into SRAM
    task load_firmware_direct;
        integer i, addr;
        begin
            $display("========================================");
            $display("Loading firmware: firmware/led_blink.bin");
            fd = $fopen("firmware/led_blink.bin", "rb");
            if (fd == 0) begin
                $display("ERROR: Cannot open firmware file!");
                $finish;
            end

            bytes_read = $fread(firmware_bytes, fd);
            $fclose(fd);

            firmware_size = bytes_read;
            $display("Firmware size: %0d bytes", firmware_size);

            // Load firmware into SRAM (16-bit words, little-endian)
            for (i = 0; i < firmware_size; i = i + 2) begin
                addr = i / 2;
                if (i + 1 < firmware_size)
                    sram_mem[addr] = {firmware_bytes[i+1], firmware_bytes[i]};
                else
                    sram_mem[addr] = {8'h00, firmware_bytes[i]};
            end

            $display("Firmware loaded into SRAM");
            $display("First 16 words of SRAM:");
            for (i = 0; i < 16; i = i + 1) begin
                $display("  SRAM[0x%04x] = 0x%04x", i, sram_mem[i]);
            end
            $display("========================================");
        end
    endtask

    // Monitor LED changes
    always @(LED1 or LED2) begin
        if ({LED2, LED1} != last_led_state) begin
            led_toggle_count = led_toggle_count + 1;
            $display("[TIME=%0dns] LED1=%b LED2=%b (toggle #%0d)", $time, LED1, LED2, led_toggle_count);
            last_led_state = {LED2, LED1};
        end
    end

    // Monitor UART TX (background task)
    initial begin
        forever begin
            uart_monitor_byte();
        end
    end

    // Main test sequence
    initial begin
        $display("========================================");
        $display("PicoRV32 Direct SRAM Load Test");
        $display("========================================");
        $display("Test: Direct Load -> Reset CPU -> Monitor");
        $display("Clock: 100 MHz -> 25 MHz (div-by-4)");
        $display("========================================\n");

        // Initialize SRAM to zero
        for (integer i = 0; i < 262144; i = i + 1) begin
            sram_mem[i] = 16'h0000;
        end

        // Load firmware
        $display("[PHASE 1] Load Firmware Directly to SRAM");
        load_firmware_direct();

        // Wait for reset
        $display("\n[PHASE 2] System Reset");
        UART_RX = 1;
        #5000;
        $display("Reset complete\n");

        // Release CPU
        $display("[PHASE 3] Release CPU from Reset");
        $display("Sending 'r' command to shell...");
        #(UART_BIT_PERIOD * 5);  // Wait before sending
        uart_send_byte(8'h72);  // 'r' command
        #(UART_BIT_PERIOD * 2);  // Extra delay between chars
        uart_send_byte(8'h0A);  // newline
        #(UART_BIT_PERIOD * 50);  // Longer wait for response
        $display("CPU released\n");

        // Monitor execution
        $display("[PHASE 4] Monitor CPU Execution");
        $display("Expected UART output:");
        $display("  - 'PicoRV32 LED Blink Test\\r\\n'");
        $display("  - 'LED1 and LED2 alternating\\r\\n'");
        $display("  - LED pattern: 1 -> 2 -> 3 -> 0 (repeating)");
        $display("  - UART chars: 1, 2, 3, 0 (repeating)");
        $display("\nMonitoring for 20ms...\n");

        // Run for 20ms to see shell response
        #20_000_000;

        // Final report
        $display("\n========================================");
        $display("SIMULATION COMPLETE");
        $display("========================================");
        $display("Runtime: 20ms simulation time");
        $display("UART characters received: %0d", uart_chars);
        $display("LED toggles: %0d", led_toggle_count);
        $display("Final LED state: LED1=%b LED2=%b", LED1, LED2);

        // Pass/fail criteria
        if (uart_chars >= 50 && led_toggle_count >= 4) begin
            $display("\n*** TEST PASSED ***");
            $display("  - Firmware loaded successfully");
            $display("  - CPU executed and generated UART output");
            $display("  - LEDs toggled as expected");
            test_passed = 1;
        end else begin
            $display("\n*** TEST FAILED ***");
            if (uart_chars < 50)
                $display("  - Insufficient UART output (expected >= 50, got %0d)", uart_chars);
            if (led_toggle_count < 4)
                $display("  - Insufficient LED toggles (expected >= 4, got %0d)", led_toggle_count);
        end

        $display("========================================\n");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500_000_000;  // 500ms timeout
        $display("\n*** TIMEOUT: Simulation exceeded 500ms ***");
        $finish;
    end

    // Monitor shell state for debugging
    always @(posedge EXTCLK) begin
        if (dut.shell_inst.state == 5'h2A) begin  // STATE_CPU_RUN_READ_INSTR
            $display("[TB] Shell entered STATE_CPU_RUN_READ_INSTR at t=%0t", $time);
        end
        if (dut.shell_inst.state == 5'h2B) begin  // STATE_CPU_RUN_WAIT_INSTR
            $display("[TB] Shell entered STATE_CPU_RUN_WAIT_INSTR at t=%0t", $time);
        end
        if (dut.shell_inst.state == 5'h28) begin  // STATE_CPU_RUN
            $display("[TB] Shell entered STATE_CPU_RUN at t=%0t, first_instruction=0x%08x",
                     $time, dut.shell_inst.first_instruction);
        end
    end

    // Waveform dump - DISABLED for speed
    // initial begin
    //     $dumpfile("tb_picorv32_direct.vcd");
    //     $dumpvars(0, tb_picorv32_direct);
    //     $dumpvars(0, dut);
    // end

endmodule
