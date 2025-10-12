//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// circular_buffer.v - Circular Buffer for UART FIFOs
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module circular_buffer #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_BITS = 3
) (
    input wire clk,
    input wire reset_n,
    input wire clear,
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] wr_data,
    output wire full,
    input wire rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire empty
);

    localparam DEPTH = 1 << ADDR_BITS;
    localparam COUNT_BITS = ADDR_BITS + 1;

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_BITS-1:0] wr_ptr;
    reg [ADDR_BITS-1:0] rd_ptr;
    reg [COUNT_BITS-1:0] count;
    reg [DATA_WIDTH-1:0] rd_data_reg;

    assign full = (count == DEPTH);
    assign empty = (count == 0);
    assign rd_data = rd_data_reg;  // Drive from register instead of combinational

    always @(posedge clk) begin
        if (!reset_n || clear) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count <= 0;
            rd_data_reg <= 0;
        end else begin
            // Always keep rd_data_reg updated with current read pointer location
            // This ensures data is ready when rd_en asserts
            rd_data_reg <= memory[rd_ptr];

            case ({wr_en & ~full, rd_en & ~empty})
                2'b10: begin // Write only
                    memory[wr_ptr] <= wr_data;
                    wr_ptr <= wr_ptr + 1;
                    count <= count + 1;
                end
                2'b01: begin // Read only
                    rd_ptr <= rd_ptr + 1;
                    count <= count - 1;
                end
                2'b11: begin // Read and write
                    memory[wr_ptr] <= wr_data;
                    wr_ptr <= wr_ptr + 1;
                    rd_ptr <= rd_ptr + 1;
                end
                default: begin // No operation
                    // Do nothing
                end
            endcase
        end
    end

endmodule
