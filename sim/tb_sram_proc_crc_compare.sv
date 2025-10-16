//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// tb_sram_proc_crc_compare.sv - CRC32 Comparison Test
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//
// DESCRIPTION:
// This testbench compares CRC32 calculations between sram_proc_new and
// sram_proc_optimized to verify the optimization didn't break CRC functionality.
//
// TESTS:
// 1. Basic CRC32 on 256 bytes (0x00000000 - 0x00000100)
// 2. Small CRC32 on 64 bytes
// 3. Large CRC32 on 1024 bytes
// 4. Edge case: 4-byte CRC (single word)
// 5. Pattern test: Verify CRC calculation correctness
//==============================================================================

`timescale 1ns / 1ps

module tb_sram_proc_crc_compare;

    // Clock and Reset
    reg clk = 0;
    reg resetn = 0;

    // Command codes
    localparam CMD_NONE  = 8'h00;
    localparam CMD_READ  = 8'h01;
    localparam CMD_WRITE = 8'h02;
    localparam CMD_CRC   = 8'h04;

    //==========================================================================
    // SRAM PROC NEW (Original - Known Good)
    //==========================================================================
    reg start_new;
    reg [7:0] cmd_new;
    reg [31:0] addr_in_new;
    reg [31:0] data_in_new;
    reg [3:0] mem_wstrb_new;
    wire busy_new;
    wire done_new;
    wire [31:0] result_new;
    wire [15:0] result_low_new;
    wire [15:0] result_high_new;

    wire sram_valid_new;
    reg sram_ready_new;
    wire sram_we_new;
    wire [18:0] sram_addr_16_new;
    wire [15:0] sram_wdata_16_new;
    reg [15:0] sram_rdata_16_new;

    sram_proc_new dut_new (
        .clk(clk),
        .resetn(resetn),
        .start(start_new),
        .cmd(cmd_new),
        .addr_in(addr_in_new),
        .data_in(data_in_new),
        .mem_wstrb(mem_wstrb_new),
        .busy(busy_new),
        .done(done_new),
        .result(result_new),
        .result_low(result_low_new),
        .result_high(result_high_new),
        .rx_byte(8'h00),
        .rx_valid(1'b0),
        .tx_data(),
        .tx_valid(),
        .tx_ready(1'b1),
        .sram_valid(sram_valid_new),
        .sram_ready(sram_ready_new),
        .sram_we(sram_we_new),
        .sram_addr_16(sram_addr_16_new),
        .sram_wdata_16(sram_wdata_16_new),
        .sram_rdata_16(sram_rdata_16_new)
    );

    //==========================================================================
    // SRAM PROC OPTIMIZED (Under Test)
    //==========================================================================
    reg start_opt;
    reg [7:0] cmd_opt;
    reg [31:0] addr_in_opt;
    reg [31:0] data_in_opt;
    reg [3:0] mem_wstrb_opt;
    wire busy_opt;
    wire done_opt;
    wire [31:0] result_opt;
    wire [15:0] result_low_opt;
    wire [15:0] result_high_opt;

    wire sram_valid_opt;
    reg sram_ready_opt;
    wire sram_we_opt;
    wire [18:0] sram_addr_16_opt;
    wire [15:0] sram_wdata_16_opt;
    reg [15:0] sram_rdata_16_opt;

    sram_proc_optimized dut_opt (
        .clk(clk),
        .resetn(resetn),
        .start(start_opt),
        .cmd(cmd_opt),
        .addr_in(addr_in_opt),
        .data_in(data_in_opt),
        .mem_wstrb(mem_wstrb_opt),
        .busy(busy_opt),
        .done(done_opt),
        .result(result_opt),
        .result_low(result_low_opt),
        .result_high(result_high_opt),
        .rx_byte(8'h00),
        .rx_valid(1'b0),
        .tx_data(),
        .tx_valid(),
        .tx_ready(1'b1),
        .sram_valid(sram_valid_opt),
        .sram_ready(sram_ready_opt),
        .sram_we(sram_we_opt),
        .sram_addr_16(sram_addr_16_opt),
        .sram_wdata_16(sram_wdata_16_opt),
        .sram_rdata_16(sram_rdata_16_opt)
    );

    //==========================================================================
    // SRAM Memory Model (Shared between both controllers)
    //==========================================================================
    reg [15:0] sram_mem [0:262143];  // 256K x 16-bit = 512KB

    // SRAM Driver Model for NEW controller (2-cycle delay)
    reg [1:0] sram_cycle_new;
    always @(posedge clk) begin
        if (!resetn) begin
            sram_ready_new <= 1'b0;
            sram_rdata_16_new <= 16'h0000;
            sram_cycle_new <= 2'd0;
        end else begin
            if (sram_valid_new) begin
                if (sram_cycle_new == 2'd0) begin
                    // Cycle 1: Start operation
                    sram_ready_new <= 1'b0;
                    sram_cycle_new <= 2'd1;
                end else if (sram_cycle_new == 2'd1) begin
                    // Cycle 2: Complete operation
                    sram_ready_new <= 1'b1;
                    if (!sram_we_new) begin
                        sram_rdata_16_new <= sram_mem[sram_addr_16_new];
                    end else begin
                        sram_mem[sram_addr_16_new] <= sram_wdata_16_new;
                    end
                    sram_cycle_new <= 2'd2;
                end else begin
                    // Cycle 3+: Hold ready until valid drops
                    sram_ready_new <= 1'b1;
                    if (!sram_valid_new)
                        sram_cycle_new <= 2'd0;
                end
            end else begin
                sram_ready_new <= 1'b0;
                sram_cycle_new <= 2'd0;
            end
        end
    end

    // SRAM Driver Model for OPTIMIZED controller (2-cycle delay)
    reg [1:0] sram_cycle_opt;
    always @(posedge clk) begin
        if (!resetn) begin
            sram_ready_opt <= 1'b0;
            sram_rdata_16_opt <= 16'h0000;
            sram_cycle_opt <= 2'd0;
        end else begin
            if (sram_valid_opt) begin
                if (sram_cycle_opt == 2'd0) begin
                    // Cycle 1: Start operation
                    sram_ready_opt <= 1'b0;
                    sram_cycle_opt <= 2'd1;
                end else if (sram_cycle_opt == 2'd1) begin
                    // Cycle 2: Complete operation
                    sram_ready_opt <= 1'b1;
                    if (!sram_we_opt) begin
                        sram_rdata_16_opt <= sram_mem[sram_addr_16_opt];
                    end else begin
                        sram_mem[sram_addr_16_opt] <= sram_wdata_16_opt;
                    end
                    sram_cycle_opt <= 2'd2;
                end else begin
                    // Cycle 3+: Hold ready until valid drops
                    sram_ready_opt <= 1'b1;
                    if (!sram_valid_opt)
                        sram_cycle_opt <= 2'd0;
                end
            end else begin
                sram_ready_opt <= 1'b0;
                sram_cycle_opt <= 2'd0;
            end
        end
    end

    //==========================================================================
    // Clock Generation
    //==========================================================================
    always #10 clk = ~clk;  // 50 MHz clock

    //==========================================================================
    // Test Variables
    //==========================================================================
    integer test_count;
    integer pass_count;
    integer fail_count;

    //==========================================================================
    // Task: Initialize SRAM with test pattern
    //==========================================================================
    task init_sram_pattern(input [31:0] start_addr, input [31:0] size, input [7:0] pattern);
        integer i;
        reg [31:0] word_val;
        begin
            $display("[INIT] Filling SRAM from 0x%08x, size=%d bytes, pattern=0x%02x",
                     start_addr, size, pattern);
            for (i = 0; i < size/4; i = i + 1) begin
                // Create 32-bit word based on pattern
                case (pattern)
                    8'h00: word_val = i;  // Sequential
                    8'h01: word_val = 32'hAAAAAAAA;  // 0xAAAAAAAA
                    8'h02: word_val = 32'h55555555;  // 0x55555555
                    8'h03: word_val = {24'h000000, i[7:0]};  // Byte sequential
                    default: word_val = 32'h00000000;
                endcase

                // Split 32-bit word into two 16-bit SRAM words
                sram_mem[(start_addr/2) + i*2]     = word_val[15:0];
                sram_mem[(start_addr/2) + i*2 + 1] = word_val[31:16];
            end
        end
    endtask

    //==========================================================================
    // Task: Run CRC test on both controllers
    //==========================================================================
    task test_crc(input [31:0] start_addr, input [31:0] end_addr, input [8*64-1:0] test_name);
        reg [31:0] crc_new_result;
        reg [31:0] crc_opt_result;
        integer cycles_new, cycles_opt;
        integer start_time, end_time;
        begin
            test_count = test_count + 1;
            $display("\n========================================");
            $display("TEST %0d: %s", test_count, test_name);
            $display("  Range: 0x%08x - 0x%08x (%0d bytes)",
                     start_addr, end_addr, end_addr - start_addr);
            $display("========================================");

            //==================================================================
            // Test SRAM_PROC_NEW
            //==================================================================
            $display("\n[NEW] Starting CRC test...");
            start_time = $time;

            @(posedge clk);
            start_new = 1'b1;
            cmd_new = CMD_CRC;
            addr_in_new = start_addr;
            data_in_new = end_addr;

            @(posedge clk);
            start_new = 1'b0;

            // Wait for completion
            wait(done_new);
            end_time = $time;
            crc_new_result = result_new;
            cycles_new = (end_time - start_time) / 20;  // 20ns per cycle

            $display("[NEW] CRC Complete: 0x%08x (%0d cycles)", crc_new_result, cycles_new);

            //==================================================================
            // Test SRAM_PROC_OPTIMIZED
            //==================================================================
            $display("\n[OPT] Starting CRC test...");
            start_time = $time;

            @(posedge clk);
            start_opt = 1'b1;
            cmd_opt = CMD_CRC;
            addr_in_opt = start_addr;
            data_in_opt = end_addr;

            @(posedge clk);
            start_opt = 1'b0;

            // Wait for completion
            wait(done_opt);
            end_time = $time;
            crc_opt_result = result_opt;
            cycles_opt = (end_time - start_time) / 20;

            $display("[OPT] CRC Complete: 0x%08x (%0d cycles)", crc_opt_result, cycles_opt);

            //==================================================================
            // Compare Results
            //==================================================================
            $display("\n[COMPARE] Results:");
            $display("  NEW: 0x%08x (%0d cycles)", crc_new_result, cycles_new);
            $display("  OPT: 0x%08x (%0d cycles)", crc_opt_result, cycles_opt);

            if (crc_new_result == crc_opt_result) begin
                $display("  *** PASS *** CRC values match!");
                pass_count = pass_count + 1;
            end else begin
                $display("  *** FAIL *** CRC values DO NOT match!");
                $display("  ERROR: Expected 0x%08x, got 0x%08x", crc_new_result, crc_opt_result);
                fail_count = fail_count + 1;
            end

            $display("  Performance: OPT is %0d cycles (%0d%%) vs NEW",
                     cycles_new - cycles_opt,
                     ((cycles_new - cycles_opt) * 100) / cycles_new);

            // Wait a few cycles before next test
            repeat(10) @(posedge clk);
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        $display("========================================");
        $display("SRAM PROC CRC32 Comparison Test");
        $display("========================================\n");

        // Initialize counters
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        // Initialize control signals
        start_new = 1'b0;
        cmd_new = CMD_NONE;
        addr_in_new = 32'h0;
        data_in_new = 32'h0;
        mem_wstrb_new = 4'h0;

        start_opt = 1'b0;
        cmd_opt = CMD_NONE;
        addr_in_opt = 32'h0;
        data_in_opt = 32'h0;
        mem_wstrb_opt = 4'h0;

        // Reset sequence
        resetn = 0;
        repeat(5) @(posedge clk);
        resetn = 1;
        repeat(5) @(posedge clk);

        //======================================================================
        // TEST 1: Basic 256-byte CRC (matches bootloader test)
        //======================================================================
        init_sram_pattern(32'h00000000, 256, 8'h00);  // Sequential pattern
        test_crc(32'h00000000, 32'h00000100, "Basic 256-byte sequential pattern");

        //======================================================================
        // TEST 2: Small 64-byte CRC
        //======================================================================
        init_sram_pattern(32'h00001000, 64, 8'h00);
        test_crc(32'h00001000, 32'h00001040, "Small 64-byte CRC");

        //======================================================================
        // TEST 3: Large 1024-byte CRC
        //======================================================================
        init_sram_pattern(32'h00010000, 1024, 8'h00);
        test_crc(32'h00010000, 32'h00010400, "Large 1KB CRC");

        //======================================================================
        // TEST 4: Edge case - Single 4-byte word
        //======================================================================
        sram_mem[0] = 16'h1234;
        sram_mem[1] = 16'h5678;
        test_crc(32'h00000000, 32'h00000004, "Single 4-byte word (0x12345678)");

        //======================================================================
        // TEST 5: Pattern 0xAAAAAAAA
        //======================================================================
        init_sram_pattern(32'h00020000, 256, 8'h01);
        test_crc(32'h00020000, 32'h00020100, "256 bytes of 0xAAAAAAAA");

        //======================================================================
        // TEST 6: Pattern 0x55555555
        //======================================================================
        init_sram_pattern(32'h00030000, 256, 8'h02);
        test_crc(32'h00030000, 32'h00030100, "256 bytes of 0x55555555");

        //======================================================================
        // TEST 7: Unaligned sizes (not multiple of 4)
        //======================================================================
        init_sram_pattern(32'h00040000, 128, 8'h03);
        test_crc(32'h00040000, 32'h00040080, "128-byte boundary test");

        //======================================================================
        // Final Summary
        //======================================================================
        repeat(20) @(posedge clk);

        $display("\n========================================");
        $display("TEST SUMMARY");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);

        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***");
            $display("The optimized CRC implementation is functionally correct!");
        end else begin
            $display("\n*** SOME TESTS FAILED ***");
            $display("The optimized CRC implementation has errors!");
        end

        $display("========================================\n");

        $finish;
    end

    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    initial begin
        #50_000_000;  // 50ms timeout
        $display("\n*** TIMEOUT ***");
        $display("Test did not complete in time - possible deadlock or hang");
        $finish;
    end

endmodule
