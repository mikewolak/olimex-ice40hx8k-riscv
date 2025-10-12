//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// mem_controller.v - Memory Controller with SRAM Interface
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module mem_controller (
    input wire clk,
    input wire resetn,

    // PicoRV32 Memory Interface
    input wire        cpu_mem_valid,
    input wire        cpu_mem_instr,
    output reg        cpu_mem_ready,
    input wire [31:0] cpu_mem_addr,
    input wire [31:0] cpu_mem_wdata,
    input wire [ 3:0] cpu_mem_wstrb,
    output reg [31:0] cpu_mem_rdata,

    // Bootloader ROM Interface (read-only)
    output reg        boot_enable,
    output reg [12:0] boot_addr,
    input wire [31:0] boot_rdata,

    // SRAM Interface (via sram_proc_new)
    output reg        sram_start,
    input wire        sram_busy,
    input wire        sram_done,
    output reg [ 7:0] sram_cmd,
    output reg [31:0] sram_addr,
    output reg [31:0] sram_wdata,
    output reg [ 3:0] sram_wstrb,
    input wire [31:0] sram_rdata,

    // MMIO Interface
    output reg        mmio_valid,
    output reg        mmio_write,
    output reg [31:0] mmio_addr,
    output reg [31:0] mmio_wdata,
    output reg [ 3:0] mmio_wstrb,
    input wire [31:0] mmio_rdata,
    input wire        mmio_ready
);

    // Memory Map
    localparam SRAM_BASE = 32'h00000000;
    localparam SRAM_END  = 32'h0007FFFF;  // 512 KB
    localparam BOOT_BASE = 32'h00010000;  // Bootloader ROM
    localparam BOOT_END  = 32'h00011FFF;  // 8 KB
    localparam MMIO_BASE = 32'h80000000;
    localparam MMIO_END  = 32'h800000FF;

    // SRAM Commands
    localparam CMD_READ  = 8'h01;
    localparam CMD_WRITE = 8'h02;

    // State Machine
    localparam STATE_IDLE      = 3'h0;
    localparam STATE_SRAM_WAIT = 3'h1;
    localparam STATE_MMIO_WAIT = 3'h2;
    localparam STATE_BOOT_WAIT = 3'h3;
    localparam STATE_DONE      = 3'h4;

    reg [2:0] state;
    reg [31:0] saved_addr;
    reg saved_is_write;

    // Address Decode
    wire addr_is_sram = (cpu_mem_addr >= SRAM_BASE) && (cpu_mem_addr <= SRAM_END);
    wire addr_is_boot = (cpu_mem_addr >= BOOT_BASE) && (cpu_mem_addr <= BOOT_END);
    wire addr_is_mmio = (cpu_mem_addr >= MMIO_BASE) && (cpu_mem_addr <= MMIO_END);

    always @(posedge clk) begin
        if (!resetn) begin
            state <= STATE_IDLE;
            cpu_mem_ready <= 1'b0;
            cpu_mem_rdata <= 32'h0;
            boot_enable <= 1'b0;
            boot_addr <= 13'h0;
            sram_start <= 1'b0;
            sram_cmd <= 8'h0;
            sram_addr <= 32'h0;
            sram_wdata <= 32'h0;
            sram_wstrb <= 4'h0;
            mmio_valid <= 1'b0;
            mmio_write <= 1'b0;
            mmio_addr <= 32'h0;
            mmio_wdata <= 32'h0;
            mmio_wstrb <= 4'h0;
            saved_addr <= 32'h0;
            saved_is_write <= 1'b0;
        end else begin
            // Default: clear control signals
            cpu_mem_ready <= 1'b0;
            boot_enable <= 1'b0;
            sram_start <= 1'b0;
            mmio_valid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (cpu_mem_valid && !cpu_mem_ready) begin
                        saved_addr <= cpu_mem_addr;
                        saved_is_write <= |cpu_mem_wstrb;

                        if (addr_is_boot && !(|cpu_mem_wstrb)) begin
                            // Route to Bootloader ROM (read-only)
                            boot_enable <= 1'b1;
                            boot_addr <= cpu_mem_addr[12:0];  // 8KB address space
                            state <= STATE_BOOT_WAIT;

                            // synthesis translate_off
                            $display("[MEM_CTRL] BOOT ROM read: addr=0x%08x", cpu_mem_addr);
                            // synthesis translate_on

                        end else if (addr_is_sram) begin
                            // Route to SRAM
                            sram_cmd <= |cpu_mem_wstrb ? CMD_WRITE : CMD_READ;
                            sram_addr <= cpu_mem_addr;
                            sram_wdata <= cpu_mem_wdata;
                            sram_wstrb <= cpu_mem_wstrb;
                            sram_start <= 1'b1;
                            state <= STATE_SRAM_WAIT;

                            // synthesis translate_off
                            $display("[MEM_CTRL] SRAM access: addr=0x%08x %s data=0x%08x wstrb=0x%01x",
                                     cpu_mem_addr, |cpu_mem_wstrb ? "WRITE" : "READ",
                                     cpu_mem_wdata, cpu_mem_wstrb);
                            // synthesis translate_on

                        end else if (addr_is_mmio) begin
                            // Route to MMIO
                            mmio_valid <= 1'b1;
                            mmio_write <= |cpu_mem_wstrb;
                            mmio_addr <= cpu_mem_addr;
                            mmio_wdata <= cpu_mem_wdata;
                            mmio_wstrb <= cpu_mem_wstrb;
                            state <= STATE_MMIO_WAIT;

                            // synthesis translate_off
                            $display("[MEM_CTRL] MMIO access: addr=0x%08x %s data=0x%08x",
                                     cpu_mem_addr, |cpu_mem_wstrb ? "WRITE" : "READ",
                                     cpu_mem_wdata);
                            // synthesis translate_on

                        end else begin
                            // Invalid address - return 0 immediately
                            cpu_mem_rdata <= 32'h0;
                            cpu_mem_ready <= 1'b1;

                            // synthesis translate_off
                            $display("[MEM_CTRL] Invalid address: 0x%08x", cpu_mem_addr);
                            // synthesis translate_on
                        end
                    end
                end

                STATE_BOOT_WAIT: begin
                    // Bootloader ROM has 1-cycle latency
                    cpu_mem_rdata <= boot_rdata;
                    cpu_mem_ready <= 1'b1;
                    state <= STATE_IDLE;

                    // synthesis translate_off
                    $display("[MEM_CTRL] BOOT ROM read complete: data=0x%08x", boot_rdata);
                    // synthesis translate_on
                end

                STATE_SRAM_WAIT: begin
                    if (sram_done) begin
                        cpu_mem_rdata <= sram_rdata;
                        cpu_mem_ready <= 1'b1;
                        state <= STATE_IDLE;

                        // synthesis translate_off
                        if (!saved_is_write) begin
                            $display("[MEM_CTRL] SRAM read complete: data=0x%08x", sram_rdata);
                        end
                        // synthesis translate_on
                    end
                end

                STATE_MMIO_WAIT: begin
                    if (mmio_ready) begin
                        cpu_mem_rdata <= mmio_rdata;
                        cpu_mem_ready <= 1'b1;
                        state <= STATE_IDLE;

                        // synthesis translate_off
                        if (!saved_is_write) begin
                            $display("[MEM_CTRL] MMIO read complete: data=0x%08x", mmio_rdata);
                        end
                        // synthesis translate_on
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
