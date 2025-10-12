//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// ice40_picorv32_top.v - Top-Level FPGA Design
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module ice40_picorv32_top (
    // Clock and Reset
    input wire EXTCLK,          // 100MHz external clock (J3)

    // User Interface
    input wire BUT1,            // User button 1 (K11)
    input wire BUT2,            // User button 2 (P13)
    output wire LED1,           // User LED 1 (M12)
    output wire LED2,           // User LED 2 (R16)

    // UART Interface
    input wire UART_RX,         // UART Receive (E4)
    output wire UART_TX,        // UART Transmit (B2)

    // SRAM Interface (K6R4016V1D-TC10)
    output wire [17:0] SA,      // SRAM Address bus
    inout wire [15:0] SD,       // SRAM Data bus
    output wire SRAM_CS_N,      // SRAM Chip Select (active low)
    output wire SRAM_OE_N,      // SRAM Output Enable (active low)
    output wire SRAM_WE_N       // SRAM Write Enable (active low)
);

    // Clock and reset management
    // Divide 100 MHz crystal by 4 to get 25 MHz system clock (meets timing at 46.96 MHz max)
    reg [1:0] clk_div = 0;
    always @(posedge EXTCLK) begin
        clk_div <= clk_div + 1;
    end
    wire clk = clk_div[1];

    reg [7:0] reset_counter = 0;
    wire global_resetn = &reset_counter;

    // Forward declarations for reset logic
    wire cpu_reset_from_loader;  // Still wired to firmware_loader but ignored for now
    wire shell_cpu_run, shell_cpu_stop;
    reg cpu_reset_from_shell;
    // DEVELOPMENT MODE: Shell has full manual control of CPU reset via 'r' and 's' commands
    // In production: would use "& ~cpu_reset_from_loader" to let firmware loader control reset
    wire cpu_resetn = global_resetn & ~cpu_reset_from_shell;

    always @(posedge clk) begin
        if (!global_resetn)
            reset_counter <= reset_counter + 1;
    end

    // CPU reset control - shell can override loader
    always @(posedge clk) begin
        if (!global_resetn) begin
            cpu_reset_from_shell <= 1'b1;  // Hold CPU in reset initially
        end else begin
            if (shell_cpu_run) begin
                cpu_reset_from_shell <= 1'b0;  // Release from reset
            end else if (shell_cpu_stop) begin
                cpu_reset_from_shell <= 1'b1;  // Hold in reset
            end
        end
    end

    // Mode Controller signals
    wire shell_mode_switch = shell_cpu_run;   // 'r' command switches to app mode
    wire shell_mode_restore;  // 's' command in shell or CPU write to MODE_CONTROL
    wire cpu_mode_write;
    wire [31:0] cpu_mode_wdata;
    wire [31:0] mode_reg_rdata;
    wire app_mode;  // 0 = Shell mode, 1 = Application mode

    // Button synchronizers (2-stage, using global reset, not cpu reset)
    // Active-low buttons inverted to active-high (1 = pressed)
    reg but1_sync1, but1_sync2;
    reg but2_sync1, but2_sync2;

    always @(posedge clk) begin
        if (!global_resetn) begin
            but1_sync1 <= 1'b0;
            but1_sync2 <= 1'b0;
            but2_sync1 <= 1'b0;
            but2_sync2 <= 1'b0;
        end else begin
            but1_sync1 <= ~BUT1;  // Invert active-low to active-high
            but1_sync2 <= but1_sync1;
            but2_sync1 <= ~BUT2;
            but2_sync2 <= but2_sync1;
        end
    end

    // LED Control - multiplexed based on mode
    wire led1_mmio, led2_mmio;
    wire led1_shell = 1'b0;  // Shell doesn't control LEDs
    wire led2_shell = 1'b0;
    assign LED1 = app_mode ? led1_mmio : led1_shell;
    assign LED2 = app_mode ? led2_mmio : led2_shell;

    // UART signals
    wire [7:0] uart_rx_data;
    wire uart_rx_data_valid;
    wire uart_tx_busy, uart_rx_busy, uart_rx_error;

    // Forward declarations for UART TX multiplexing
    wire [7:0] shell_uart_tx_data;
    wire shell_uart_tx_valid;
    wire fw_loader_busy;
    wire [7:0] fw_loader_uart_tx_data;
    wire fw_loader_uart_tx_valid;
    wire [7:0] mmio_uart_tx_data;
    wire mmio_uart_tx_valid;

    // UART TX multiplexing
    // Priority: Firmware loader > Mode-based (Shell or App)
    wire [7:0] uart_tx_data_mux = fw_loader_busy ? fw_loader_uart_tx_data :
                                  app_mode ? mmio_uart_tx_data :
                                  shell_uart_tx_data;
    wire uart_tx_valid_mux = fw_loader_busy ? fw_loader_uart_tx_valid :
                             app_mode ? mmio_uart_tx_valid :
                             shell_uart_tx_valid;

    // UART Core (25 MHz clock after divide-by-4)
    uart #(
        .CLK_FREQ(25_000_000),
        .BAUD_RATE(115_200),
        .OS_RATE(16),
        .D_WIDTH(8),
        .PARITY(0),
        .PARITY_EO(1'b0)
    ) uart_core (
        .clk(clk),
        .reset_n(global_resetn),
        .tx_ena(uart_tx_valid_mux),
        .tx_data(uart_tx_data_mux),
        .rx(UART_RX),
        .rx_busy(uart_rx_busy),
        .rx_error(uart_rx_error),
        .rx_data(uart_rx_data),
        .rx_data_valid(uart_rx_data_valid),
        .tx_busy(uart_tx_busy),
        .tx(UART_TX)
    );

    // Circular Buffer for UART RX
    // Priority: Firmware loader > App (CPU) > Shell
    // UART RX buffer is shared - muxed based on mode
    wire fw_loader_buffer_rd_en, shell_buffer_rd_en, mmio_buffer_rd_en;
    wire [7:0] buffer_rd_data;
    wire buffer_full, buffer_empty;
    wire shell_buffer_clear;
    wire buffer_wr_en = uart_rx_data_valid && !buffer_full;
    wire buffer_rd_en = fw_loader_busy ? fw_loader_buffer_rd_en :
                        app_mode ? mmio_buffer_rd_en :
                        shell_buffer_rd_en;

    circular_buffer #(
        .DATA_WIDTH(8),
        .ADDR_BITS(6)
    ) uart_circular_buffer (
        .clk(clk),
        .reset_n(global_resetn),
        .clear(shell_buffer_clear),
        .wr_en(buffer_wr_en),
        .wr_data(uart_rx_data),
        .full(buffer_full),
        .rd_en(buffer_rd_en),
        .rd_data(buffer_rd_data),
        .empty(buffer_empty)
    );

    // SRAM 16-bit driver interface
    wire [18:0] sram_addr_16_shell, sram_addr_16_loader, sram_addr_16_cpu;
    wire [15:0] sram_wdata_16_shell, sram_wdata_16_loader, sram_wdata_16_cpu;
    wire [15:0] sram_rdata_16;
    wire sram_we_shell, sram_we_loader, sram_we_cpu;
    wire sram_valid_16_shell, sram_valid_16_loader, sram_valid_16_cpu;
    wire sram_ready_16;
    wire shell_active, loader_active, cpu_active;

    // SRAM arbiter - shell priority (for debugging), then loader, then CPU
    wire [18:0] sram_addr_16_mux = shell_active ? sram_addr_16_shell :
                                    loader_active ? sram_addr_16_loader : sram_addr_16_cpu;
    wire [15:0] sram_wdata_16_mux = shell_active ? sram_wdata_16_shell :
                                     loader_active ? sram_wdata_16_loader : sram_wdata_16_cpu;
    wire sram_we_mux = shell_active ? sram_we_shell :
                       loader_active ? sram_we_loader : sram_we_cpu;
    wire sram_valid_16_mux = shell_active ? sram_valid_16_shell :
                             loader_active ? sram_valid_16_loader : sram_valid_16_cpu;

    // *** CLEAN-ROOM SRAM Driver with COOLDOWN fix ***
    sram_driver_new sram_drv (
        .clk(clk),
        .resetn(global_resetn),
        .valid(sram_valid_16_mux),
        .ready(sram_ready_16),
        .we(sram_we_mux),
        .addr(sram_addr_16_mux),
        .wdata(sram_wdata_16_mux),
        .rdata(sram_rdata_16),
        .sram_addr(SA),
        .sram_data(SD),
        .sram_cs_n(SRAM_CS_N),
        .sram_oe_n(SRAM_OE_N),
        .sram_we_n(SRAM_WE_N)
    );

    // Shell and firmware loader signals (UART TX already declared above)
    wire shell_uart_tx_ready = ~uart_tx_busy;

    wire sram_proc_start;
    wire [7:0] sram_proc_cmd;
    wire [31:0] sram_proc_addr;
    wire [31:0] sram_proc_data;
    wire sram_proc_busy;
    wire sram_proc_done;
    wire [31:0] sram_proc_result;
    wire [15:0] sram_proc_result_low;
    wire [15:0] sram_proc_result_high;

    wire fw_loader_start;
    wire fw_loader_done;
    wire fw_loader_error;
    wire [7:0] fw_loader_nak_reason;

    assign shell_active = sram_proc_busy;
    assign loader_active = fw_loader_busy;
    assign cpu_active = !loader_active && !shell_active;

    // Shell Module
    shell shell_inst (
        .clk(clk),
        .resetn(global_resetn),
        .buffer_rd_data(buffer_rd_data),
        .buffer_rd_en(shell_buffer_rd_en),
        .buffer_empty(buffer_empty),
        .buffer_clear(shell_buffer_clear),
        .uart_tx_data(shell_uart_tx_data),
        .uart_tx_valid(shell_uart_tx_valid),
        .uart_tx_ready(shell_uart_tx_ready),
        .sram_proc_start(sram_proc_start),
        .sram_proc_cmd(sram_proc_cmd),
        .sram_proc_addr(sram_proc_addr),
        .sram_proc_data(sram_proc_data),
        .sram_proc_busy(sram_proc_busy),
        .sram_proc_done(sram_proc_done),
        .sram_proc_result(sram_proc_result),
        .sram_proc_result_low(sram_proc_result_low),
        .sram_proc_result_high(sram_proc_result_high),
        .fw_loader_start(fw_loader_start),
        .fw_loader_busy(fw_loader_busy),
        .fw_loader_done(fw_loader_done),
        .fw_loader_error(fw_loader_error),
        .fw_loader_nak_reason(fw_loader_nak_reason),
        .cpu_run(shell_cpu_run),
        .cpu_stop(shell_cpu_stop),
        .mode_restore(shell_mode_restore)
    );

    // *** CLEAN-ROOM SRAM Processor ***
    sram_proc_new sram_proc_inst (
        .clk(clk),
        .resetn(global_resetn),
        .start(sram_proc_start),
        .cmd(sram_proc_cmd),
        .addr_in(sram_proc_addr),
        .data_in(sram_proc_data),
        .mem_wstrb(4'b1111),              // Shell always does full 32-bit writes
        .busy(sram_proc_busy),
        .done(sram_proc_done),
        .result(sram_proc_result),
        .result_low(sram_proc_result_low),
        .result_high(sram_proc_result_high),
        .rx_byte(8'h00),
        .rx_valid(1'b0),
        .tx_data(),
        .tx_valid(),
        .tx_ready(1'b1),
        .sram_valid(sram_valid_16_shell),
        .sram_ready(sram_ready_16),
        .sram_we(sram_we_shell),
        .sram_addr_16(sram_addr_16_shell),
        .sram_wdata_16(sram_wdata_16_shell),
        .sram_rdata_16(sram_rdata_16)
    );

    // Firmware Loader Module - Now using 16-bit SRAM interface
    firmware_loader fw_loader_inst (
        .clk(clk),
        .resetn(global_resetn),
        .start(fw_loader_start),
        .busy(fw_loader_busy),
        .done(fw_loader_done),
        .error(fw_loader_error),
        .nak_reason(fw_loader_nak_reason),
        .buffer_rd_data(buffer_rd_data),
        .buffer_rd_en(fw_loader_buffer_rd_en),
        .buffer_empty(buffer_empty),
        .uart_tx_data(fw_loader_uart_tx_data),
        .uart_tx_valid(fw_loader_uart_tx_valid),
        .uart_tx_ready(shell_uart_tx_ready),
        .sram_valid(sram_valid_16_loader),
        .sram_ready(sram_ready_16),
        .sram_we(sram_we_loader),
        .sram_addr_16(sram_addr_16_loader),
        .sram_wdata_16(sram_wdata_16_loader),
        .sram_rdata_16(sram_rdata_16),
        .cpu_reset(cpu_reset_from_loader)
    );

    // ========================================
    // PicoRV32 CPU + Memory-Mapped I/O
    // ========================================

    // PicoRV32 Memory Interface
    wire        cpu_mem_valid;
    wire        cpu_mem_instr;
    wire        cpu_mem_ready;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [ 3:0] cpu_mem_wstrb;
    wire [31:0] cpu_mem_rdata;

    // PicoRV32 CPU Core - RV32E (16 regs) to save space
    picorv32 #(
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .ENABLE_REGS_16_31(0),          // RV32E: only 16 registers
        .ENABLE_REGS_DUALPORT(0),
        .LATCHED_MEM_RDATA(0),
        .TWO_STAGE_SHIFT(1),
        .BARREL_SHIFTER(0),
        .TWO_CYCLE_COMPARE(0),
        .TWO_CYCLE_ALU(0),
        .COMPRESSED_ISA(0),
        .CATCH_MISALIGN(0),
        .CATCH_ILLINSN(0),
        .ENABLE_PCPI(0),
        .ENABLE_MUL(0),
        .ENABLE_FAST_MUL(0),
        .ENABLE_DIV(0),
        .ENABLE_IRQ(0),
        .ENABLE_IRQ_QREGS(0),
        .ENABLE_IRQ_TIMER(0),
        .ENABLE_TRACE(0),
        .REGS_INIT_ZERO(1),
        .MASKED_IRQ(32'h00000000),
        .LATCHED_IRQ(32'hffffffff),
        .PROGADDR_RESET(32'h00000000),
        .PROGADDR_IRQ(32'h00000010),
        .STACKADDR(32'h00080000)
    ) cpu (
        .clk(clk),
        .resetn(cpu_resetn),
        .trap(),

        .mem_valid(cpu_mem_valid),
        .mem_instr(cpu_mem_instr),
        .mem_ready(cpu_mem_ready),
        .mem_addr(cpu_mem_addr),
        .mem_wdata(cpu_mem_wdata),
        .mem_wstrb(cpu_mem_wstrb),
        .mem_rdata(cpu_mem_rdata),

        .mem_la_read(),
        .mem_la_write(),
        .mem_la_addr(),
        .mem_la_wdata(),
        .mem_la_wstrb(),

        .pcpi_valid(),
        .pcpi_insn(),
        .pcpi_rs1(),
        .pcpi_rs2(),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'h0),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),

        .irq(32'h0),
        .eoi()
    );

    // Memory Controller signals
    wire        mem_ctrl_sram_start;
    wire        mem_ctrl_sram_busy;
    wire        mem_ctrl_sram_done;
    wire [ 7:0] mem_ctrl_sram_cmd;
    wire [31:0] mem_ctrl_sram_addr;
    wire [31:0] mem_ctrl_sram_wdata;
    wire [ 3:0] mem_ctrl_sram_wstrb;
    wire [31:0] mem_ctrl_sram_rdata;

    // MMIO signals
    wire        mmio_valid;
    wire        mmio_write;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [ 3:0] mmio_wstrb;
    wire [31:0] mmio_rdata;
    wire        mmio_ready;

    // Memory Controller - Routes CPU to SRAM or MMIO
    mem_controller mem_ctrl (
        .clk(clk),
        .resetn(cpu_resetn),

        // PicoRV32 Interface
        .cpu_mem_valid(cpu_mem_valid),
        .cpu_mem_instr(cpu_mem_instr),
        .cpu_mem_ready(cpu_mem_ready),
        .cpu_mem_addr(cpu_mem_addr),
        .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_wstrb(cpu_mem_wstrb),
        .cpu_mem_rdata(cpu_mem_rdata),

        // SRAM Interface (via sram_proc_new)
        .sram_start(mem_ctrl_sram_start),
        .sram_busy(mem_ctrl_sram_busy),
        .sram_done(mem_ctrl_sram_done),
        .sram_cmd(mem_ctrl_sram_cmd),
        .sram_addr(mem_ctrl_sram_addr),
        .sram_wdata(mem_ctrl_sram_wdata),
        .sram_wstrb(mem_ctrl_sram_wstrb),
        .sram_rdata(mem_ctrl_sram_rdata),

        // MMIO Interface
        .mmio_valid(mmio_valid),
        .mmio_write(mmio_write),
        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_wstrb(mmio_wstrb),
        .mmio_rdata(mmio_rdata),
        .mmio_ready(mmio_ready)
    );

    // SRAM Processor for CPU (via Memory Controller)
    sram_proc_new sram_proc_cpu (
        .clk(clk),
        .resetn(cpu_resetn),
        .start(mem_ctrl_sram_start),
        .cmd(mem_ctrl_sram_cmd),
        .addr_in(mem_ctrl_sram_addr),
        .data_in(mem_ctrl_sram_wdata),
        .mem_wstrb(mem_ctrl_sram_wstrb),
        .busy(mem_ctrl_sram_busy),
        .done(mem_ctrl_sram_done),
        .result(mem_ctrl_sram_rdata),
        .result_low(),
        .result_high(),
        .rx_byte(8'h00),
        .rx_valid(1'b0),
        .tx_data(),
        .tx_valid(),
        .tx_ready(1'b1),
        .sram_valid(sram_valid_16_cpu),
        .sram_ready(sram_ready_16),
        .sram_we(sram_we_cpu),
        .sram_addr_16(sram_addr_16_cpu),
        .sram_wdata_16(sram_wdata_16_cpu),
        .sram_rdata_16(sram_rdata_16)
    );

    // Mode Controller - Controls Shell/App mode switching
    mode_controller mode_ctrl (
        .clk(clk),
        .resetn(global_resetn),

        // Shell control interface
        .shell_mode_switch(shell_mode_switch),   // 'r' command
        .shell_mode_restore(shell_mode_restore), // 's' command

        // CPU/MMIO control interface
        .cpu_mode_write(cpu_mode_write),
        .cpu_mode_wdata(cpu_mode_wdata),
        .mode_reg_rdata(mode_reg_rdata),

        // Mode output
        .app_mode(app_mode)
    );

    // MMIO Peripherals - UART, LED, and Button registers
    mmio_peripherals mmio (
        .clk(clk),
        .resetn(cpu_resetn),

        // MMIO Interface
        .mmio_valid(mmio_valid),
        .mmio_write(mmio_write),
        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_wstrb(mmio_wstrb),
        .mmio_rdata(mmio_rdata),
        .mmio_ready(mmio_ready),

        // UART TX Interface
        .uart_tx_data(mmio_uart_tx_data),
        .uart_tx_valid(mmio_uart_tx_valid),
        .uart_tx_busy(uart_tx_busy),

        // UART RX Interface (circular buffer)
        .uart_rx_data(buffer_rd_data),
        .uart_rx_rd_en(mmio_buffer_rd_en),
        .uart_rx_empty(buffer_empty),

        // LED Outputs
        .led1(led1_mmio),
        .led2(led2_mmio),

        // Button Inputs (pre-synchronized)
        .but1_sync(but1_sync2),
        .but2_sync(but2_sync2),

        // Mode Controller Interface
        .mode_write(cpu_mode_write),
        .mode_wdata(cpu_mode_wdata),
        .mode_rdata(mode_reg_rdata)
    );

endmodule
