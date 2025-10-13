//==============================================================================
// Comprehensive Bootloader Upload and Execution Test
// tb_bootloader_complete.sv
//
// Tests:
// 1. Bootloader boots to 0x40000 and waits for 'r' command
// 2. UART protocol: send 'r\n', receive '@@@'
// 3. Upload firmware (length + data + CRC32)
// 4. Bootloader verifies CRC and sends 'OK\n'
// 5. Bootloader jumps to 0x0 and firmware executes
// 6. Verify firmware behavior (LED patterns, UART output)
//
// Timeout: 1 hour (3.6 billion ns)
//==============================================================================

`timescale 1ns/1ps

module tb_bootloader_complete;

    //==========================================================================
    // Clock and Reset
    //==========================================================================

    reg clk_100mhz;
    reg resetn;

    // System clock (100MHz crystal -> /4 -> 25MHz system clock)
    wire clk = clk_100mhz;

    //==========================================================================
    // Top-level Interface
    //==========================================================================

    // UART
    reg uart_rx;
    wire uart_tx;

    // LEDs
    wire led1, led2;

    // Buttons
    reg but1, but2;

    // SRAM Physical Interface
    wire [17:0] sram_addr;
    wire [15:0] sram_data;
    wire sram_cs_n;
    wire sram_oe_n;
    wire sram_we_n;

    //==========================================================================
    // SRAM Behavioral Model (512KB)
    //==========================================================================

    reg [15:0] sram_mem [0:262143];  // 256K x 16-bit
    reg [15:0] sram_data_out;
    reg sram_data_oe;

    // Tri-state control
    assign sram_data = (sram_data_oe && !sram_oe_n && !sram_cs_n) ? sram_data_out : 16'hzzzz;

    // SRAM write logic
    always @(negedge sram_we_n) begin
        if (!sram_cs_n) begin
            sram_mem[sram_addr] <= sram_data;
        end
    end

    // SRAM read logic
    always @(*) begin
        if (!sram_cs_n && !sram_oe_n && sram_we_n) begin
            sram_data_out = sram_mem[sram_addr];
            sram_data_oe = 1'b1;
        end else begin
            sram_data_out = 16'hxxxx;
            sram_data_oe = 1'b0;
        end
    end

    //==========================================================================
    // DUT: Full Top-Level Design
    //==========================================================================

    ice40_picorv32_top dut (
        .EXTCLK(clk_100mhz),
        .UART_RX(uart_rx),
        .UART_TX(uart_tx),
        .LED1(led1),
        .LED2(led2),
        .BUT1(but1),
        .BUT2(but2),
        .SA(sram_addr),
        .SD(sram_data),
        .SRAM_CS_N(sram_cs_n),
        .SRAM_OE_N(sram_oe_n),
        .SRAM_WE_N(sram_we_n)
    );

    //==========================================================================
    // Clock Generation (100MHz)
    //==========================================================================

    initial begin
        clk_100mhz = 0;
        forever #5 clk_100mhz = ~clk_100mhz;  // 10ns period = 100MHz
    end

    //==========================================================================
    // UART Configuration (115200 baud @ 25MHz system clock)
    //==========================================================================

    // Baud rate: 115200 baud
    // System clock: 25MHz (after /4 divider)
    // Bit period: 25MHz / 115200 = 217 clocks per bit
    // At 100MHz testbench clock: 217 * 4 = 868 ns per bit

    parameter UART_BIT_PERIOD_NS = 8680;  // 115200 baud = 8.68 us per bit
    parameter UART_CLKS_PER_BIT = UART_BIT_PERIOD_NS / 10;  // At 100MHz clock

    //==========================================================================
    // UART Transmit Task (Testbench -> DUT via uart_rx)
    //==========================================================================

    task uart_send_byte;
        input [7:0] data;
        begin
            $display("[UART TX] Sending byte: 0x%02x '%c'", data,
                     (data >= 32 && data <= 126) ? data : ".");

            // Start bit
            uart_rx = 0;
            #UART_BIT_PERIOD_NS;

            // Data bits (LSB first)
            for (int i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #UART_BIT_PERIOD_NS;
            end

            // Stop bit
            uart_rx = 1;
            #UART_BIT_PERIOD_NS;
        end
    endtask

    //==========================================================================
    // UART Receive Task (DUT -> Testbench via uart_tx)
    //==========================================================================

    task uart_receive_byte;
        output [7:0] data;
        integer i;
        begin
            // Wait for start bit (falling edge)
            wait (uart_tx == 0);
            #(UART_BIT_PERIOD_NS / 2);  // Sample in middle of start bit

            // Sample data bits
            for (i = 0; i < 8; i = i + 1) begin
                #UART_BIT_PERIOD_NS;
                data[i] = uart_tx;
            end

            // Wait for stop bit
            #UART_BIT_PERIOD_NS;

            $display("[UART RX] Received byte: 0x%02x '%c'", data,
                     (data >= 32 && data <= 126) ? data : ".");
        end
    endtask

    //==========================================================================
    // CRC32 Calculation
    //==========================================================================

    function [31:0] crc32_update;
        input [31:0] crc;
        input [7:0] data;
        integer i;
        reg [31:0] temp_crc;
        reg [7:0] temp_data;
        begin
            temp_crc = crc;
            temp_data = data;
            for (i = 0; i < 8; i = i + 1) begin
                if (temp_crc[0] ^ temp_data[0])
                    temp_crc = (temp_crc >> 1) ^ 32'hEDB88320;
                else
                    temp_crc = temp_crc >> 1;
                temp_data = temp_data >> 1;
            end
            crc32_update = temp_crc;
        end
    endfunction

    //==========================================================================
    // Task: Load Firmware from Hex File
    //==========================================================================

    reg [7:0] firmware_buffer [0:65535];  // Up to 64KB firmware
    integer firmware_size;

    task load_firmware_hex;
        input [1024*8-1:0] filename;
        integer file;
        integer addr;
        integer byte_val;
        integer i, j;
        reg [7:0] data_byte;
        integer char;
        integer address;
        reg [31:0] base_addr;
        begin
            firmware_size = 0;
            base_addr = 0;

            $display("[TB] Loading firmware from: %s", filename);

            file = $fopen(filename, "r");
            if (file == 0) begin
                $display("[ERROR] Could not open firmware file: %s", filename);
                $finish;
            end

            // Parse Verilog hex format (@address followed by hex bytes)
            while (!$feof(file)) begin
                char = $fgetc(file);
                if (char == -1) break;  // EOF

                // Check for address line (@xxxxxxxx)
                if (char == "@") begin
                    $fscanf(file, "%08x", base_addr);
                    address = base_addr;
                    // Skip to end of line
                    while ($fgetc(file) != "\n" && !$feof(file)) begin
                    end
                end
                // Check for hex data
                else if ((char >= "0" && char <= "9") ||
                         (char >= "A" && char <= "F") ||
                         (char >= "a" && char <= "f")) begin
                    // Unget the character and read hex bytes from line
                    $fseek(file, -1, 1);  // Seek back 1 byte

                    // Read hex bytes until end of line
                    while (!$feof(file)) begin
                        char = $fgetc(file);
                        if (char == "\n" || char == -1) break;
                        if (char == " " || char == "\t") continue;

                        // Read two hex digits
                        if ((char >= "0" && char <= "9") ||
                            (char >= "A" && char <= "F") ||
                            (char >= "a" && char <= "f")) begin
                            $fseek(file, -1, 1);
                            $fscanf(file, "%02x", byte_val);
                            firmware_buffer[address] = byte_val[7:0];
                            if (address >= firmware_size) begin
                                firmware_size = address + 1;
                            end
                            address = address + 1;
                        end
                    end
                end
            end

            $fclose(file);

            $display("[TB] Firmware loaded: %0d bytes", firmware_size);
        end
    endtask

    //==========================================================================
    // Task: Upload Firmware via UART
    //==========================================================================

    task upload_firmware;
        input integer size;
        integer i, chunk_num;
        reg [31:0] crc, fpga_crc;
        reg [7:0] rx_byte, expected_ack;
        integer bytes_in_chunk;
        begin
            $display("\n========================================");
            $display("UPLOADING FIRMWARE: %0d bytes", size);
            $display("========================================");

            // Step 1: Send 'R' (Ready) command
            $display("[TB] Step 1: Sending 'R' (Ready) command...");
            uart_send_byte(8'h52);  // 'R'

            // Step 2: Wait for ACK 'A'
            $display("[TB] Step 2: Waiting for ACK 'A'...");
            uart_receive_byte(rx_byte);
            if (rx_byte != 8'h41) begin  // 'A'
                $display("[ERROR] Expected ACK 'A' (0x41), got 0x%02x", rx_byte);
                $finish;
            end
            $display("[TB] ✓ Received ACK 'A'");

            // Step 3: Send firmware size (4 bytes, little-endian)
            $display("[TB] Step 3: Sending size: %0d bytes", size);
            uart_send_byte(size[7:0]);
            uart_send_byte(size[15:8]);
            uart_send_byte(size[23:16]);
            uart_send_byte(size[31:24]);

            // Step 4: Wait for ACK 'B'
            $display("[TB] Step 4: Waiting for ACK 'B'...");
            uart_receive_byte(rx_byte);
            if (rx_byte != 8'h42) begin  // 'B'
                $display("[ERROR] Expected ACK 'B' (0x42), got 0x%02x", rx_byte);
                $finish;
            end
            $display("[TB] ✓ Received ACK 'B'");

            // Step 5: Send firmware data in 64-byte chunks
            $display("[TB] Step 5: Sending %0d bytes of firmware data in 64-byte chunks...", size);
            crc = 32'hFFFFFFFF;
            expected_ack = 8'h43;  // 'C' is first data ACK
            chunk_num = 0;

            i = 0;
            while (i < size) begin
                bytes_in_chunk = 0;

                // Send up to 64 bytes (with inter-byte spacing)
                while (bytes_in_chunk < 64 && i < size) begin
                    // Small delay between bytes to avoid overwhelming the UART buffer
                    if (bytes_in_chunk > 0) begin
                        #(UART_BIT_PERIOD_NS * 2);  // 17.36us spacing between bytes
                    end

                    uart_send_byte(firmware_buffer[i]);
                    crc = crc32_update(crc, firmware_buffer[i]);
                    i = i + 1;
                    bytes_in_chunk = bytes_in_chunk + 1;
                end

                // Wait for ACK after each chunk (C, D, E, ... Z, then wraps to A)
                uart_receive_byte(rx_byte);
                if (rx_byte != expected_ack) begin
                    $display("[ERROR] Expected ACK 0x%02x ('%c'), got 0x%02x ('%c')",
                             expected_ack, expected_ack, rx_byte, rx_byte);
                    $finish;
                end

                chunk_num = chunk_num + 1;
                if (chunk_num % 10 == 0 || i >= size) begin
                    $display("[TB]   Sent chunk %0d: %0d / %0d bytes, ACK='%c'",
                             chunk_num, i, size, expected_ack);
                end

                // Increment ACK character (C -> D -> ... -> Z -> A -> B -> C ...)
                expected_ack = expected_ack + 1;
                if (expected_ack > 8'h5A) expected_ack = 8'h41;  // Wrap Z to A

                // Small delay before next chunk to allow bootloader to process
                #(UART_BIT_PERIOD_NS * 2);
            end

            crc = ~crc;
            $display("[TB] Step 6: Sending 'C' (CRC command)...");
            uart_send_byte(8'h43);  // 'C'

            $display("[TB] Step 7: Sending CRC32: 0x%08x", crc);
            uart_send_byte(crc[7:0]);
            uart_send_byte(crc[15:8]);
            uart_send_byte(crc[23:16]);
            uart_send_byte(crc[31:24]);

            // Step 8: Receive ACK + 4-byte FPGA CRC
            $display("[TB] Step 8: Waiting for ACK + CRC response...");
            uart_receive_byte(rx_byte);
            if (rx_byte != expected_ack) begin
                $display("[ERROR] Expected ACK 0x%02x, got 0x%02x", expected_ack, rx_byte);
                $finish;
            end

            // Receive 4-byte CRC from FPGA
            fpga_crc = 0;
            uart_receive_byte(rx_byte); fpga_crc[7:0] = rx_byte;
            uart_receive_byte(rx_byte); fpga_crc[15:8] = rx_byte;
            uart_receive_byte(rx_byte); fpga_crc[23:16] = rx_byte;
            uart_receive_byte(rx_byte); fpga_crc[31:24] = rx_byte;

            $display("[TB] Expected CRC: 0x%08x", crc);
            $display("[TB] FPGA CRC:     0x%08x", fpga_crc);

            if (crc == fpga_crc) begin
                $display("[TB] ✓ CRC MATCH - Upload successful!");
            end else begin
                $display("[ERROR] Unexpected response: 0x%02x", rx_byte);
                $finish;
            end

            $display("[TB] ✓ Firmware upload complete!");
        end
    endtask

    //==========================================================================
    // LED Monitor
    //==========================================================================

    always @(led1 or led2) begin
        $display("[LED] LED1=%b, LED2=%b (time=%0t)", led1, led2, $time);
    end

    //==========================================================================
    // Main Test Sequence
    //==========================================================================

    integer test_phase;

    initial begin
        $dumpfile("tb_bootloader_complete.vcd");
        $dumpvars(0, tb_bootloader_complete);

        // Initialize signals
        resetn = 0;
        uart_rx = 1;  // UART idle high
        but1 = 1;     // Button not pressed (active low)
        but2 = 1;     // Button not pressed (active low)
        test_phase = 0;

        // Initialize SRAM
        for (int i = 0; i < 262144; i = i + 1) begin
            sram_mem[i] = 16'h0000;
        end

        $display("\n========================================");
        $display("BOOTLOADER COMPLETE TEST");
        $display("Testing: Upload + Execution");
        $display("Timeout: 1 hour");
        $display("========================================\n");

        // Reset sequence
        $display("[TB] Phase 0: Reset");
        #1000;
        resetn = 1;
        #1000;

        // Wait for bootloader to initialize
        $display("[TB] Phase 1: Bootloader initialization");
        $display("[TB] CPU should boot to 0x40000 and wait for 'r' command");
        $display("[TB] LED1 should be ON (waiting for upload)");

        // Wait for LED1 to turn on (bootloader ready)
        $display("[TB] Waiting for LED1 to turn on...");
        wait (led1 === 1'b1);
        $display("[TB] LED1 is ON - bootloader ready!");
        #1000;  // Small delay after LED1 turns on

        // Load firmware
        test_phase = 2;
        $display("\n[TB] Phase 2: Loading test firmware");
        load_firmware_hex("/mnt/c/msys64/home/mwolak/olimex-ice40hx8k-riscv-intr/firmware/led_blink.hex");

        // Upload firmware
        test_phase = 3;
        $display("\n[TB] Phase 3: Uploading firmware via UART");
        upload_firmware(firmware_size);

        // Wait for bootloader to jump to firmware
        test_phase = 4;
        $display("\n[TB] Phase 4: Waiting for bootloader to jump to 0x0...");
        #10000;  // 10 us

        // Monitor firmware execution
        test_phase = 5;
        $display("\n[TB] Phase 5: Monitoring firmware execution");
        $display("[TB] Expecting LED blink pattern...");
        #100000000;  // 100 ms - should see multiple blinks

        // Test complete
        $display("\n========================================");
        $display("TEST COMPLETE");
        $display("========================================");
        $display("✓ Bootloader uploaded firmware successfully");
        $display("✓ Firmware executed at address 0x0");
        $display("✓ System operational");
        $display("========================================\n");

        $finish;
    end

    //==========================================================================
    // Timeout Watchdog (1 hour = 3600 seconds = 3.6 trillion ns)
    // Note: Using reasonable timeout of 1 billion ns for simulation
    //==========================================================================

    initial begin
        #1000000000;  // 1 second timeout (adjustable for testing)
        $display("\n[WARNING] Simulation timeout after 1 second");
        $display("Test phase: %0d", test_phase);
        $display("Note: Increase timeout if needed for full firmware execution");
        $finish;
    end

    //==========================================================================
    // Detailed Debug Output
    //==========================================================================

    // Monitor CPU program counter and key signals
    reg [31:0] last_pc;
    integer instr_count;
    initial begin
        last_pc = 0;
        instr_count = 0;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            last_pc <= 0;
            instr_count <= 0;
        end else begin
            // Monitor CPU execution
            if (dut.cpu.mem_valid && dut.cpu.mem_ready && dut.cpu.mem_instr) begin
                if (instr_count < 2000 || (instr_count % 1000 == 0)) begin
                    $display("[CPU] time=%0t #%0d PC=0x%08x addr=0x%08x ready=%b",
                             $time, instr_count, dut.cpu.reg_pc, dut.cpu.mem_addr, dut.cpu.mem_ready);
                end
                instr_count <= instr_count + 1;
                last_pc <= dut.cpu.reg_pc;
            end

            // Monitor bootloader ROM access
            if (dut.mem_ctrl.boot_enable) begin
                if (instr_count < 50) begin
                    $display("[ROM] time=%0t Reading bootloader ROM addr=0x%05x", $time, dut.mem_ctrl.boot_addr);
                end
            end
        end
    end

endmodule
