/*
 * 'r' Command Test - CPU Release
 */

`timescale 1ns / 1ps

module tb_r_command;

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

    task uart_send_string(input [8*64-1:0] str, input integer len);
        integer i;
        begin
            for (i = 0; i < len; i = i + 1) begin
                uart_send_byte(str[8*(len-1-i) +: 8]);
                #(UART_BIT_PERIOD * 2);
            end
        end
    endtask

    // UART RX
    reg [7:0] uart_rx_byte;
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
            $display("[UART RX] 0x%02x ('%c')", uart_rx_byte,
                     (uart_rx_byte >= 32 && uart_rx_byte <= 126) ? uart_rx_byte : ".");
        end
    endtask

    initial begin
        forever begin
            @(negedge UART_TX);
            uart_receive_byte();
        end
    end

    // Main test
    initial begin
        $display("========================================");
        $display("'r' Command Test - CPU Release");
        $display("========================================\n");

        // Initialize SRAM with test instruction at address 0
        // Load a simple instruction: 0x12345678
        sram_mem[0] = 16'h5678;  // Low word
        sram_mem[1] = 16'h1234;  // High word

        #10000;
        $display("[TEST] Waiting for prompt...");
        #500000;

        $display("\n[TEST] Sending 'r' command to release CPU");
        #(UART_BIT_PERIOD * 10);
        uart_send_byte(8'h72);  // 'r'
        uart_send_byte(8'h0A);  // newline

        $display("[TEST] Waiting for CPU release message...");
        #2000000;

        $display("\n[TEST] Checking CPU reset signals...");
        $display("  global_resetn = %b", dut.global_resetn);
        $display("  cpu_reset_from_loader = %b", dut.cpu_reset_from_loader);
        $display("  cpu_reset_from_shell = %b", dut.cpu_reset_from_shell);
        $display("  cpu_resetn = %b", dut.cpu_resetn);
        $display("  shell_cpu_run = %b", dut.shell_cpu_run);

        if (dut.cpu_resetn == 1'b1) begin
            $display("[PASS] CPU is out of reset");
        end else begin
            $display("[FAIL] CPU still in reset");
            if (dut.cpu_reset_from_loader) $display("  -> Held by firmware_loader");
            if (dut.cpu_reset_from_shell) $display("  -> Held by shell");
        end

        $display("\n========================================");
        $display("'r' Command Test Complete");
        $display("========================================\n");

        $finish;
    end

    initial begin
        #10_000_000;
        $display("\n*** TIMEOUT ***");
        $finish;
    end

endmodule
