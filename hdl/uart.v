//==============================================================================
// Olimex iCE40HX8K-EVB RISC-V Platform
// uart.v - UART Controller with TX/RX FIFO
//
// Copyright (c) October 2025 Michael Wolak
// Email: mikewolak@gmail.com, mike@epromfoundry.com
//
// NOT FOR COMMERCIAL USE
// Educational and research purposes only
//==============================================================================

module uart #(
    parameter CLK_FREQ = 100_000_000,  // frequency of system clock in Hertz
    parameter BAUD_RATE = 115_200,     // data link baud rate in bits/second
    parameter OS_RATE = 16,            // oversampling rate to find center of receive bits
    parameter D_WIDTH = 8,             // data bus width
    parameter PARITY = 0,              // 0 for no parity, 1 for parity
    parameter PARITY_EO = 1'b0         // 1'b0 for even, 1'b1 for odd parity
) (
    input wire clk,                           // system clock
    input wire reset_n,                       // asynchronous reset
    input wire tx_ena,                        // initiate transmission
    input wire [D_WIDTH-1:0] tx_data,         // data to transmit
    input wire rx,                            // receive pin
    output reg rx_busy,                       // data reception in progress
    output reg rx_error,                      // start, parity, or stop bit error detected
    output reg [D_WIDTH-1:0] rx_data,         // data received
    output reg rx_data_valid,                 // pulse when new byte received
    output reg tx_busy,                       // transmission in progress
    output reg tx                             // transmit pin
);

    // State machine types
    localparam TX_IDLE = 1'b0, TX_TRANSMIT = 1'b1;
    localparam RX_IDLE = 1'b0, RX_RECEIVE = 1'b1;
    
    // State machine registers
    reg tx_state, rx_state;
    
    // Clock enable pulses
    reg baud_pulse;
    reg os_pulse;
    
    // Parity calculation
    reg parity_error;
    reg [D_WIDTH:0] rx_parity;
    reg [D_WIDTH:0] tx_parity;
    
    // Buffers
    reg [PARITY+D_WIDTH:0] rx_buffer;
    reg [PARITY+D_WIDTH+1:0] tx_buffer;
    
    // Counters
    integer count_baud;
    integer count_os;
    integer rx_count;
    integer os_count;
    integer tx_count;
    
    // Baud rate and oversampling rate generation
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            baud_pulse <= 1'b0;
            os_pulse <= 1'b0;
            count_baud <= 0;
            count_os <= 0;
        end else begin
            // Create baud enable pulse
            if (count_baud < CLK_FREQ/BAUD_RATE-1) begin
                count_baud <= count_baud + 1;
                baud_pulse <= 1'b0;
            end else begin
                count_baud <= 0;
                baud_pulse <= 1'b1;
                count_os <= 0;  // reset oversampling counter to avoid cumulative error
            end
            
            // Create oversampling enable pulse
            if (count_os < CLK_FREQ/BAUD_RATE/OS_RATE-1) begin
                count_os <= count_os + 1;
                os_pulse <= 1'b0;
            end else begin
                count_os <= 0;
                os_pulse <= 1'b1;
            end
        end
    end
    
    // Receive state machine
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            os_count <= 0;
            rx_count <= 0;
            rx_busy <= 1'b0;
            rx_error <= 1'b0;
            rx_data <= {D_WIDTH{1'b0}};
            rx_data_valid <= 1'b0;
            rx_state <= RX_IDLE;
            rx_buffer <= {(PARITY+D_WIDTH+1){1'b0}};
        end else begin
            rx_data_valid <= 1'b0;  // Clear data valid pulse every clock cycle

            if (os_pulse) begin
            
            case (rx_state)
                RX_IDLE: begin
                    rx_busy <= 1'b0;
                    if (rx == 1'b0) begin  // start bit might be present
                        if (os_count < OS_RATE/2) begin
                            os_count <= os_count + 1;
                            rx_state <= RX_IDLE;
                        end else begin
                            os_count <= 0;
                            rx_count <= 0;
                            rx_busy <= 1'b1;
                            rx_buffer <= {rx, rx_buffer[PARITY+D_WIDTH:1]};
                            rx_state <= RX_RECEIVE;
                        end
                    end else begin
                        os_count <= 0;
                        rx_state <= RX_IDLE;
                    end
                end
                
                RX_RECEIVE: begin
                    if (os_count < OS_RATE-1) begin
                        os_count <= os_count + 1;
                        rx_state <= RX_RECEIVE;
                    end else if (rx_count < PARITY+D_WIDTH) begin
                        os_count <= 0;
                        rx_count <= rx_count + 1;
                        rx_buffer <= {rx, rx_buffer[PARITY+D_WIDTH:1]};
                        rx_state <= RX_RECEIVE;
                    end else begin
                        // Center of stop bit
                        rx_data <= rx_buffer[D_WIDTH:1];
                        rx_data_valid <= 1'b1;  // Pulse for new data
                        rx_error <= rx_buffer[0] | parity_error | ~rx;
                        rx_busy <= 1'b0;
                        rx_state <= RX_IDLE;
                    end
                end
            endcase
            end
        end
    end
    
    // Receive parity calculation
    integer i;
    always @(*) begin
        rx_parity[0] = PARITY_EO;
        for (i = 0; i < D_WIDTH; i = i + 1) begin
            rx_parity[i+1] = rx_parity[i] ^ rx_buffer[i+1];
        end
    end
    
    // Parity error detection
    always @(*) begin
        if (PARITY == 1)
            parity_error = rx_parity[D_WIDTH] ^ rx_buffer[PARITY+D_WIDTH];
        else
            parity_error = 1'b0;
    end
    
    // Transmit state machine
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tx_count <= 0;
            tx <= 1'b1;
            tx_busy <= 1'b1;
            tx_state <= TX_IDLE;
            tx_buffer <= {(PARITY+D_WIDTH+2){1'b1}};
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    if (tx_ena) begin
                        tx_buffer[D_WIDTH+1:0] <= {tx_data, 1'b0, 1'b1}; // data, start bit, stop bit
                        if (PARITY == 1) begin
                            tx_buffer[PARITY+D_WIDTH+1] <= tx_parity[D_WIDTH];
                        end
                        tx_busy <= 1'b1;
                        tx_count <= 0;
                        tx_state <= TX_TRANSMIT;
                        // synthesis translate_off
                        $display("[UART] TX starting: data=0x%02x, tx_busy=1", tx_data);
                        // synthesis translate_on
                    end else begin
                        tx_busy <= 1'b0;
                        tx_state <= TX_IDLE;
                    end
                end
                
                TX_TRANSMIT: begin
                    if (baud_pulse) begin
                        tx_count <= tx_count + 1;
                        tx_buffer <= {1'b1, tx_buffer[PARITY+D_WIDTH+1:1]};
                    end
                    if (tx_count < PARITY+D_WIDTH+3) begin
                        tx_state <= TX_TRANSMIT;
                    end else begin
                        tx_state <= TX_IDLE;
                        tx_busy <= 1'b0;  // Clear busy flag when transmission completes
                        // synthesis translate_off
                        $display("[UART] TX complete, returning to IDLE");
                        // synthesis translate_on
                    end
                end
            endcase
            tx <= tx_buffer[0];
        end
    end
    
    // Transmit parity calculation
    integer j;
    always @(*) begin
        tx_parity[0] = PARITY_EO;
        for (j = 0; j < D_WIDTH; j = j + 1) begin
            tx_parity[j+1] = tx_parity[j] ^ tx_data[j];
        end
    end

endmodule
