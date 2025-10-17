//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// sram_driver_fast.v - Fast 100MHz SRAM Driver with Burst Mode
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module sram_driver_fast (
    input wire clk_100mhz,   // 100 MHz SRAM clock (EXTCLK direct)
    input wire clk_50mhz,    // 50 MHz system clock (for CDC)
    input wire resetn,

    // CPU Interface (50MHz domain)
    input wire        cpu_valid,
    output reg        cpu_ready,
    input wire        cpu_we,
    input wire        cpu_instr,     // 1 = instruction fetch (high priority)
    input wire [18:0] cpu_addr,      // 16-bit word address
    input wire [15:0] cpu_wdata,
    output reg [15:0] cpu_rdata,

    // VGA Burst Interface (50MHz domain)
    input wire        vga_burst_req,  // Request burst of N words
    output reg        vga_burst_ack,  // Burst complete
    input wire [18:0] vga_burst_addr, // Starting address
    input wire [8:0]  vga_burst_len,  // Number of 16-bit words to read (max 320)
    output reg        vga_wdata_valid,// Data valid pulse
    output reg [15:0] vga_wdata,      // Burst data output

    // SRAM Physical Interface (100MHz domain)
    output reg [17:0] sram_addr,
    inout wire [15:0] sram_data,
    output reg        sram_cs_n,
    output reg        sram_oe_n,
    output reg        sram_we_n
);

    //==========================================================================
    // Clock Domain Crossing (CDC) - 50MHz → 100MHz
    //==========================================================================

    // CPU request CDC
    reg cpu_valid_sync1, cpu_valid_sync2;
    reg cpu_we_lat, cpu_instr_lat;
    reg [18:0] cpu_addr_lat;
    reg [15:0] cpu_wdata_lat;

    // VGA request CDC
    reg vga_burst_req_sync1, vga_burst_req_sync2;
    reg [18:0] vga_burst_addr_lat;
    reg [8:0]  vga_burst_len_lat;

    // Response CDC (100MHz → 50MHz)
    reg cpu_ready_100;
    reg [15:0] cpu_rdata_100;
    reg vga_burst_ack_100;

    // Synchronize CPU request (50MHz → 100MHz)
    always @(posedge clk_100mhz) begin
        if (!resetn) begin
            cpu_valid_sync1 <= 0;
            cpu_valid_sync2 <= 0;
        end else begin
            cpu_valid_sync1 <= cpu_valid;
            cpu_valid_sync2 <= cpu_valid_sync1;
        end
    end

    // Latch CPU request parameters on rising edge
    always @(posedge clk_100mhz) begin
        if (!resetn) begin
            cpu_we_lat <= 0;
            cpu_instr_lat <= 0;
            cpu_addr_lat <= 0;
            cpu_wdata_lat <= 0;
        end else if (cpu_valid_sync1 && !cpu_valid_sync2) begin
            // Rising edge of valid - latch all parameters
            cpu_we_lat <= cpu_we;
            cpu_instr_lat <= cpu_instr;
            cpu_addr_lat <= cpu_addr;
            cpu_wdata_lat <= cpu_wdata;
        end
    end

    // Synchronize VGA burst request (50MHz → 100MHz)
    always @(posedge clk_100mhz) begin
        if (!resetn) begin
            vga_burst_req_sync1 <= 0;
            vga_burst_req_sync2 <= 0;
        end else begin
            vga_burst_req_sync1 <= vga_burst_req;
            vga_burst_req_sync2 <= vga_burst_req_sync1;
        end
    end

    // Latch VGA burst parameters
    always @(posedge clk_100mhz) begin
        if (!resetn) begin
            vga_burst_addr_lat <= 0;
            vga_burst_len_lat <= 0;
        end else if (vga_burst_req_sync1 && !vga_burst_req_sync2) begin
            vga_burst_addr_lat <= vga_burst_addr;
            vga_burst_len_lat <= vga_burst_len;
        end
    end

    // Synchronize responses (100MHz → 50MHz)
    always @(posedge clk_50mhz) begin
        if (!resetn) begin
            cpu_ready <= 0;
            cpu_rdata <= 0;
            vga_burst_ack <= 0;
            vga_wdata_valid <= 0;
            vga_wdata <= 0;
        end else begin
            cpu_ready <= cpu_ready_100;
            cpu_rdata <= cpu_rdata_100;
            vga_burst_ack <= vga_burst_ack_100;
            // VGA data passes through directly (no CDC needed for burst data)
        end
    end

    //==========================================================================
    // SRAM State Machine (100MHz domain)
    //==========================================================================
    // States:
    // - IDLE: Wait for request
    // - CPU_READ: Single-cycle read for CPU
    // - CPU_WRITE: Single-cycle write for CPU
    // - VGA_BURST: Continuous burst read for VGA

    localparam IDLE       = 3'd0;
    localparam CPU_READ   = 3'd1;
    localparam CPU_WRITE  = 3'd2;
    localparam VGA_BURST  = 3'd3;
    localparam COOLDOWN   = 3'd4;

    reg [2:0] state = IDLE;
    reg [8:0] burst_counter = 0;
    reg [18:0] burst_addr = 0;

    // Tri-state buffer control
    reg [15:0] data_out_reg = 0;
    reg data_oe = 0;
    assign sram_data = data_oe ? data_out_reg : 16'hzzzz;

    // Main state machine @ 100MHz
    always @(posedge clk_100mhz) begin
        if (!resetn) begin
            state <= IDLE;
            sram_cs_n <= 1;
            sram_oe_n <= 1;
            sram_we_n <= 1;
            sram_addr <= 0;
            data_oe <= 0;
            data_out_reg <= 0;
            cpu_ready_100 <= 0;
            cpu_rdata_100 <= 0;
            vga_burst_ack_100 <= 0;
            vga_wdata_valid <= 0;
            vga_wdata <= 0;
            burst_counter <= 0;
            burst_addr <= 0;
        end else begin
            // Default: clear single-cycle signals
            cpu_ready_100 <= 0;
            vga_wdata_valid <= 0;

            case (state)
                IDLE: begin
                    sram_cs_n <= 1;
                    sram_oe_n <= 1;
                    sram_we_n <= 1;
                    data_oe <= 0;
                    vga_burst_ack_100 <= 0;

                    // Priority arbitration:
                    // 1. CPU instruction fetch (highest)
                    // 2. CPU data access
                    // 3. VGA burst (lowest, only when no CPU activity)

                    if (cpu_valid_sync2) begin
                        // CPU request
                        sram_addr <= cpu_addr_lat[17:0];
                        sram_cs_n <= 0;

                        if (cpu_we_lat) begin
                            // Write operation
                            data_out_reg <= cpu_wdata_lat;
                            data_oe <= 1;
                            sram_we_n <= 0;  // Assert WE
                            sram_oe_n <= 1;  // OE must be high during write
                            state <= CPU_WRITE;
                        end else begin
                            // Read operation
                            sram_oe_n <= 0;  // Assert OE
                            sram_we_n <= 1;  // WE high
                            data_oe <= 0;
                            state <= CPU_READ;
                        end
                    end else if (vga_burst_req_sync2 && !vga_burst_ack_100) begin
                        // VGA burst request (only if CPU is idle)
                        burst_addr <= vga_burst_addr_lat;
                        burst_counter <= vga_burst_len_lat;
                        state <= VGA_BURST;
                    end
                end

                CPU_READ: begin
                    // Single-cycle read @ 100MHz
                    // Address was set up in previous cycle
                    // Data is valid after tAA (10ns max, we have 10ns @ 100MHz)
                    cpu_rdata_100 <= sram_data;
                    cpu_ready_100 <= 1;
                    sram_cs_n <= 1;
                    sram_oe_n <= 1;
                    state <= COOLDOWN;
                end

                CPU_WRITE: begin
                    // Single-cycle write
                    // WE was asserted in previous cycle, data is stable
                    cpu_ready_100 <= 1;
                    sram_cs_n <= 1;
                    sram_we_n <= 1;
                    data_oe <= 0;
                    state <= COOLDOWN;
                end

                VGA_BURST: begin
                    // Continuous burst read mode
                    // Each cycle: address → data (pipeline)
                    if (burst_counter > 0) begin
                        // Set up address
                        sram_addr <= burst_addr[17:0];
                        sram_cs_n <= 0;
                        sram_oe_n <= 0;
                        sram_we_n <= 1;
                        data_oe <= 0;

                        // Sample data from PREVIOUS cycle (if not first)
                        if (burst_counter < vga_burst_len_lat) begin
                            vga_wdata <= sram_data;
                            vga_wdata_valid <= 1;
                        end

                        // Advance to next address
                        burst_addr <= burst_addr + 1;
                        burst_counter <= burst_counter - 1;
                    end else begin
                        // Burst complete - sample final word
                        vga_wdata <= sram_data;
                        vga_wdata_valid <= 1;
                        vga_burst_ack_100 <= 1;
                        sram_cs_n <= 1;
                        sram_oe_n <= 1;
                        state <= IDLE;
                    end
                end

                COOLDOWN: begin
                    // One cycle gap to allow signals to settle
                    sram_cs_n <= 1;
                    sram_oe_n <= 1;
                    sram_we_n <= 1;
                    data_oe <= 0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
