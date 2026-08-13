/**
 * @note UART 8-N-1 is sampled at rounded integer clock intervals, LSB first.
 * @note The two-flop synchronizer adds latency but isolates asynchronous RX.
 */
module uart_rx #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer BAUD_RATE = 115_200
) (
    input  wire [0:0] clk,
    input  wire [0:0] reset,
    input  wire [0:0] rx,
    output wire [0:0] output_valid,
    input  wire [0:0] output_ready,
    output wire [7:0] output_data,
    output wire [0:0] framing_error,
    output wire [0:0] overflow_error
);
    localparam integer CLOCKS_PER_BIT = (CLOCK_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam integer HALF_CLOCKS_PER_BIT = CLOCKS_PER_BIT / 2;
    localparam [1:0] STATE_IDLE = 2'h0;
    localparam [1:0] STATE_START = 2'h1;
    localparam [1:0] STATE_DATA = 2'h2;
    localparam [1:0] STATE_STOP = 2'h3;

    reg [0:0] rx_meta;
    reg [0:0] rx_sync;
    reg [1:0] state;
    integer clock_count;
    integer bit_index;
    reg [7:0] shift_reg;
    reg [7:0] output_data_reg;
    reg [0:0] output_valid_reg;
    reg [0:0] framing_error_reg;
    reg [0:0] overflow_error_reg;

    initial begin
        if ((CLOCK_HZ <= 0) || (BAUD_RATE <= 0) || (CLOCKS_PER_BIT < 2)) begin
            $fatal(1, "UART clock and baud parameters are invalid");
        end
    end

    assign output_valid = output_valid_reg;
    assign output_data = output_data_reg;
    assign framing_error = framing_error_reg;
    assign overflow_error = overflow_error_reg;

    always @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;

        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            state <= STATE_IDLE;
            clock_count <= 0;
            bit_index <= 0;
            shift_reg <= 8'h00;
            output_data_reg <= 8'h00;
            output_valid_reg <= 1'b0;
            framing_error_reg <= 1'b0;
            overflow_error_reg <= 1'b0;
        end
        else begin
            framing_error_reg <= 1'b0;
            overflow_error_reg <= 1'b0;
            if (output_valid_reg && output_ready) begin
                output_valid_reg <= 1'b0;
            end

            case (state)
                STATE_IDLE: begin
                    clock_count <= 0;
                    if (rx_sync == 1'b0) begin
                        state <= STATE_START;
                    end
                end
                STATE_START: begin
                    if (clock_count == HALF_CLOCKS_PER_BIT - 1) begin
                        clock_count <= 0;
                        if (rx_sync == 1'b0) begin
                            state <= STATE_DATA;
                            bit_index <= 0;
                        end
                        else begin
                            state <= STATE_IDLE;
                        end
                    end
                    else begin
                        clock_count <= clock_count + 1;
                    end
                end
                STATE_DATA: begin
                    if (clock_count == CLOCKS_PER_BIT - 1) begin
                        clock_count <= 0;
                        shift_reg[bit_index] <= rx_sync;
                        if (bit_index == 7) begin
                            state <= STATE_STOP;
                        end
                        else begin
                            bit_index <= bit_index + 1;
                        end
                    end
                    else begin
                        clock_count <= clock_count + 1;
                    end
                end
                STATE_STOP: begin
                    if (clock_count == CLOCKS_PER_BIT - 1) begin
                        clock_count <= 0;
                        state <= STATE_IDLE;
                        if (rx_sync == 1'b0) begin
                            framing_error_reg <= 1'b1;
                        end
                        else if (output_valid_reg && !output_ready) begin
                            overflow_error_reg <= 1'b1;
                        end
                        else begin
                            output_data_reg <= shift_reg;
                            output_valid_reg <= 1'b1;
                        end
                    end
                    else begin
                        clock_count <= clock_count + 1;
                    end
                end
                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule
