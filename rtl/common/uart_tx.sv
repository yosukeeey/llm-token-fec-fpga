module uart_tx #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer BAUD_RATE = 115_200
) (
    input  wire [0:0] clk,
    input  wire [0:0] reset,
    input  wire [0:0] input_valid,
    output wire [0:0] input_ready,
    input  wire [7:0] input_data,
    output wire [0:0] tx
);
    localparam integer CLKS_PER_BIT = BAUD_RATE > 0
        ? (CLOCK_HZ + (BAUD_RATE / 2)) / BAUD_RATE
        : 0;
    localparam integer COUNTER_WIDTH = CLKS_PER_BIT >= 2 ? $clog2(CLKS_PER_BIT) : 1;

    reg [COUNTER_WIDTH-1:0] clock_count;
    reg [3:0] bit_index;
    reg [9:0] shift_register;
    reg busy;

    // UART 8-N-1 sends one start, eight LSB-first data, and one stop bit.
    assign input_ready = !reset && (
        !busy || ((bit_index == 9) && (clock_count == CLKS_PER_BIT - 1))
    );
    assign tx = reset ? 1'b1 : (busy ? shift_register[bit_index] : 1'b1);

    initial begin
        if (BAUD_RATE == 0) begin
            $fatal(1, "uart_tx BAUD_RATE must be nonzero");
        end
        if (CLOCK_HZ < BAUD_RATE) begin
            $fatal(1, "uart_tx CLOCK_HZ must not be below BAUD_RATE");
        end
        if (CLKS_PER_BIT < 2) begin
            $fatal(1, "uart_tx divisor must be at least 2");
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            clock_count <= {COUNTER_WIDTH{1'b0}};
            bit_index <= 4'd0;
            shift_register <= 10'h3ff;
            busy <= 1'b0;
        end
        else if (!busy) begin
            if (input_valid && input_ready) begin
                // The stop slot remains stable while input_ready backpressures the source.
                shift_register <= {1'b1, input_data, 1'b0};
                clock_count <= {COUNTER_WIDTH{1'b0}};
                bit_index <= 4'd0;
                busy <= 1'b1;
            end
        end
        else if (clock_count == CLKS_PER_BIT - 1) begin
            clock_count <= {COUNTER_WIDTH{1'b0}};
            if (bit_index == 9) begin
                if (input_valid) begin
                    // Accepting here places the next start immediately after this stop bit.
                    shift_register <= {1'b1, input_data, 1'b0};
                    bit_index <= 4'd0;
                end
                else begin
                    busy <= 1'b0;
                end
            end
            else begin
                bit_index <= bit_index + 1'b1;
            end
        end
        else begin
            clock_count <= clock_count + 1'b1;
        end
    end
endmodule
