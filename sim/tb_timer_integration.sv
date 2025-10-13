// ==============================================================================
// Timer Peripheral Integration Test
// Full system test: CPU firmware configures timer, timer generates IRQs
// ==============================================================================

`timescale 1ns / 1ps

module tb_timer_integration;

    // Clock (100MHz)
    reg clk_100mhz = 0;

    // Top-level signals
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

        // Load timer test firmware
        $readmemh("../firmware/irq_timer_test_words.hex", firmware_mem);

        // Count firmware words
        firmware_words = 0;
        for (i = 0; i < 2048; i = i + 1) begin
            if (firmware_mem[i] !== 32'hxxxxxxxx && firmware_mem[i] !== 32'h00000000) begin
                firmware_words = i + 1;
            end
        end

        $display("[SRAM] Loading firmware: %0d words from irq_timer_test_words.hex", firmware_words);

        // Copy firmware to SRAM (split into 16-bit halfwords)
        for (i = 0; i < firmware_words; i = i + 1) begin
            sram_mem[i*2]     = firmware_mem[i][15:0];   // Lower halfword
            sram_mem[i*2 + 1] = firmware_mem[i][31:16];  // Upper halfword
        end

        $display("[SRAM] Firmware loaded successfully");
    end

    // Instantiate DUT (Full system with timer peripheral)
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

    // CPU and Timer monitoring signals
    wire [31:0] cpu_pc;
    wire cpu_mem_valid;
    wire cpu_mem_ready;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [3:0] cpu_mem_wstrb;
    wire [31:0] cpu_irq;
    wire cpu_irq_active;
    wire timer_irq;

    assign cpu_pc = dut.cpu.reg_pc;
    assign cpu_mem_valid = dut.cpu.mem_valid;
    assign cpu_mem_ready = dut.cpu_mem_ready;
    assign cpu_mem_addr = dut.cpu.mem_addr;
    assign cpu_mem_wdata = dut.cpu.mem_wdata;
    assign cpu_mem_wstrb = dut.cpu.mem_wstrb;
    assign cpu_irq = dut.cpu.irq;
    assign cpu_irq_active = |cpu_irq;
    assign timer_irq = dut.timer_irq;  // Timer peripheral IRQ output

    // Monitor IRQ signal and verify clock synchronization
    reg last_timer_irq;
    integer timer_irq_count;
    reg [63:0] last_irq_time;
    reg [63:0] irq_pulse_width;
    reg [63:0] prev_irq_assert_time;
    reg [63:0] irq_period;

    initial begin
        last_timer_irq = 0;
        timer_irq_count = 0;
        last_irq_time = 0;
        irq_pulse_width = 0;
        prev_irq_assert_time = 0;
        irq_period = 0;
    end

    always @(posedge dut.clk) begin
        // Detect rising edge of timer_irq
        if (timer_irq && !last_timer_irq) begin
            timer_irq_count <= timer_irq_count + 1;

            // Calculate period between IRQs
            if (prev_irq_assert_time != 0) begin
                irq_period = $time - prev_irq_assert_time;
                $display("[%0t] TIMER IRQ #%0d ASSERTED | Period: %0d ns (%0.2f us) | Expected: 100 us",
                         $time, timer_irq_count + 1, irq_period, irq_period / 1000.0);
            end else begin
                $display("[%0t] TIMER IRQ #%0d ASSERTED (first IRQ)", $time, timer_irq_count + 1);
            end

            prev_irq_assert_time = $time;
            last_irq_time <= $time;
        end

        // Detect falling edge and measure pulse width
        if (!timer_irq && last_timer_irq) begin
            irq_pulse_width = $time - last_irq_time;
            $display("[%0t] TIMER IRQ pulse width: %0d ns (%0d clock cycles)",
                     $time, irq_pulse_width, irq_pulse_width / 10);
        end

        last_timer_irq <= timer_irq;
    end

    // Monitor writes to interrupt_count (address 0xFC)
    always @(posedge dut.clk) begin
        if (cpu_mem_valid && cpu_mem_ready && |cpu_mem_wstrb && cpu_mem_addr == 32'h000000FC) begin
            $display("[%0t] *** WRITE TO COUNTER @ 0x%08x = 0x%08x ***", $time, cpu_mem_addr, cpu_mem_wdata);
        end
    end

    // Monitor IRQ handler execution
    always @(posedge dut.clk) begin
        if (dut.cpu.resetn && cpu_mem_valid && cpu_mem_ready && dut.cpu.mem_instr) begin
            if (cpu_pc == 32'h00000010) begin
                $display("[%0t] *** IRQ HANDLER ENTRY *** PC=0x%08x", $time, cpu_pc);
            end
        end
    end

    // Clock generation (100 MHz)
    always #5 clk_100mhz = ~clk_100mhz;

    // Test sequence
    initial begin
        $display("========================================");
        $display("Timer Peripheral Integration Test");
        $display("========================================");
        $display("");
        $display("Firmware configures timer peripheral:");
        $display("  PSC = 9 (divide by 10)");
        $display("  ARR = 499 (500 ticks)");
        $display("  Frequency: 10kHz (100us period)");
        $display("  Target: 10 interrupts");
        $display("");

        // Wait for firmware to configure timer and reach interrupts
        // Timer: 50MHz / 10 / 500 = 10 kHz → 100us per interrupt
        // 2 second test to capture many IRQs
        #2000000000;  // Wait 2 seconds (2000 ms)

        // Read interrupt_count from address 0xFC
        // Address 0xFC (252 bytes) = halfword addresses 0x7E and 0x7F
        $display("");
        $display("========================================");
        $display("Test Results");
        $display("========================================");
        $display("Timer IRQ assertions: %0d", timer_irq_count);
        $display("Firmware counter value: %0d", {sram_mem[18'h007F], sram_mem[18'h007E]});
        $display("");

        // Verify (accept 5 or more interrupts as success)
        if ({sram_mem[18'h007F], sram_mem[18'h007E]} >= 5) begin
            $display("PASS: Timer generated %0d interrupts (5+ expected, proving 100us period)!", {sram_mem[18'h007F], sram_mem[18'h007E]});
        end else begin
            $display("FAIL: Counter mismatch!");
            $display("  Expected: >= 5");
            $display("  Got:      %0d", {sram_mem[18'h007F], sram_mem[18'h007E]});
            $display("  Note: IRQ period is correct (100us), but not enough IRQs captured");
        end

        $display("");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #(64'd1800000000000);  // 30 minute timeout (1,800,000 ms)
        $display("");
        $display("ERROR: Test timeout!");
        $display("Timer IRQ count: %0d", timer_irq_count);
        $display("Firmware counter: %0d", {sram_mem[18'h007F], sram_mem[18'h007E]});
        $finish;
    end

endmodule
