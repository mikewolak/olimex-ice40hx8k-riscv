//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// mmio_peripherals.v - Memory-Mapped I/O Peripherals
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module mmio_peripherals (
    input wire clk,
    input wire resetn,

    // MMIO Interface (from memory controller)
    input wire        mmio_valid,
    input wire        mmio_write,
    input wire [31:0] mmio_addr,
    input wire [31:0] mmio_wdata,
    input wire [ 3:0] mmio_wstrb,
    output reg [31:0] mmio_rdata,
    output reg        mmio_ready,

    // UART TX Interface
    output reg [ 7:0] uart_tx_data,
    output reg        uart_tx_valid,
    input wire        uart_tx_busy,

    // UART RX Interface (circular buffer)
    input wire [ 7:0] uart_rx_data,
    output reg        uart_rx_rd_en,
    input wire        uart_rx_empty,

    // LED Outputs
    output reg led1,
    output reg led2,

    // Button Inputs (pre-synchronized, active-high: 1=pressed)
    input wire but1_sync,
    input wire but2_sync,

    // Mode Controller Interface
    output reg        mode_write,
    output reg [31:0] mode_wdata,
    input wire [31:0] mode_rdata,

    // VGA Interface
    output wire [2:0] vga_r,
    output wire [2:0] vga_g,
    output wire [2:0] vga_b,
    output wire       vga_hs,
    output wire       vga_vs,

    // SRAM Interface (shared with VGA controller)
    input wire        vga_sram_valid,
    output wire       vga_sram_ready,
    input wire        vga_sram_we,
    input wire [18:0] vga_sram_addr,
    input wire [15:0] vga_sram_wdata,
    output wire [15:0] vga_sram_rdata,

    // Interrupt Outputs
    output wire timer_irq,
    output wire vga_vblank_irq,
    output wire vga_hblank_irq
);

    // Memory Map
    localparam ADDR_UART_TX_DATA   = 32'h80000000;
    localparam ADDR_UART_TX_STATUS = 32'h80000004;
    localparam ADDR_UART_RX_DATA   = 32'h80000008;
    localparam ADDR_UART_RX_STATUS = 32'h8000000C;
    localparam ADDR_LED_CONTROL    = 32'h80000010;
    localparam ADDR_MODE_CONTROL   = 32'h80000014;  // Bit 0: 0=Shell, 1=App
    localparam ADDR_BUTTON_INPUT   = 32'h80000018;  // Bit 0: BUT1, Bit 1: BUT2 (1=pressed)
    localparam ADDR_TIMER_BASE     = 32'h80000020;  // Timer registers (0x20-0x2F)
    localparam ADDR_VGA_BASE       = 32'h80000040;  // VGA registers (0x40-0x5F)

    // LED Control Register
    reg [1:0] led_reg;

    // Timer interface signals
    wire        timer_valid;
    wire        timer_ready;
    wire [31:0] timer_rdata;

    // VGA interface signals
    wire        vga_valid;
    wire        vga_ready;
    wire [31:0] vga_rdata;

    // Address decode for timer (0x80000020-0x8000002F)
    wire addr_is_timer = (mmio_addr[31:4] == 28'h8000002);

    // Address decode for VGA (0x80000040-0x8000005F)
    wire addr_is_vga = (mmio_addr[31:5] == 27'h400002);

    // Timer Peripheral Instance
    timer_peripheral timer (
        .clk(clk),
        .resetn(resetn),
        .mmio_valid(timer_valid),
        .mmio_write(mmio_write),
        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_wstrb(mmio_wstrb),
        .mmio_rdata(timer_rdata),
        .mmio_ready(timer_ready),
        .timer_irq(timer_irq)
    );

    assign timer_valid = mmio_valid && addr_is_timer;

    // VGA Controller Instance
    vga_controller vga (
        .clk(clk),
        .resetn(resetn),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs),
        .mmio_valid(vga_valid),
        .mmio_write(mmio_write),
        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_wstrb(mmio_wstrb),
        .mmio_rdata(vga_rdata),
        .mmio_ready(vga_ready),
        .sram_valid(vga_sram_valid),
        .sram_ready(vga_sram_ready),
        .sram_we(vga_sram_we),
        .sram_addr(vga_sram_addr),
        .sram_wdata(vga_sram_wdata),
        .sram_rdata(vga_sram_rdata),
        .vga_vblank_irq(vga_vblank_irq),
        .vga_hblank_irq(vga_hblank_irq)
    );

    assign vga_valid = mmio_valid && addr_is_vga;

    always @(posedge clk) begin
        if (!resetn) begin
            mmio_rdata <= 32'h0;
            mmio_ready <= 1'b0;
            uart_tx_data <= 8'h0;
            uart_tx_valid <= 1'b0;
            uart_rx_rd_en <= 1'b0;
            led_reg <= 2'b00;
            led1 <= 1'b0;
            led2 <= 1'b0;
            mode_write <= 1'b0;
            mode_wdata <= 32'h0;
        end else begin
            // Default: clear control signals
            mmio_ready <= 1'b0;
            uart_tx_valid <= 1'b0;
            uart_rx_rd_en <= 1'b0;
            mode_write <= 1'b0;

            // Update LED outputs from register
            led1 <= led_reg[0];
            led2 <= led_reg[1];

            if (mmio_valid && !mmio_ready) begin
                // Route timer addresses to timer peripheral
                if (addr_is_timer) begin
                    // synthesis translate_off
                    $display("[MMIO_PERIPH] Routing to timer: addr=0x%08x write=%b ready=%b", mmio_addr, mmio_write, timer_ready);
                    // synthesis translate_on
                    mmio_rdata <= timer_rdata;
                    mmio_ready <= timer_ready;
                end else if (addr_is_vga) begin
                    // Route VGA addresses to VGA controller
                    // synthesis translate_off
                    $display("[MMIO_PERIPH] Routing to VGA: addr=0x%08x write=%b ready=%b", mmio_addr, mmio_write, vga_ready);
                    // synthesis translate_on
                    mmio_rdata <= vga_rdata;
                    mmio_ready <= vga_ready;
                end else if (mmio_write) begin
                    // ============ WRITE OPERATIONS ============
                    case (mmio_addr)
                        ADDR_UART_TX_DATA: begin
                            // Write to UART TX
                            if (!uart_tx_busy) begin
                                uart_tx_data <= mmio_wdata[7:0];
                                uart_tx_valid <= 1'b1;
                                mmio_ready <= 1'b1;

                                // synthesis translate_off
                                $display("[MMIO] UART TX: 0x%02x ('%c')",
                                         mmio_wdata[7:0],
                                         (mmio_wdata[7:0] >= 32 && mmio_wdata[7:0] < 127) ? mmio_wdata[7:0] : 8'h2E);
                                // synthesis translate_on
                            end
                            // If busy, don't ack - CPU must retry
                        end

                        ADDR_LED_CONTROL: begin
                            // Write to LED control register
                            if (mmio_wstrb[0]) begin
                                led_reg <= mmio_wdata[1:0];
                            end
                            mmio_ready <= 1'b1;

                            // synthesis translate_off
                            $display("[MMIO] LED control: 0x%02x (LED1=%b LED2=%b)",
                                     mmio_wdata[1:0], mmio_wdata[0], mmio_wdata[1]);
                            // synthesis translate_on
                        end

                        ADDR_MODE_CONTROL: begin
                            // Write to mode control register
                            mode_write <= 1'b1;
                            mode_wdata <= mmio_wdata;
                            mmio_ready <= 1'b1;

                            // synthesis translate_off
                            $display("[MMIO] Mode control write: 0x%08x (app_mode=%b)",
                                     mmio_wdata, mmio_wdata[0]);
                            // synthesis translate_on
                        end

                        default: begin
                            // Write to invalid register - ignore
                            mmio_ready <= 1'b1;
                        end
                    endcase

                end else begin
                    // ============ READ OPERATIONS ============
                    case (mmio_addr)
                        ADDR_UART_TX_STATUS: begin
                            // Read UART TX status
                            mmio_rdata <= {31'h0, uart_tx_busy};
                            mmio_ready <= 1'b1;
                        end

                        ADDR_UART_RX_DATA: begin
                            // Read from UART RX buffer
                            if (!uart_rx_empty) begin
                                mmio_rdata <= {24'h0, uart_rx_data};
                                uart_rx_rd_en <= 1'b1;  // Advance buffer pointer
                                mmio_ready <= 1'b1;

                                // synthesis translate_off
                                $display("[MMIO] UART RX: 0x%02x ('%c')",
                                         uart_rx_data,
                                         (uart_rx_data >= 32 && uart_rx_data < 127) ? uart_rx_data : 8'h2E);
                                // synthesis translate_on
                            end else begin
                                // Buffer empty - return 0
                                mmio_rdata <= 32'h0;
                                mmio_ready <= 1'b1;
                            end
                        end

                        ADDR_UART_RX_STATUS: begin
                            // Read UART RX status
                            mmio_rdata <= {31'h0, ~uart_rx_empty};
                            mmio_ready <= 1'b1;

                            // synthesis translate_off
                            $display("[MMIO] UART RX STATUS: empty=%b, returning %b", uart_rx_empty, ~uart_rx_empty);
                            // synthesis translate_on
                        end

                        ADDR_LED_CONTROL: begin
                            // Read LED control register
                            mmio_rdata <= {30'h0, led_reg};
                            mmio_ready <= 1'b1;
                        end

                        ADDR_MODE_CONTROL: begin
                            // Read mode control register
                            mmio_rdata <= mode_rdata;
                            mmio_ready <= 1'b1;
                        end

                        ADDR_BUTTON_INPUT: begin
                            // Read button input register (pre-synchronized, active-high)
                            mmio_rdata <= {30'h0, but2_sync, but1_sync};
                            mmio_ready <= 1'b1;
                        end

                        default: begin
                            // Read from invalid register - return 0
                            mmio_rdata <= 32'h0;
                            mmio_ready <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end

endmodule
