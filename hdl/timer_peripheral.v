//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// timer_peripheral.v - STM32-style 32-bit Timer with Interrupt
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module timer_peripheral (
    input wire clk,              // System clock (50 MHz)
    input wire resetn,

    // MMIO Interface
    input wire        mmio_valid,
    input wire        mmio_write,
    input wire [31:0] mmio_addr,
    input wire [31:0] mmio_wdata,
    input wire [ 3:0] mmio_wstrb,
    output reg [31:0] mmio_rdata,
    output wire       mmio_ready,    // Changed to wire for combinational response

    // Interrupt Output
    output wire       timer_irq
);

    // =========================================================================
    // Register Map (STM32-style)
    // Base: 0x80000020
    // =========================================================================
    // +0x00: CR  (Control Register)     - [0]=Enable, [1]=One-shot mode
    // +0x04: SR  (Status Register)      - [0]=UIF (Update Interrupt Flag)
    // +0x08: PSC (Prescaler)            - 16-bit clock divider (0-65535)
    // +0x0C: ARR (Auto-Reload Register) - 32-bit reload value
    // +0x10: CNT (Counter)              - 32-bit current count (read-only)
    // =========================================================================

    localparam ADDR_CR  = 5'h00;
    localparam ADDR_SR  = 5'h04;
    localparam ADDR_PSC = 5'h08;
    localparam ADDR_ARR = 5'h0C;
    localparam ADDR_CNT = 5'h10;

    // Timer Registers
    reg        cr_enable;       // CR[0]: Timer enable
    reg        cr_one_shot;     // CR[1]: One-shot mode (vs continuous)
    reg        sr_uif;          // SR[0]: Update interrupt flag
    reg [15:0] psc_value;       // PSC: Prescaler value (0-65535)
    reg [31:0] arr_value;       // ARR: Auto-reload value
    reg [31:0] cnt_value;       // CNT: Current counter value

    // Prescaler counter
    reg [15:0] psc_counter;
    wire       psc_tick;        // Prescaler generates tick when it reaches 0

    // IRQ pulse generation
    reg        irq_pulse;       // Single-cycle IRQ pulse

    // synthesis translate_off
    integer debug_cycle_count;
    integer debug_mmio_cycles;
    integer debug_count_cycles;
    integer debug_decrements;
    integer debug_psc_ticks;
    reg [15:0] last_psc_counter;
    reg [31:0] last_cnt_value;
    // synthesis translate_on

    // Prescaler tick generation
    assign psc_tick = (psc_counter == 16'h0000);

    // MMIO ready - combinational response (same cycle)
    assign mmio_ready = mmio_valid;

    // Interrupt Output - single-cycle pulse (clock-edge synchronized)
    assign timer_irq = irq_pulse;

    // All timer logic in one always block
    always @(posedge clk) begin
        if (!resetn) begin
            // Reset all registers
            mmio_rdata <= 32'h00000000;
            psc_counter <= 16'h0000;
            psc_value <= 16'h0000;
            arr_value <= 32'h00000000;
            cnt_value <= 32'h00000000;
            sr_uif <= 1'b0;
            cr_enable <= 1'b0;
            cr_one_shot <= 1'b0;
            irq_pulse <= 1'b0;
            // synthesis translate_off
            debug_cycle_count = 0;
            debug_mmio_cycles = 0;
            debug_count_cycles = 0;
            debug_decrements = 0;
            debug_psc_ticks = 0;
            last_psc_counter = 16'h0000;
            last_cnt_value = 32'h00000000;
            // synthesis translate_on
        end else begin
            // synthesis translate_off
            debug_cycle_count = debug_cycle_count + 1;
            if (mmio_valid) begin
                debug_mmio_cycles = debug_mmio_cycles + 1;
            end
            if (cr_enable) begin
                debug_count_cycles = debug_count_cycles + 1;
            end
            if (cr_enable) begin
                // Track prescaler ticks
                if (psc_tick) begin
                    debug_psc_ticks = debug_psc_ticks + 1;
                end
                // Track counter decrements
                if (cnt_value != last_cnt_value && cnt_value < last_cnt_value) begin
                    debug_decrements = debug_decrements + 1;
                end
                last_cnt_value = cnt_value;
                last_psc_counter = psc_counter;
            end

            if (cr_enable && (debug_cycle_count == 1000 || debug_cycle_count == 10000 || debug_cycle_count == 100000)) begin
                $display("[TIMER_PERIPH] After %0d cycles: psc_counter=%0d cnt_value=%0d | MMIO: %0d cycles (%.1f%%) | Counting: %0d cycles (%.1f%%)",
                         debug_cycle_count, psc_counter, cnt_value,
                         debug_mmio_cycles, (debug_mmio_cycles * 100.0) / debug_cycle_count,
                         debug_count_cycles, (debug_count_cycles * 100.0) / debug_cycle_count);
                $display("[TIMER_PERIPH]   PSC ticks: %0d (expected: ~%0d) | Counter decrements: %0d (expected: ~%0d)",
                         debug_psc_ticks, debug_count_cycles / 10, debug_decrements, debug_psc_ticks);
            end
            // synthesis translate_on
            // Default: Clear IRQ pulse (single-cycle pulse)
            irq_pulse <= 1'b0;

            // Timer counting logic - runs EVERY cycle when enabled (independent of MMIO)
            if (cr_enable) begin
                if (psc_tick) begin
                    psc_counter <= psc_value;  // Reload prescaler

                    // Counter decrements on prescaler tick
                    if (cnt_value == 32'h00000000) begin
                        // Counter reached zero - generate single-cycle IRQ pulse
                        irq_pulse <= 1'b1;
                        sr_uif <= 1'b1;
                        // synthesis translate_off
                        $display("[%0t] [TIMER_PERIPH] Counter reached 0 - generating IRQ pulse", $time);
                        $display("[%0t] [TIMER_PERIPH]   cr_enable=%b cr_one_shot=%b arr_value=%0d",
                                 $time, cr_enable, cr_one_shot, arr_value);
                        // synthesis translate_on

                        if (cr_one_shot) begin
                            // One-shot mode: Stop timer
                            cr_enable <= 1'b0;
                            cnt_value <= arr_value;  // Reload for next start
                        end else begin
                            // Continuous mode: Auto-reload and continue
                            cnt_value <= arr_value;
                            // synthesis translate_off
                            $display("[%0t] [TIMER_PERIPH]   Reloading: cnt_value <= %0d (continuous mode)",
                                     $time, arr_value);
                            // synthesis translate_on
                        end
                    end else begin
                        // Decrement counter
                        cnt_value <= cnt_value - 32'd1;
                    end
                end else begin
                    // Decrement prescaler counter
                    psc_counter <= psc_counter - 16'd1;
                end
            end

            // MMIO handling - can override timer updates if needed (e.g., during enable)
            if (mmio_valid && mmio_write) begin
                // synthesis translate_off
                $display("[TIMER] WRITE: addr=0x%08x data=0x%08x", mmio_addr, mmio_wdata);
                // synthesis translate_on

                case (mmio_addr[4:0])
                    ADDR_CR: begin
                        if (mmio_wstrb[0]) begin
                            cr_enable   <= mmio_wdata[0];
                            cr_one_shot <= mmio_wdata[1];
                            // When enabling timer, load counter with ARR
                            if (mmio_wdata[0] && !cr_enable) begin
                                cnt_value <= arr_value;
                                psc_counter <= psc_value;
                                // synthesis translate_off
                                $display("[TIMER_PERIPH] Timer enabled: cnt=%0d psc_counter=%0d arr=%0d psc_value=%0d",
                                         arr_value, psc_value, arr_value, psc_value);
                                // synthesis translate_on
                            end
                        end
                    end

                    ADDR_SR: begin
                        if (mmio_wstrb[0]) begin
                            // Write 1 to clear interrupt flag
                            if (mmio_wdata[0])
                                sr_uif <= 1'b0;
                        end
                    end

                    ADDR_PSC: begin
                        if (mmio_wstrb[0]) psc_value[7:0]  <= mmio_wdata[7:0];
                        if (mmio_wstrb[1]) psc_value[15:8] <= mmio_wdata[15:8];
                    end

                    ADDR_ARR: begin
                        if (mmio_wstrb[0]) arr_value[7:0]   <= mmio_wdata[7:0];
                        if (mmio_wstrb[1]) arr_value[15:8]  <= mmio_wdata[15:8];
                        if (mmio_wstrb[2]) arr_value[23:16] <= mmio_wdata[23:16];
                        if (mmio_wstrb[3]) arr_value[31:24] <= mmio_wdata[31:24];
                    end

                    // CNT is read-only, writes ignored
                endcase
            end

            // MMIO reads (separate combinational assignment)
            if (mmio_valid) begin
                case (mmio_addr[4:0])
                    ADDR_CR:  mmio_rdata <= {30'h0, cr_one_shot, cr_enable};
                    ADDR_SR:  mmio_rdata <= {31'h0, sr_uif};
                    ADDR_PSC: mmio_rdata <= {16'h0000, psc_value};
                    ADDR_ARR: mmio_rdata <= arr_value;
                    ADDR_CNT: mmio_rdata <= cnt_value;
                    default:  mmio_rdata <= 32'h00000000;
                endcase
            end
        end
    end

endmodule
