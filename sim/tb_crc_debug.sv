/*
 * CRC Command Debug Testbench
 * Focused test to debug CRC UART output deadlock
 */

`timescale 1ns / 1ps

module tb_crc_debug;

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

    // Clock generation: 100 MHz
    always #5 EXTCLK = ~EXTCLK;

    // UART bit period: 115200 baud = 8680.56 ns
    localparam UART_BIT_PERIOD = 8680;

    // UART tasks
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

    task uart_send_string(input [8*64-1:0] str, input integer len);
        integer i;
        begin
            for (i = 0; i < len; i = i + 1) begin
                uart_send_byte(str[8*(len-1-i) +: 8]);
                #(UART_BIT_PERIOD * 2);  // Inter-character delay
            end
        end
    endtask

    // UART RX task - receive and display bytes
    reg [7:0] uart_rx_byte;
    task uart_receive_byte;
        integer i;
        begin
            // Wait for start bit
            wait(UART_TX == 0);
            #(UART_BIT_PERIOD / 2);  // Move to middle of start bit
            #UART_BIT_PERIOD;  // Move to first data bit

            // Receive 8 data bits
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_byte[i] = UART_TX;
                #UART_BIT_PERIOD;
            end

            // Stop bit
            #UART_BIT_PERIOD;

            $display("[UART RX] Received byte: 0x%02x ('%c')", uart_rx_byte,
                     (uart_rx_byte >= 32 && uart_rx_byte <= 126) ? uart_rx_byte : ".");
        end
    endtask

    // Monitor UART TX activity
    initial begin
        forever begin
            @(negedge UART_TX);
            uart_receive_byte();
        end
    end

    // Main test sequence
    initial begin
        $display("========================================");
        $display("CRC Command Debug Test");
        $display("========================================\n");

        // Initialize SRAM with known pattern for CRC test
        // Fill addresses 0x00000000 to 0x000000FF with incrementing values
        for (integer i = 0; i < 128; i = i + 1) begin
            sram_mem[2*i]   = 16'h0000 + i;      // Low word
            sram_mem[2*i+1] = 16'h0100 + i;      // High word
        end

        // Wait for reset
        #10000;
        $display("[TEST] Waiting for initial prompt...");
        #500000;  // Wait for initial prompt ">"

        //==============================================
        // TEST: CRC Command (Interactive Mode)
        //==============================================
        $display("\n[TEST] Sending CRC command: crc");
        $display("[TEST] Testing interactive mode with prompts");

        // Send "crc" command
        #(UART_BIT_PERIOD * 10);
        uart_send_string("crc", 3);
        uart_send_byte(8'h0A);  // Newline

        $display("[TEST] Waiting for 'Start>' prompt...");
        #500000;  // Wait for Start> prompt

        // Send start address "00000000"
        $display("[TEST] Sending start address: 00000000");
        uart_send_string("00000000", 8);
        uart_send_byte(8'h0A);  // Newline

        $display("[TEST] Waiting for 'End>' prompt...");
        #500000;  // Wait for End> prompt

        // Send end address "00000100" (256 bytes)
        $display("[TEST] Sending end address: 00000100");
        uart_send_string("00000100", 8);
        uart_send_byte(8'h0A);  // Newline

        $display("[TEST] CRC command sent, waiting for CRC calculation and output...");

        // Wait for CRC calculation and UART output
        #5000000;  // 5ms should be plenty

        $display("\n========================================");
        $display("CRC Test Complete");
        $display("========================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #10_000_000;  // 10ms timeout
        $display("\n*** TIMEOUT ***");
        $display("CRC command did not complete in time - possible deadlock");
        $finish;
    end

endmodule
