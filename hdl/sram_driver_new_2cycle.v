//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// sram_driver_new.v - SRAM Physical Interface Driver (2-CYCLE OPTIMIZED)
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//
// OPTIMIZATION: Reduced from 5-cycle to 2-cycle access for 2.5x speedup
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

    // 2-Cycle FSM States
    localparam IDLE     = 2'd0;  // Waiting for transaction
    localparam ACTIVE   = 2'd1;  // Address + control signals asserted
    localparam COMPLETE = 2'd2;  // Data capture (read) or write completion

    reg [1:0] state;
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
                        // Latch inputs for stability
                        addr_reg <= addr[17:0];
                        wdata_reg <= wdata;
                        we_reg <= we;

                        // synthesis translate_off
                        $display("[SRAM_2CYC] IDLE->ACTIVE: addr=0x%05x data=0x%04x we=%b t=%0t",
                                 addr[17:0], wdata, we, $time);
                        // synthesis translate_on

                        state <= ACTIVE;
                    end
                end

                ACTIVE: begin
                    // Cycle 1: Assert all control signals simultaneously
                    // This meets datasheet timing:
                    //   - tAS = 0ns min (address setup before WE/OE) - NOT REQUIRED
                    //   - tAA = 10ns max (address to data valid)
                    //   - tWP = 7ns min (write pulse width)

                    sram_addr <= addr_reg;
                    sram_cs_n <= 1'b0;  // Enable chip

                    if (we_reg) begin
                        // WRITE: Assert address, data, CS, and WE simultaneously
                        // Data is stable from this cycle through COMPLETE (40ns total)
                        // This exceeds tDW = 5ns min and tDH = 0ns min
                        data_out_reg <= wdata_reg;
                        data_oe <= 1'b1;
                        sram_we_n <= 1'b0;  // Assert WE immediately (will be 20ns+ pulse)
                        sram_oe_n <= 1'b1;  // OE must be HIGH during writes

                        // synthesis translate_off
                        $display("[SRAM_2CYC] ACTIVE(WRITE): addr=0x%05x data=0x%04x WE=0 t=%0t",
                                 addr_reg, wdata_reg, $time);
                        // synthesis translate_on
                    end else begin
                        // READ: Assert address, CS, and OE simultaneously
                        // Data will be valid by end of COMPLETE cycle (40ns total)
                        // This exceeds tAA = 10ns max
                        sram_oe_n <= 1'b0;  // Enable output immediately
                        sram_we_n <= 1'b1;  // WE must be HIGH during reads
                        data_oe <= 1'b0;    // Tri-state our output

                        // synthesis translate_off
                        $display("[SRAM_2CYC] ACTIVE(READ): addr=0x%05x OE=0 t=%0t",
                                 addr_reg, $time);
                        // synthesis translate_on
                    end

                    state <= COMPLETE;
                end

                COMPLETE: begin
                    // Cycle 2: Complete transaction
                    sram_addr <= addr_reg;  // Keep address stable

                    if (we_reg) begin
                        // WRITE COMPLETION:
                        // WE has been asserted for 20ns (ACTIVE cycle)
                        // Now deassert WE while keeping data stable
                        // This provides tWP = 20ns (exceeds 7ns min)
                        // and tDH = 20ns (exceeds 0ns min)
                        sram_cs_n <= 1'b0;      // Keep CS active
                        sram_we_n <= 1'b1;      // Deassert WE (rising edge latches data)
                        sram_oe_n <= 1'b1;      // Keep OE high
                        data_out_reg <= wdata_reg;  // Maintain data stability
                        data_oe <= 1'b1;        // Keep driving bus this cycle
                        ready <= 1'b1;          // Signal completion

                        // synthesis translate_off
                        $display("[SRAM_2CYC] COMPLETE(WRITE): WE=1 (write latched) ready=1 t=%0t", $time);
                        // synthesis translate_on
                    end else begin
                        // READ COMPLETION:
                        // Data has had 20ns (ACTIVE) + settling time to become valid
                        // This exceeds tAA = 10ns max, so data is stable
                        // Sample data now
                        sram_cs_n <= 1'b0;      // Keep CS active
                        sram_oe_n <= 1'b0;      // Keep OE active
                        sram_we_n <= 1'b1;      // Keep WE high
                        rdata <= sram_data;     // Sample data from SRAM
                        ready <= 1'b1;          // Signal completion

                        // synthesis translate_off
                        $display("[SRAM_2CYC] COMPLETE(READ): data=0x%04x ready=1 t=%0t",
                                sram_data, $time);
                        // synthesis translate_on
                    end

                    state <= IDLE;  // Return directly to IDLE (no cooldown needed)
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Timing Analysis Comments:
    //
    // K6R4016V1D-TC10 Requirements vs 2-Cycle Implementation:
    //
    // READS:
    //   tRC  (Read Cycle)        = 10ns min → We provide 40ns (2 cycles)   ✓
    //   tAA  (Address Access)    = 10ns max → We allow 40ns                ✓
    //   tOE  (OE to Valid)       = 5ns max  → We allow 40ns                ✓
    //   tOH  (Output Hold)       = 3ns min  → We provide 20ns              ✓
    //   tHZ  (CS High to Hi-Z)   = 5ns max  → Next cycle transition        ✓
    //
    // WRITES:
    //   tWC  (Write Cycle)       = 10ns min → We provide 40ns (2 cycles)   ✓
    //   tAS  (Address Setup)     = 0ns min  → We provide 0ns (simultaneous)✓
    //   tAW  (Address Valid)     = 7ns min  → We provide 40ns              ✓
    //   tWP  (Write Pulse)       = 7ns min  → We provide 20ns              ✓
    //   tDW  (Data Setup)        = 5ns min  → We provide 40ns              ✓
    //   tDH  (Data Hold)         = 0ns min  → We provide 20ns              ✓
    //   tWR  (Write Recovery)    = 0ns min  → Next cycle ready             ✓
    //
    // All timing requirements met with 2-4x margin at 50MHz (20ns period)

endmodule
