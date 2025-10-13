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
    output reg        mmio_ready,

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

    // Prescaler tick generation
    assign psc_tick = (psc_counter == 16'h0000);

    // All timer logic in one always block to avoid multiple drivers
    always @(posedge clk) begin
        if (!resetn) begin
            psc_counter <= 16'h0000;
            cnt_value <= 32'h00000000;
            sr_uif <= 1'b0;
            cr_enable <= 1'b0;
        end else begin
            // MMIO Write Operations (highest priority)
            if (mmio_valid && mmio_write && mmio_ready) begin
                case (mmio_addr[4:0])
                    ADDR_CR: begin
                        if (mmio_wstrb[0]) begin
                            cr_enable   <= mmio_wdata[0];
                            cr_one_shot <= mmio_wdata[1];
                            // When enabling timer, load counter with ARR
                            if (mmio_wdata[0] && !cr_enable) begin
                                cnt_value <= arr_value;
                                psc_counter <= psc_value;
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
            end else begin
                // Prescaler counter logic (only when not being written by MMIO)
                if (cr_enable) begin
                    if (psc_tick) begin
                        psc_counter <= psc_value;  // Reload prescaler

                        // Counter decrements on prescaler tick
                        if (cnt_value == 32'h00000000) begin
                            // Counter reached zero - generate update event
                            sr_uif <= 1'b1;

                            if (cr_one_shot) begin
                                // One-shot mode: Stop timer
                                cr_enable <= 1'b0;
                                cnt_value <= arr_value;  // Reload for next start
                            end else begin
                                // Continuous mode: Auto-reload and continue
                                cnt_value <= arr_value;
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
            end
        end
    end

    // MMIO Read Operations
    always @(posedge clk) begin
        if (!resetn) begin
            mmio_rdata <= 32'h00000000;
            mmio_ready <= 1'b0;
        end else begin
            mmio_ready <= mmio_valid && !mmio_ready;

            if (mmio_valid && !mmio_ready) begin
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

    // Interrupt Output
    // IRQ is high when UIF flag is set
    assign timer_irq = sr_uif;

endmodule
