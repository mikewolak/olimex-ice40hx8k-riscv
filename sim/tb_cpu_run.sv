/*
 * CPU Run Test - Full system test with firmware
 * Tests that 'r' command properly transfers control to PicoRV32
 */

`timescale 1ns / 1ps

module tb_cpu_run;

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

    // Load firmware into SRAM
    task load_firmware;
        integer word_addr, byte_addr, i;
        reg [7:0] byte_mem [0:524287];  // 512KB byte array
        begin
            $display("[TEST] Loading firmware from led_blink.hex...");

            // Initialize byte memory to zero
            for (i = 0; i < 524288; i = i + 1) byte_mem[i] = 8'h00;

            // Load byte-oriented hex file
            $readmemh("firmware/led_blink.hex", byte_mem);

            // Pack bytes into 16-bit words (little-endian)
            // RISC-V is little-endian: word = {byte[addr+1], byte[addr]}
            for (word_addr = 0; word_addr < 262144; word_addr = word_addr + 1) begin
                byte_addr = word_addr * 2;
                sram_mem[word_addr] = {byte_mem[byte_addr + 1], byte_mem[byte_addr]};
            end

            $display("[TEST] First 8 words of SRAM:");
            for (word_addr = 0; word_addr < 8; word_addr = word_addr + 1) begin
                $display("[TEST]   SRAM[0x%05x] = 0x%04x", word_addr, sram_mem[word_addr]);
            end

            // Reconstruct first instruction for verification
            $display("[TEST] First instruction = 0x%04x%04x", sram_mem[1], sram_mem[0]);
        end
    endtask

    // Monitor LED changes
    reg prev_led1 = 0;
    reg prev_led2 = 0;
    integer led1_toggles = 0;
    integer led2_toggles = 0;

    always @(LED1) begin
        if (LED1 !== prev_led1) begin
            led1_toggles = led1_toggles + 1;
            $display("[LED] LED1 changed to %b at time %t", LED1, $time);
            prev_led1 = LED1;
        end
    end

    always @(LED2) begin
        if (LED2 !== prev_led2) begin
            led2_toggles = led2_toggles + 1;
            $display("[LED] LED2 changed to %b at time %t", LED2, $time);
            prev_led2 = LED2;
        end
    end

    // Monitor CPU memory accesses to MMIO
    always @(posedge EXTCLK) begin
        if (dut.app_mode && dut.cpu_mem_valid && dut.cpu_mem_ready) begin
            if (dut.cpu_mem_wstrb != 0) begin
                // Write access
                if (dut.cpu_mem_addr == 32'h80000000) begin
                    $display("[MMIO] CPU writing to UART TX: 0x%02x ('%c')",
                             dut.cpu_mem_wdata[7:0],
                             (dut.cpu_mem_wdata[7:0] >= 32 && dut.cpu_mem_wdata[7:0] <= 126) ? dut.cpu_mem_wdata[7:0] : ".");
                end else if (dut.cpu_mem_addr == 32'h80000008) begin
                    $display("[MMIO] CPU writing to LEDs: 0x%08x", dut.cpu_mem_wdata);
                end
            end
        end
    end

    // Main test
    initial begin
        $display("========================================");
        $display("CPU Run Test - Full System");
        $display("========================================\n");

        // Load firmware
        load_firmware();

        #10000;
        $display("\n[TEST] Waiting for shell prompt...");
        #500000;

        $display("\n[TEST] Sending 'r' command to release CPU");
        #(UART_BIT_PERIOD * 10);
        uart_send_byte(8'h72);  // 'r'
        uart_send_byte(8'h0A);  // newline

        $display("[TEST] Waiting for 'RELEASING CPU' message...");
        #2000000;

        $display("\n[TEST] Checking mode switch...");
        $display("  app_mode = %b", dut.app_mode);
        $display("  cpu_resetn = %b", dut.cpu_resetn);
        $display("  shell_mode_switch = %b", dut.shell_mode_switch);

        if (dut.app_mode == 1'b1) begin
            $display("[PASS] System switched to APP mode");
        end else begin
            $display("[FAIL] System still in SHELL mode");
        end

        if (dut.cpu_resetn == 1'b1) begin
            $display("[PASS] CPU is out of reset");
        end else begin
            $display("[FAIL] CPU still in reset");
        end

        // Let CPU execute firmware for extended time to see multiple toggles
        $display("\n[TEST] Running CPU firmware for 2 seconds to observe full LED blink cycles...\n");

        // Status updates every 200ms
        #200000000;
        $display("[TEST] t=200ms: LED1=%d LED2=%d, LED1_toggles=%d LED2_toggles=%d, UART_bytes=%d, PC=0x%08x",
                 LED1, LED2, led1_toggles, led2_toggles, uart_rx_count, dut.cpu.reg_pc);

        #200000000;
        $display("[TEST] t=400ms: LED1=%d LED2=%d, LED1_toggles=%d LED2_toggles=%d, UART_bytes=%d, PC=0x%08x",
                 LED1, LED2, led1_toggles, led2_toggles, uart_rx_count, dut.cpu.reg_pc);

        #200000000;
        $display("[TEST] t=600ms: LED1=%d LED2=%d, LED1_toggles=%d LED2_toggles=%d, UART_bytes=%d, PC=0x%08x",
                 LED1, LED2, led1_toggles, led2_toggles, uart_rx_count, dut.cpu.reg_pc);

        #200000000;
        $display("[TEST] t=800ms: LED1=%d LED2=%d, LED1_toggles=%d LED2_toggles=%d, UART_bytes=%d, PC=0x%08x",
                 LED1, LED2, led1_toggles, led2_toggles, uart_rx_count, dut.cpu.reg_pc);

        #200000000;
        $display("[TEST] t=1.0s: LED1=%d LED2=%d, LED1_toggles=%d LED2_toggles=%d, UART_bytes=%d, PC=0x%08x",
                 LED1, LED2, led1_toggles, led2_toggles, uart_rx_count, dut.cpu.reg_pc);

        #200000000;
        $display("[TEST] t=1.2s: LED1=%d LED2=%d, LED1_toggles=%d LED2_toggles=%d, UART_bytes=%d, PC=0x%08x",
                 LED1, LED2, led1_toggles, led2_toggles, uart_rx_count, dut.cpu.reg_pc);

        #200000000;
        $display("[TEST] t=1.4s: LED1=%d LED2=%d, LED1_toggles=%d LED2_toggles=%d, UART_bytes=%d, PC=0x%08x",
                 LED1, LED2, led1_toggles, led2_toggles, uart_rx_count, dut.cpu.reg_pc);

        #200000000;
        $display("[TEST] t=1.6s: LED1=%d LED2=%d, LED1_toggles=%d LED2_toggles=%d, UART_bytes=%d, PC=0x%08x",
                 LED1, LED2, led1_toggles, led2_toggles, uart_rx_count, dut.cpu.reg_pc);

        #200000000;
        $display("[TEST] t=1.8s: LED1=%d LED2=%d, LED1_toggles=%d LED2_toggles=%d, UART_bytes=%d, PC=0x%08x",
                 LED1, LED2, led1_toggles, led2_toggles, uart_rx_count, dut.cpu.reg_pc);

        #200000000;
        $display("[TEST] t=2.0s: LED1=%d LED2=%d, LED1_toggles=%d LED2_toggles=%d, UART_bytes=%d, PC=0x%08x",
                 LED1, LED2, led1_toggles, led2_toggles, uart_rx_count, dut.cpu.reg_pc);

        $display("\n========================================");
        $display("FINAL TEST RESULTS");
        $display("========================================");
        $display("  CPU PC = 0x%08x", dut.cpu.reg_pc);
        $display("  LED1 state = %b, toggles = %d", LED1, led1_toggles);
        $display("  LED2 state = %b, toggles = %d", LED2, led2_toggles);
        $display("  Total UART bytes = %d", uart_rx_count);

        // Decode UART message
        $display("\n[UART] Received message:");
        for (integer i = 0; i < uart_rx_count; i = i + 1) begin
            if (uart_rx_buffer[i] >= 32 && uart_rx_buffer[i] <= 126)
                $write("%c", uart_rx_buffer[i]);
            else if (uart_rx_buffer[i] == 8'h0D)
                $write("\\r");
            else if (uart_rx_buffer[i] == 8'h0A)
                $write("\\n");
            else
                $write("[0x%02x]", uart_rx_buffer[i]);
        end
        $display("");

        // Pass/Fail criteria
        $display("\n========================================");
        $display("TEST ANALYSIS");
        $display("========================================");

        if (led1_toggles >= 3 && led2_toggles >= 3) begin
            $display("[PASS] Both LEDs toggling multiple times (LED1=%d, LED2=%d)", led1_toggles, led2_toggles);
        end else if (led1_toggles > 0 || led2_toggles > 0) begin
            $display("[PARTIAL] Some LED activity but not both alternating (LED1=%d, LED2=%d)", led1_toggles, led2_toggles);
        end else begin
            $display("[FAIL] No LED activity detected");
        end

        if (uart_rx_count > 100) begin
            $display("[PASS] CPU sent substantial UART data (%d bytes)", uart_rx_count);
        end else if (uart_rx_count > 46) begin
            $display("[PARTIAL] CPU sent some UART data (%d bytes)", uart_rx_count);
        end else begin
            $display("[FAIL] No UART output from CPU detected");
        end

        $display("\n========================================");
        $display("CPU Run Test Complete - 2 seconds elapsed");
        $display("========================================\n");

        $finish;
    end

    initial begin
        #2_500_000_000;
        $display("\n*** TIMEOUT after 2.5 seconds ***");
        $finish;
    end

endmodule
