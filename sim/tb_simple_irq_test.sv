// ==============================================================================
// Simple Interrupt Test Bench
// Manually triggers IRQ line and verifies firmware counter
//==============================================================================

`timescale 1ns / 1ps

module tb_simple_irq_test;

    // Clock (100MHz)
    reg clk_100mhz = 0;

    // Test control
    integer irq_trigger_count = 0;
    reg manual_irq = 0;

    // Top-level signals (matching actual port names)
    reg BUT1 = 0;
    reg BUT2 = 0;
    wire LED1;
    wire LED2;
    wire UART_TX;
    reg UART_RX = 1;

    // SRAM signals
    wire [17:0] SA;
    wire [15:0] SD;
    wire SRAM_CS_N;
    wire SRAM_OE_N;
    wire SRAM_WE_N;

    //==========================================================================
    // SRAM Behavioral Model (512KB)
    //==========================================================================

    reg [15:0] sram_mem [0:262143];  // 256K x 16-bit
    reg [15:0] sram_data_out;
    reg sram_data_oe;

    // Tri-state control
    assign SD = (sram_data_oe && !SRAM_OE_N && !SRAM_CS_N) ? sram_data_out : 16'hzzzz;

    // SRAM write logic
    always @(negedge SRAM_WE_N) begin
        if (!SRAM_CS_N) begin
            sram_mem[SA] <= SD;
        end
    end

    // SRAM read logic
    always @(*) begin
        if (!SRAM_CS_N && !SRAM_OE_N && SRAM_WE_N) begin
            sram_data_out = sram_mem[SA];
            sram_data_oe = 1'b1;
        end else begin
            sram_data_out = 16'hxxxx;
            sram_data_oe = 1'b0;
        end
    end

    // Load firmware into SRAM
    integer i;
    reg [31:0] firmware_mem [0:2047];
    integer firmware_words;

    initial begin
        // Initialize SRAM to zeros
        for (i = 0; i < 262144; i = i + 1) begin
            sram_mem[i] = 16'h0000;
        end

        // Load firmware hex file (32-bit words)
        $readmemh("../firmware/irq_counter_test_words.hex", firmware_mem);

        // Count firmware words
        firmware_words = 0;
        for (i = 0; i < 2048; i = i + 1) begin
            if (firmware_mem[i] !== 32'hxxxxxxxx && firmware_mem[i] !== 32'h00000000) begin
                firmware_words = i + 1;
            end
        end

        $display("[SRAM] Loading firmware: %0d words from irq_counter_test_words.hex", firmware_words);

        // Copy firmware to SRAM (split into 16-bit halfwords)
        for (i = 0; i < firmware_words; i = i + 1) begin
            sram_mem[i*2]     = firmware_mem[i][15:0];   // Lower halfword
            sram_mem[i*2 + 1] = firmware_mem[i][31:16];  // Upper halfword
        end

        $display("[SRAM] Firmware loaded successfully");
    end

    // Instantiate DUT
    ice40_picorv32_top dut (
        .EXTCLK(clk_100mhz),
        .BUT1(BUT1),
        .BUT2(BUT2),
        .LED1(LED1),
        .LED2(LED2),
        .UART_TX(UART_TX),
        .UART_RX(UART_RX),
        .SA(SA),
        .SD(SD),
        .SRAM_CS_N(SRAM_CS_N),
        .SRAM_OE_N(SRAM_OE_N),
        .SRAM_WE_N(SRAM_WE_N)
    );

    // CPU monitoring signals
    wire [31:0] cpu_pc;
    wire cpu_mem_valid;
    wire cpu_mem_ready;
    wire cpu_mem_instr;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [3:0] cpu_mem_wstrb;
    wire [31:0] cpu_mem_rdata;
    wire [31:0] cpu_irq;
    wire cpu_irq_active;

    assign cpu_pc = dut.cpu.reg_pc;
    assign cpu_mem_valid = dut.cpu.mem_valid;
    assign cpu_mem_ready = dut.cpu_mem_ready;
    assign cpu_mem_instr = dut.cpu.mem_instr;
    assign cpu_mem_addr = dut.cpu.mem_addr;
    assign cpu_mem_wdata = dut.cpu.mem_wdata;
    assign cpu_mem_wstrb = dut.cpu.mem_wstrb;
    assign cpu_mem_rdata = dut.cpu_mem_rdata;
    assign cpu_irq = dut.cpu.irq;
    assign cpu_irq_active = |cpu_irq;  // Any IRQ bit set

    // Monitor CPU execution
    reg [31:0] last_pc;
    integer stuck_count;

    initial begin
        last_pc = 0;
        stuck_count = 0;
    end

    // Monitor IRQ signal changes
    reg last_timer_irq;
    reg last_cpu_irq_active;

    initial begin
        last_timer_irq = 0;
        last_cpu_irq_active = 0;
    end

    always @(posedge dut.clk) begin
        if (dut.timer_irq != last_timer_irq) begin
            $display("[%0t] IRQ SIGNAL: timer_irq=%b, cpu_irq=0x%08x", $time, dut.timer_irq, cpu_irq);
            last_timer_irq <= dut.timer_irq;
        end

        if (cpu_irq_active != last_cpu_irq_active) begin
            $display("[%0t] IRQ STATE: cpu_irq_active=%b", $time, cpu_irq_active);
            last_cpu_irq_active <= cpu_irq_active;
        end

        // Monitor writes to interrupt_count address (0xe4)
        if (cpu_mem_valid && cpu_mem_ready && |cpu_mem_wstrb && cpu_mem_addr == 32'h000000e4) begin
            $display("[%0t] *** WRITE TO COUNTER @ 0x%08x = 0x%08x ***", $time, cpu_mem_addr, cpu_mem_wdata);
        end
    end

    always @(posedge dut.clk) begin
        if (dut.cpu.resetn) begin
            // Check if PC is changing
            if (cpu_pc == last_pc && cpu_mem_valid && !cpu_mem_ready) begin
                stuck_count <= stuck_count + 1;
                if (stuck_count > 1000) begin
                    $display("[%0t] WARNING: CPU stuck at PC=0x%08x for %0d cycles", $time, cpu_pc, stuck_count);
                    stuck_count <= 0;
                end
            end else begin
                stuck_count <= 0;
            end

            // Monitor PC - print IRQ handler entry and selective addresses
            if (cpu_mem_valid && cpu_mem_ready && cpu_mem_instr) begin
                if (cpu_pc == 32'h00000010) begin
                    $display("[%0t] *** IRQ HANDLER ENTRY *** PC=0x%08x", $time, cpu_pc);
                end else if (cpu_pc == 32'h00000034) begin
                    $display("[%0t] *** CALLING irq_handler() *** PC=0x%08x", $time, cpu_pc);
                end else if (cpu_pc == 32'h00000090) begin
                    $display("[%0t] *** INSIDE irq_handler() *** PC=0x%08x INSTR=0x%08x", $time, cpu_pc, cpu_mem_rdata);
                end else if (cpu_pc == 32'h00000038) begin
                    $display("[%0t] *** RETURNED from irq_handler() *** PC=0x%08x", $time, cpu_pc);
                end else if (cpu_pc == 32'h00000058) begin
                    $display("[%0t] *** EXECUTING retirq *** PC=0x%08x", $time, cpu_pc);
                end else if (cpu_pc[7:0] == 8'h00 || cpu_pc[11:0] == 12'hb8) begin
                    $display("[%0t] PC=0x%08x INSTR=0x%08x", $time, cpu_pc, cpu_mem_rdata);
                end
            end

            last_pc <= cpu_pc;
        end
    end

    // Clock generation (100 MHz)
    always #5 clk_100mhz = ~clk_100mhz;

    // Test sequence
    initial begin
        $display("========================================");
        $display("Simple Interrupt Counter Test");
        $display("========================================");
        $display("");

        // Wait for reset to complete and firmware to initialize
        #100000;  // 100us
        $display("[%0t] Starting IRQ triggers", $time);

        // Trigger 10 interrupts
        // Space them 25us apart since each handler takes ~19-20us
        repeat (10) begin
            #25000;  // Wait 25us between interrupts (enough for handler to complete)

            // Pulse IRQ line on clock edge - single clock cycle (10ns)
            @(posedge dut.clk);  // Sync to clock edge
            force dut.timer_irq = 1;
            $display("[%0t] IRQ trigger #%0d", $time, irq_trigger_count + 1);
            @(posedge dut.clk);  // Hold for one clock cycle
            force dut.timer_irq = 0;

            irq_trigger_count++;
        end

        // Wait longer for all interrupt handlers to complete
        // Each interrupt takes ~20us, so 10 interrupts need ~200us
        #200000;

        // Read interrupt_count directly from address 0xe4
        // Address 0xe4 (228 bytes) = halfword addresses 0x72 and 0x73
        $display("");
        $display("========================================");
        $display("Test Results");
        $display("========================================");
        $display("Testbench IRQ triggers: %0d", irq_trigger_count);
        $display("Firmware counter value: %0d", {sram_mem[18'h0073], sram_mem[18'h0072]});
        $display("");

        // Verify
        if ({sram_mem[18'h0073], sram_mem[18'h0072]} == irq_trigger_count) begin
            $display("PASS: Interrupt counts match!");
        end else begin
            $display("FAIL: Interrupt count mismatch!");
            $display("  Expected: %0d", irq_trigger_count);
            $display("  Got:      %0d", {sram_mem[18'h0073], sram_mem[18'h0072]});
        end

        $display("");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #1000000;  // 1ms timeout
        $display("");
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
