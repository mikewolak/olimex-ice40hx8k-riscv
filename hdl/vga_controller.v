//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// vga_controller.v - VGA Controller with SRAM Framebuffer
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module vga_controller (
    input wire clk,              // System clock (50 MHz)
    input wire resetn,

    // VGA Output Signals
    output wire [2:0] vga_r,     // Red (3-bit)
    output wire [2:0] vga_g,     // Green (3-bit)
    output wire [2:0] vga_b,     // Blue (2-bit, we'll use 3 for symmetry)
    output wire vga_hs,          // Horizontal sync
    output wire vga_vs,          // Vertical sync

    // MMIO Interface
    input wire        mmio_valid,
    input wire        mmio_write,
    input wire [31:0] mmio_addr,
    input wire [31:0] mmio_wdata,
    input wire [ 3:0] mmio_wstrb,
    output reg [31:0] mmio_rdata,
    output reg        mmio_ready,

    // SRAM Interface (for framebuffer access)
    output reg        sram_valid,
    input wire        sram_ready,
    output reg        sram_we,
    output reg [18:0] sram_addr,
    output reg [15:0] sram_wdata,
    input wire [15:0] sram_rdata,

    // Interrupt Output
    output reg        vga_vblank_irq,
    output reg        vga_hblank_irq
);

    //==========================================================================
    // VGA Timing Constants (640×480 @ 60Hz, 25.175 MHz pixel clock)
    //==========================================================================
    // We'll use 25MHz (50MHz/2) which is close enough

    // Horizontal timing (pixels)
    localparam H_VISIBLE   = 640;
    localparam H_FRONT     = 16;
    localparam H_SYNC      = 96;
    localparam H_BACK      = 48;
    localparam H_TOTAL     = 800;  // 640 + 16 + 96 + 48

    // Vertical timing (lines)
    localparam V_VISIBLE   = 480;
    localparam V_FRONT     = 10;
    localparam V_SYNC      = 2;
    localparam V_BACK      = 33;
    localparam V_TOTAL     = 525;  // 480 + 10 + 2 + 33

    // Framebuffer size (320×240 @ 8-bit color)
    localparam FB_WIDTH    = 320;
    localparam FB_HEIGHT   = 240;

    //==========================================================================
    // MMIO Register Map
    //==========================================================================
    localparam ADDR_VGA_CTRL      = 32'h80000040;
    localparam ADDR_VGA_STATUS    = 32'h80000044;
    localparam ADDR_VGA_FB_ADDR   = 32'h80000048;
    localparam ADDR_VGA_IRQ_MASK  = 32'h8000004C;
    localparam ADDR_VGA_IRQ_CLEAR = 32'h80000050;

    //==========================================================================
    // Clock Generation (25MHz from 50MHz)
    //==========================================================================
    reg clk_25mhz = 0;
    always @(posedge clk) begin
        if (!resetn)
            clk_25mhz <= 0;
        else
            clk_25mhz <= ~clk_25mhz;
    end

    //==========================================================================
    // VGA Timing Counters
    //==========================================================================
    reg [9:0] h_counter = 0;  // 0-799
    reg [9:0] v_counter = 0;  // 0-524

    // Sync generation
    wire h_sync = (h_counter >= (H_VISIBLE + H_FRONT)) &&
                  (h_counter < (H_VISIBLE + H_FRONT + H_SYNC));
    wire v_sync = (v_counter >= (V_VISIBLE + V_FRONT)) &&
                  (v_counter < (V_VISIBLE + V_FRONT + V_SYNC));

    // Active video area
    wire h_active = (h_counter < H_VISIBLE);
    wire v_active = (v_counter < V_VISIBLE);
    wire video_active = h_active && v_active;

    // Blanking flags
    wire h_blank = !h_active;
    wire v_blank = !v_active;

    // VGA outputs (registered for clean signals)
    reg [2:0] vga_r_reg = 0;
    reg [2:0] vga_g_reg = 0;
    reg [2:0] vga_b_reg = 0;
    reg vga_hs_reg = 1;
    reg vga_vs_reg = 1;

    assign vga_r = vga_r_reg;
    assign vga_g = vga_g_reg;
    assign vga_b = vga_b_reg;
    assign vga_hs = vga_hs_reg;
    assign vga_vs = vga_vs_reg;

    //==========================================================================
    // Control Registers
    //==========================================================================
    reg        ctrl_enable = 0;         // VGA enable
    reg [31:0] fb_base_addr = 32'h00060000;  // Default framebuffer address
    reg        irq_vblank_enable = 0;   // VBLANK interrupt enable
    reg        irq_hblank_enable = 0;   // HBLANK interrupt enable

    //==========================================================================
    // Framebuffer Pixel Coordinates (320×240)
    //==========================================================================
    // Map 640×480 display to 320×240 framebuffer (2×2 upscale)
    wire [8:0] fb_x = h_counter[9:1];  // Divide by 2 (0-319)
    wire [8:0] fb_y = v_counter[9:1];  // Divide by 2 (0-239)

    // Check if we're in valid framebuffer area
    wire fb_valid = (fb_x < FB_WIDTH) && (fb_y < FB_HEIGHT);

    //==========================================================================
    // Line Buffer (320 pixels × 8-bit color)
    //==========================================================================
    // Double line buffer: while displaying line N, fetch line N+1
    reg [7:0] line_buffer_0 [0:319];
    reg [7:0] line_buffer_1 [0:319];
    reg       current_buffer = 0;  // Which buffer is being displayed

    // Current pixel from line buffer
    wire [7:0] pixel_data = current_buffer ?
                           line_buffer_1[fb_x] :
                           line_buffer_0[fb_x];

    //==========================================================================
    // Framebuffer Prefetch State Machine
    //==========================================================================
    localparam FETCH_IDLE       = 3'd0;
    localparam FETCH_WAIT_READY = 3'd1;
    localparam FETCH_READ       = 3'd2;
    localparam FETCH_STORE      = 3'd3;

    reg [2:0]  fetch_state = FETCH_IDLE;
    reg [8:0]  fetch_x = 0;      // Which pixel we're fetching (0-319)
    reg [8:0]  fetch_line = 0;   // Which line to fetch next
    reg        fetch_buffer = 0; // Which buffer to fill

    //==========================================================================
    // VGA Timing Generator (25MHz domain)
    //==========================================================================
    reg v_counter_prev = 0;
    reg h_counter_prev = 0;

    always @(posedge clk) begin
        if (!resetn) begin
            h_counter <= 0;
            v_counter <= 0;
            vga_hs_reg <= 1;
            vga_vs_reg <= 1;
            vga_r_reg <= 0;
            vga_g_reg <= 0;
            vga_b_reg <= 0;
            current_buffer <= 0;
            fetch_line <= 0;
            v_counter_prev <= 0;
            h_counter_prev <= 0;
            vga_vblank_irq <= 0;
            vga_hblank_irq <= 0;
        end else if (clk_25mhz && !clk_25mhz) begin  // Rising edge of 25MHz clock
            // Store previous counter values for edge detection
            h_counter_prev <= h_counter[0];
            v_counter_prev <= v_counter[0];

            // Horizontal counter
            if (h_counter == H_TOTAL - 1) begin
                h_counter <= 0;

                // Vertical counter
                if (v_counter == V_TOTAL - 1) begin
                    v_counter <= 0;
                    fetch_line <= 0;  // Reset for new frame
                end else begin
                    v_counter <= v_counter + 1;
                end

                // At end of visible line, swap buffers and prepare next line
                if (v_counter < V_VISIBLE) begin
                    current_buffer <= ~current_buffer;
                    fetch_line <= v_counter + 1;  // Start fetching next line
                end

                // Generate HBLANK interrupt (single-cycle pulse)
                if (irq_hblank_enable && v_counter < V_VISIBLE)
                    vga_hblank_irq <= 1;
                else
                    vga_hblank_irq <= 0;

            end else begin
                h_counter <= h_counter + 1;
                vga_hblank_irq <= 0;  // Clear HBLANK IRQ
            end

            // Generate VBLANK interrupt (single-cycle pulse at start of VBLANK)
            if (v_counter == V_VISIBLE && h_counter == 0) begin
                if (irq_vblank_enable)
                    vga_vblank_irq <= 1;
            end else begin
                vga_vblank_irq <= 0;
            end

            // Sync signals (negative polarity for VGA)
            vga_hs_reg <= ~h_sync;
            vga_vs_reg <= ~v_sync;

            // Pixel output
            if (video_active && ctrl_enable && fb_valid) begin
                // RGB332 format: RRRGGGBB
                vga_r_reg <= pixel_data[7:5];  // 3 bits red
                vga_g_reg <= pixel_data[4:2];  // 3 bits green
                vga_b_reg <= {pixel_data[1:0], pixel_data[1]};  // 2 bits blue, duplicate LSB
            end else begin
                // Blanking or disabled - output black
                vga_r_reg <= 0;
                vga_g_reg <= 0;
                vga_b_reg <= 0;
            end
        end
    end

    //==========================================================================
    // Framebuffer Fetch State Machine (50MHz domain)
    //==========================================================================
    // Fetches one scanline during horizontal blanking
    // Reads 4 pixels at a time (32-bit = 4×8-bit pixels)

    reg [31:0] sram_read_data = 0;

    always @(posedge clk) begin
        if (!resetn) begin
            fetch_state <= FETCH_IDLE;
            fetch_x <= 0;
            fetch_buffer <= 0;
            sram_valid <= 0;
            sram_we <= 0;
            sram_addr <= 0;
            sram_wdata <= 0;
            sram_read_data <= 0;
        end else begin
            case (fetch_state)
                FETCH_IDLE: begin
                    // Start fetching during horizontal blanking
                    if (h_blank && ctrl_enable && (fetch_line < FB_HEIGHT)) begin
                        fetch_x <= 0;
                        fetch_buffer <= ~current_buffer;  // Fill the non-displayed buffer
                        fetch_state <= FETCH_READ;
                    end
                end

                FETCH_READ: begin
                    if (fetch_x < FB_WIDTH) begin
                        // Calculate SRAM address for this pixel
                        // Address = fb_base_addr + (fetch_line * 320 + fetch_x)
                        // For 32-bit reads: addr = base + ((line * 320 + x) >> 2) * 4
                        // Since we read 4 pixels (32 bits) at a time

                        if (!sram_valid) begin
                            // Convert byte address to 16-bit word address
                            // Each read gets 4 pixels (32 bits = 2 × 16-bit words)
                            sram_addr <= (fb_base_addr[18:0] +
                                         {fetch_line, 6'b0} + {fetch_line, 8'b0} +  // line * 320
                                         {10'b0, fetch_x}) >> 1;  // Byte to word address
                            sram_we <= 0;
                            sram_valid <= 1;
                            fetch_state <= FETCH_WAIT_READY;
                        end
                    end else begin
                        // Done fetching this line
                        fetch_state <= FETCH_IDLE;
                    end
                end

                FETCH_WAIT_READY: begin
                    if (sram_ready) begin
                        // Got low 16 bits, need to read high 16 bits
                        sram_read_data[15:0] <= sram_rdata;
                        sram_valid <= 0;

                        // Read next word (high 16 bits)
                        // This is a simplification - we'll read 16 bits at a time
                        // and only use 8 bits, fetching one pixel at a time
                        fetch_state <= FETCH_STORE;
                    end
                end

                FETCH_STORE: begin
                    // Store pixel in line buffer
                    if (fetch_buffer)
                        line_buffer_1[fetch_x] <= sram_read_data[7:0];
                    else
                        line_buffer_0[fetch_x] <= sram_read_data[7:0];

                    fetch_x <= fetch_x + 1;
                    fetch_state <= FETCH_READ;
                end

                default: fetch_state <= FETCH_IDLE;
            endcase
        end
    end

    //==========================================================================
    // MMIO Register Interface
    //==========================================================================
    always @(posedge clk) begin
        if (!resetn) begin
            mmio_rdata <= 0;
            mmio_ready <= 0;
            ctrl_enable <= 0;
            fb_base_addr <= 32'h00060000;
            irq_vblank_enable <= 0;
            irq_hblank_enable <= 0;
        end else begin
            mmio_ready <= 0;

            if (mmio_valid && !mmio_ready) begin
                if (mmio_write) begin
                    // WRITE operations
                    case (mmio_addr)
                        ADDR_VGA_CTRL: begin
                            if (mmio_wstrb[0]) begin
                                ctrl_enable <= mmio_wdata[0];
                            end
                            mmio_ready <= 1;
                        end

                        ADDR_VGA_FB_ADDR: begin
                            fb_base_addr <= mmio_wdata;
                            mmio_ready <= 1;
                        end

                        ADDR_VGA_IRQ_MASK: begin
                            if (mmio_wstrb[0]) begin
                                irq_vblank_enable <= mmio_wdata[0];
                                irq_hblank_enable <= mmio_wdata[1];
                            end
                            mmio_ready <= 1;
                        end

                        ADDR_VGA_IRQ_CLEAR: begin
                            // Write-only register (writing clears corresponding IRQ)
                            // IRQs are auto-cleared (single-cycle pulses), so this is mainly for software ack
                            mmio_ready <= 1;
                        end

                        default: begin
                            mmio_ready <= 1;
                        end
                    endcase
                end else begin
                    // READ operations
                    case (mmio_addr)
                        ADDR_VGA_CTRL: begin
                            mmio_rdata <= {31'b0, ctrl_enable};
                            mmio_ready <= 1;
                        end

                        ADDR_VGA_STATUS: begin
                            mmio_rdata <= {30'b0, v_blank, h_blank};
                            mmio_ready <= 1;
                        end

                        ADDR_VGA_FB_ADDR: begin
                            mmio_rdata <= fb_base_addr;
                            mmio_ready <= 1;
                        end

                        ADDR_VGA_IRQ_MASK: begin
                            mmio_rdata <= {30'b0, irq_hblank_enable, irq_vblank_enable};
                            mmio_ready <= 1;
                        end

                        default: begin
                            mmio_rdata <= 0;
                            mmio_ready <= 1;
                        end
                    endcase
                end
            end
        end
    end

endmodule
