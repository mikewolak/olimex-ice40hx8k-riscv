//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// sram_driver_new.v - SRAM Physical Interface Driver
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module sram_driver_new (
    input wire clk,
    input wire resetn,

    // Command Interface
    input wire valid,
    output reg ready,
    input wire we,
    input wire [18:0] addr,      // Word address (19 bits for 512KB)
    input wire [15:0] wdata,
    output reg [15:0] rdata,

    // SRAM Physical Interface
    output reg [17:0] sram_addr,
    inout wire [15:0] sram_data,
    output reg sram_cs_n,
    output reg sram_oe_n,
    output reg sram_we_n
);

    // States
    localparam IDLE     = 3'd0;
    localparam SETUP    = 3'd1;  // Address/data setup
    localparam ACTIVE   = 3'd2;  // Assert WE for write, sample data for read
    localparam RECOVERY = 3'd3;  // Write recovery / read completion
    localparam COOLDOWN = 3'd4;  // Mandatory 1-cycle gap after transaction

    reg [2:0] state;
    reg [15:0] data_out_reg;
    reg data_oe;
    reg [17:0] addr_reg;
    reg [15:0] wdata_reg;
    reg we_reg;

    // Tri-state data control
    assign sram_data = data_oe ? data_out_reg : 16'hzzzz;

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            ready <= 1'b0;
            sram_cs_n <= 1'b1;
            sram_oe_n <= 1'b1;
            sram_we_n <= 1'b1;
            data_oe <= 1'b0;
            data_out_reg <= 16'h0;
            rdata <= 16'h0;
            addr_reg <= 18'h0;
            wdata_reg <= 16'h0;
            we_reg <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 1'b0;
                    sram_cs_n <= 1'b1;
                    sram_oe_n <= 1'b1;
                    sram_we_n <= 1'b1;
                    data_oe <= 1'b0;

                    if (valid) begin
                        // Latch address and data
                        addr_reg <= addr[17:0];
                        wdata_reg <= wdata;
                        we_reg <= we;

                        // synthesis translate_off
                        $display("[SRAM_DRIVER] IDLE->SETUP: addr=0x%05x data=0x%04x we=%b",
                                 addr[17:0], wdata, we);
                        // synthesis translate_on

                        state <= SETUP;
                    end
                end

                SETUP: begin
                    // Cycle 1: Address setup, assert CS
                    // tAS = 0ns min (we have 10ns)
                    sram_addr <= addr_reg;
                    sram_cs_n <= 1'b0;

                    if (we_reg) begin
                        // WRITE: Setup data on bus, keep WE and OE high
                        data_out_reg <= wdata_reg;
                        data_oe <= 1'b1;
                        sram_we_n <= 1'b1;  // Keep high during setup
                        sram_oe_n <= 1'b1;  // OE must be high during write

                        // synthesis translate_off
                        $display("[SRAM_DRIVER] SETUP(WRITE): addr=0x%05x data=0x%04x",
                                 addr_reg, wdata_reg);
                        // synthesis translate_on
                    end else begin
                        // READ: Assert OE, keep WE high
                        sram_oe_n <= 1'b0;
                        sram_we_n <= 1'b1;
                        data_oe <= 1'b0;

                        // synthesis translate_off
                        $display("[SRAM_DRIVER] SETUP(READ): addr=0x%05x", addr_reg);
                        // synthesis translate_on
                    end

                    state <= ACTIVE;
                end

                ACTIVE: begin
                    // Cycle 2: Write pulse or read data sampling
                    sram_cs_n <= 1'b0;
                    sram_addr <= addr_reg;  // Keep address stable

                    if (we_reg) begin
                        // WRITE: Assert WE while data is stable
                        // tWP = 7ns min (we have 10ns)
                        // tDW = 5ns min (data was setup in previous cycle, stable for 10ns+)
                        sram_we_n <= 1'b0;
                        sram_oe_n <= 1'b1;
                        data_out_reg <= wdata_reg;
                        data_oe <= 1'b1;

                        // synthesis translate_off
                        $display("[SRAM_DRIVER] ACTIVE(WRITE): WE asserted, addr=0x%05x data=0x%04x",
                                 addr_reg, wdata_reg);
                        // synthesis translate_on
                    end else begin
                        // READ: Sample data from SRAM
                        // tAA = 10ns max (we have 20ns from address setup)
                        sram_oe_n <= 1'b0;
                        sram_we_n <= 1'b1;
                        rdata <= sram_data;

                        // synthesis translate_off
                        $display("[SRAM_DRIVER] ACTIVE(READ): Sampling data=0x%04x", sram_data);
                        // synthesis translate_on
                    end

                    state <= RECOVERY;
                end

                RECOVERY: begin
                    // Cycle 3: Recovery cycle
                    if (we_reg) begin
                        // WRITE: Deassert WE, maintain data hold
                        // tDH = 0ns min (we hold for full cycle = 10ns)
                        // tWR = 0ns min (we have 10ns recovery)
                        sram_we_n <= 1'b1;
                        sram_cs_n <= 1'b1;
                        sram_oe_n <= 1'b1;
                        data_oe <= 1'b0;  // Release bus

                        // synthesis translate_off
                        $display("[SRAM_DRIVER] RECOVERY(WRITE): Complete");
                        // synthesis translate_on
                    end else begin
                        // READ: Complete, data already sampled
                        sram_cs_n <= 1'b1;
                        sram_oe_n <= 1'b1;
                        sram_we_n <= 1'b1;

                        // synthesis translate_off
                        $display("[SRAM_DRIVER] RECOVERY(READ): Complete, rdata=0x%04x", rdata);
                        // synthesis translate_on
                    end

                    ready <= 1'b1;
                    state <= COOLDOWN;  // Go to cooldown, not directly to IDLE
                end

                COOLDOWN: begin
                    // Mandatory 1-cycle gap - allows master to deassert valid
                    ready <= 1'b0;
                    sram_cs_n <= 1'b1;
                    sram_oe_n <= 1'b1;
                    sram_we_n <= 1'b1;
                    data_oe <= 1'b0;

                    // synthesis translate_off
                    $display("[SRAM_DRIVER] COOLDOWN");
                    // synthesis translate_on

                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
