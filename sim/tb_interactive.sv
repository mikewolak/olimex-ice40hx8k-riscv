/*
 * Interactive Firmware Test - Bidirectional Mode Switching
 * Tests 's' command and interactive firmware with UART read
 */

`timescale 1ns / 1ps

module tb_interactive;

    // Clock and Reset
    reg EXTCLK = 0;
    reg BUT1 = 1;
    wire LED1, LED2;

    // UART
    reg UART_RX = 1;
    wire UART_TX;

    // SRAM Interface
    wire [17:0] SA;
    wire [15:0] SD;
    wire SRAM_CS_N, SRAM_OE_N, SRAM_WE_N;

    // SRAM Memory Model
    reg [15:0] sram_mem [0:262143];
    reg [15:0] sram_data_out;
    reg sram_output_enable;

    assign SD = (!SRAM_OE_N && !SRAM_CS_N && sram_output_enable) ? sram_data_out : 16'hzzzz;

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

    // DUT
    ice40_picorv32_top dut (
        .EXTCLK(EXTCLK),
        .BUT1(BUT1),
        .BUT2(1'b1),
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

    // Clock: 100 MHz
    always #5 EXTCLK = ~EXTCLK;

    // UART: 115200 baud
    localparam UART_BIT_PERIOD = 8680;

    task uart_send_byte(input [7:0] data);
        integer i;
        begin
            UART_RX = 0;  // Start bit
            #UART_BIT_PERIOD;
            for (i = 0; i < 8; i = i + 1) begin
                UART_RX = data[i];
                #UART_BIT_PERIOD;
            end
            UART_RX = 1;  // Stop bit
            #UART_BIT_PERIOD;
        end
    endtask

    // UART RX
    reg [7:0] uart_rx_byte;
    integer uart_rx_count = 0;
    reg [7:0] uart_rx_buffer [0:255];

    task uart_receive_byte;
        integer i;
        begin
            wait(UART_TX == 0);
            #(UART_BIT_PERIOD / 2);
            #UART_BIT_PERIOD;
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_byte[i] = UART_TX;
                #UART_BIT_PERIOD;
            end
            #UART_BIT_PERIOD;
            uart_rx_buffer[uart_rx_count] = uart_rx_byte;
            uart_rx_count = uart_rx_count + 1;
            $display("[UART RX] 0x%02x ('%c')",
                     uart_rx_byte,
                     (uart_rx_byte >= 32 && uart_rx_byte <= 126) ? uart_rx_byte : ".");
        end
    endtask

    initial begin
        forever begin
            @(negedge UART_TX);
            uart_receive_byte();
        end
    end

    // Load firmware
    task load_firmware;
        integer word_addr, byte_addr, i;
        reg [7:0] byte_mem [0:524287];
        begin
            $display("[TEST] Loading firmware from firmware/interactive.hex...");

            for (i = 0; i < 524288; i = i + 1) byte_mem[i] = 8'h00;
            $readmemh("firmware/interactive.hex", byte_mem);

            for (word_addr = 0; word_addr < 262144; word_addr = word_addr + 1) begin
                byte_addr = word_addr * 2;
                sram_mem[word_addr] = {byte_mem[byte_addr + 1], byte_mem[byte_addr]};
            end

            $display("[TEST] First instruction = 0x%04x%04x", sram_mem[1], sram_mem[0]);
        end
    endtask

    // Main test
    initial begin
        $display("========================================");
        $display("Interactive Firmware Test");
        $display("========================================\n");

        // Load firmware
        load_firmware();

        #10000;
        $display("\n[TEST] Waiting for shell prompt...");
        #500000;

        // Test 1: 's' command from shell
        $display("\n[TEST] TEST 1: Sending 's' command (SHELL->APP)");
        #(UART_BIT_PERIOD * 10);
        uart_send_byte(8'h73);  // 's'
        uart_send_byte(8'h0A);  // newline

        $display("[TEST] Waiting for 'SWITCHING TO APP MODE' message...");
        #2000000;

        $display("\n[TEST] Checking mode:");
        $display("  app_mode = %b", dut.app_mode);
        $display("  cpu_resetn = %b", dut.cpu_resetn);

        if (dut.app_mode == 1'b1) begin
            $display("[PASS] System switched to APP mode");
        end else begin
            $display("[FAIL] System still in SHELL mode");
            $finish;
        end

        // Wait for interactive firmware menu
        // Menu is ~259 chars * 87us/char = ~22.5ms
        $display("\n[TEST] Waiting for interactive firmware menu...");
        #25000000;

        // Test 2: Send CPU commands
        $display("\n[TEST] TEST 2: Sending '1' command to CPU (LED1 on)");
        uart_send_byte(8'h31);  // '1'
        #1000000;

        $display("\n[TEST] TEST 3: Sending 't' command to CPU (toggle LEDs)");
        uart_send_byte(8'h74);  // 't'
        #1000000;

        $display("\n[TEST] TEST 4: Sending 'c' command to CPU (show counter)");
        uart_send_byte(8'h63);  // 'c'
        #1000000;

        // Test 3: Return to shell from CPU
        $display("\n[TEST] TEST 5: Sending 's' command to CPU (APP->SHELL)");
        uart_send_byte(8'h73);  // 's'
        // Wait for: echo 's' + \r\n + "Switching to SHELL mode...\n" (~32 chars) + delay(100000)
        // 32 chars * 87us + 1ms + margin = ~4ms total, use 10ms to be safe
        #10000000;

        $display("\n[TEST] Checking mode after CPU 's' command:");
        $display("  app_mode = %b", dut.app_mode);

        if (dut.app_mode == 1'b0) begin
            $display("[PASS] System switched back to SHELL mode");
        end else begin
            $display("[FAIL] System still in APP mode");
        end

        // Test 4: Switch back to APP
        $display("\n[TEST] TEST 6: Sending 's' again from SHELL (SHELL->APP again)");
        #1000000;
        uart_send_byte(8'h73);  // 's'
        uart_send_byte(8'h0A);  // newline
        #2000000;

        if (dut.app_mode == 1'b1) begin
            $display("[PASS] System switched back to APP mode");
        end else begin
            $display("[FAIL] Failed to switch back to APP");
        end

        $display("\n========================================");
        $display("FINAL RESULTS");
        $display("========================================");
        $display("  Total UART bytes received: %d", uart_rx_count);
        $display("  LED1 = %b, LED2 = %b", LED1, LED2);

        // Decode some of the UART message
        $display("\n[UART] First 200 characters:");
        for (integer i = 0; i < 200 && i < uart_rx_count; i = i + 1) begin
            if (uart_rx_buffer[i] >= 32 && uart_rx_buffer[i] <= 126)
                $write("%c", uart_rx_buffer[i]);
            else if (uart_rx_buffer[i] == 8'h0D)
                $write("<CR>");
            else if (uart_rx_buffer[i] == 8'h0A)
                $write("<LF>\n");
            else
                $write("[0x%02x]", uart_rx_buffer[i]);
        end
        $display("\n");

        $display("\n========================================");
        $display("Interactive Test Complete");
        $display("========================================\n");

        $finish;
    end

    initial begin
        #50_000_000;
        $display("\n*** TIMEOUT ***");
        $finish;
    end

endmodule
