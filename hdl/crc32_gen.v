//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// crc32_gen.v - CRC32 Generator (IEEE 802.3)
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module crc32_gen (
    input wire clk,           // Clock
    input wire clr_crc,       // Clear/reset CRC
    input wire [31:0] din,    // 32-bit data input
    input wire calc,          // Calculate enable
    output wire [31:0] crc    // 32-bit CRC output
);

    reg [31:0] crc_reg;
    wire [31:0] m;
    
    // XOR input data with current CRC register
    assign m = din ^ crc_reg;
    
    // CRC calculation logic - implements 32 shifts through the LFSR
    always @(posedge clk) begin
        if (clr_crc) begin
            // Initial CRC value is 0xFFFFFFFF
            crc_reg <= 32'hFFFFFFFF;
        end else if (calc) begin
            // Parallel CRC calculation for 32-bit input
            // This implements the PKZIP polynomial in parallel
            crc_reg[0]  <= m[0] ^ m[1] ^ m[2] ^ m[4] ^ m[7] ^ m[8] ^ m[16] ^ m[22] ^ m[23] ^ m[26] ^ m[6] ^ m[20] ^ m[3];
            crc_reg[1]  <= m[1] ^ m[2] ^ m[3] ^ m[5] ^ m[8] ^ m[9] ^ m[17] ^ m[23] ^ m[24] ^ m[27] ^ m[7] ^ m[21] ^ m[4];
            crc_reg[2]  <= m[2] ^ m[3] ^ m[4] ^ m[6] ^ m[9] ^ m[10] ^ m[18] ^ m[24] ^ m[25] ^ m[28] ^ m[0] ^ m[8] ^ m[22] ^ m[5];
            crc_reg[3]  <= m[3] ^ m[4] ^ m[5] ^ m[7] ^ m[10] ^ m[11] ^ m[19] ^ m[25] ^ m[26] ^ m[29] ^ m[1] ^ m[9] ^ m[23] ^ m[6];
            crc_reg[4]  <= m[4] ^ m[5] ^ m[6] ^ m[8] ^ m[11] ^ m[12] ^ m[20] ^ m[26] ^ m[27] ^ m[30] ^ m[2] ^ m[10] ^ m[24] ^ m[7];
            crc_reg[5]  <= m[5] ^ m[6] ^ m[7] ^ m[9] ^ m[12] ^ m[13] ^ m[21] ^ m[27] ^ m[28] ^ m[31] ^ m[0] ^ m[3] ^ m[11] ^ m[25] ^ m[8];
            crc_reg[6]  <= m[10] ^ m[13] ^ m[14] ^ m[16] ^ m[28] ^ m[29] ^ m[0] ^ m[2] ^ m[12] ^ m[23] ^ m[9] ^ m[20] ^ m[3];
            crc_reg[7]  <= m[11] ^ m[14] ^ m[15] ^ m[17] ^ m[29] ^ m[30] ^ m[1] ^ m[3] ^ m[13] ^ m[24] ^ m[10] ^ m[21] ^ m[4];
            crc_reg[8]  <= m[12] ^ m[15] ^ m[16] ^ m[18] ^ m[30] ^ m[31] ^ m[2] ^ m[4] ^ m[14] ^ m[25] ^ m[0] ^ m[11] ^ m[22] ^ m[5];
            crc_reg[9]  <= m[13] ^ m[17] ^ m[19] ^ m[20] ^ m[31] ^ m[4] ^ m[5] ^ m[7] ^ m[8] ^ m[15] ^ m[0] ^ m[2] ^ m[12] ^ m[22];
            crc_reg[10] <= m[14] ^ m[18] ^ m[21] ^ m[22] ^ m[26] ^ m[4] ^ m[5] ^ m[9] ^ m[2] ^ m[13] ^ m[0] ^ m[7];
            crc_reg[11] <= m[15] ^ m[19] ^ m[22] ^ m[23] ^ m[27] ^ m[5] ^ m[6] ^ m[10] ^ m[3] ^ m[14] ^ m[1] ^ m[8];
            crc_reg[12] <= m[16] ^ m[20] ^ m[23] ^ m[24] ^ m[28] ^ m[6] ^ m[7] ^ m[11] ^ m[4] ^ m[15] ^ m[2] ^ m[9];
            crc_reg[13] <= m[17] ^ m[21] ^ m[24] ^ m[25] ^ m[29] ^ m[7] ^ m[8] ^ m[12] ^ m[5] ^ m[16] ^ m[3] ^ m[10] ^ m[0];
            crc_reg[14] <= m[18] ^ m[22] ^ m[25] ^ m[26] ^ m[30] ^ m[8] ^ m[9] ^ m[6] ^ m[17] ^ m[4] ^ m[11] ^ m[13] ^ m[0] ^ m[1];
            crc_reg[15] <= m[19] ^ m[23] ^ m[26] ^ m[27] ^ m[31] ^ m[9] ^ m[10] ^ m[7] ^ m[18] ^ m[5] ^ m[12] ^ m[14] ^ m[1] ^ m[2];
            crc_reg[16] <= m[16] ^ m[23] ^ m[24] ^ m[26] ^ m[27] ^ m[28] ^ m[10] ^ m[11] ^ m[22] ^ m[7] ^ m[19] ^ m[13] ^ m[4] ^ m[15] ^ m[1];
            crc_reg[17] <= m[17] ^ m[24] ^ m[25] ^ m[27] ^ m[28] ^ m[29] ^ m[11] ^ m[12] ^ m[23] ^ m[8] ^ m[20] ^ m[14] ^ m[5] ^ m[16] ^ m[2];
            crc_reg[18] <= m[18] ^ m[25] ^ m[26] ^ m[28] ^ m[29] ^ m[30] ^ m[12] ^ m[13] ^ m[24] ^ m[9] ^ m[21] ^ m[15] ^ m[6] ^ m[17] ^ m[3] ^ m[0];
            crc_reg[19] <= m[19] ^ m[26] ^ m[27] ^ m[29] ^ m[30] ^ m[31] ^ m[13] ^ m[14] ^ m[25] ^ m[10] ^ m[22] ^ m[16] ^ m[7] ^ m[18] ^ m[4] ^ m[0] ^ m[1];
            crc_reg[20] <= m[22] ^ m[27] ^ m[28] ^ m[30] ^ m[31] ^ m[14] ^ m[15] ^ m[11] ^ m[17] ^ m[16] ^ m[19] ^ m[4] ^ m[5] ^ m[6] ^ m[0] ^ m[3] ^ m[7];
            crc_reg[21] <= m[22] ^ m[26] ^ m[28] ^ m[29] ^ m[31] ^ m[15] ^ m[17] ^ m[12] ^ m[18] ^ m[5] ^ m[2] ^ m[0] ^ m[3];
            crc_reg[22] <= m[22] ^ m[26] ^ m[27] ^ m[29] ^ m[30] ^ m[20] ^ m[13] ^ m[19] ^ m[18] ^ m[7] ^ m[8] ^ m[2];
            crc_reg[23] <= m[23] ^ m[27] ^ m[28] ^ m[30] ^ m[31] ^ m[21] ^ m[14] ^ m[20] ^ m[19] ^ m[8] ^ m[9] ^ m[0] ^ m[3];
            crc_reg[24] <= m[24] ^ m[26] ^ m[28] ^ m[29] ^ m[31] ^ m[23] ^ m[15] ^ m[16] ^ m[21] ^ m[8] ^ m[9] ^ m[10] ^ m[2] ^ m[7] ^ m[3] ^ m[6];
            crc_reg[25] <= m[25] ^ m[26] ^ m[27] ^ m[29] ^ m[30] ^ m[20] ^ m[23] ^ m[24] ^ m[17] ^ m[9] ^ m[10] ^ m[11] ^ m[1] ^ m[2] ^ m[6];
            crc_reg[26] <= m[26] ^ m[27] ^ m[28] ^ m[30] ^ m[31] ^ m[21] ^ m[24] ^ m[25] ^ m[18] ^ m[10] ^ m[11] ^ m[12] ^ m[2] ^ m[3] ^ m[7];
            crc_reg[27] <= m[27] ^ m[28] ^ m[29] ^ m[31] ^ m[23] ^ m[25] ^ m[19] ^ m[20] ^ m[16] ^ m[11] ^ m[12] ^ m[13] ^ m[7] ^ m[2] ^ m[6] ^ m[1] ^ m[0];
            crc_reg[28] <= m[28] ^ m[29] ^ m[30] ^ m[22] ^ m[23] ^ m[24] ^ m[21] ^ m[16] ^ m[17] ^ m[12] ^ m[13] ^ m[14] ^ m[4] ^ m[6] ^ m[0];
            crc_reg[29] <= m[29] ^ m[30] ^ m[31] ^ m[23] ^ m[24] ^ m[25] ^ m[22] ^ m[17] ^ m[18] ^ m[13] ^ m[14] ^ m[15] ^ m[7] ^ m[5] ^ m[1] ^ m[0];
            crc_reg[30] <= m[30] ^ m[31] ^ m[24] ^ m[25] ^ m[22] ^ m[20] ^ m[18] ^ m[19] ^ m[14] ^ m[15] ^ m[7] ^ m[4] ^ m[3];
            crc_reg[31] <= m[31] ^ m[25] ^ m[22] ^ m[21] ^ m[19] ^ m[15] ^ m[7] ^ m[6] ^ m[5] ^ m[3] ^ m[2] ^ m[1] ^ m[0];
        end
    end
    
    // Output is ones-complemented (RefOut = True, XorOut = 0xFFFFFFFF)
    assign crc = ~crc_reg;

endmodule
