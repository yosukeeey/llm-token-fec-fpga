module uart_frame_pipeline #(
    parameter integer CLOCK_HZ = 100000000,
    parameter integer BAUD_RATE = 115200,
    parameter integer RX_FIFO_DEPTH = 2048,
    parameter integer TX_FIFO_DEPTH = 2048,
    parameter integer FRAME_IDLE_TIMEOUT_CYCLES = 0,
    parameter integer INJECT_ERROR_BIT = -1
) (
    input  wire [0:0]  clk,
    input  wire [0:0]  reset_async,
    input  wire [0:0]  uart_rx_pin,
    output wire [0:0]  uart_tx_pin,
    output wire [31:0] crc_error_count,
    output wire [31:0] length_error_count,
    output wire [31:0] version_error_count,
    output wire [31:0] timeout_error_count,
    output wire [31:0] handler_error_count,
    output wire [31:0] uart_framing_error_count,
    output wire [31:0] internal_overflow_count
);
    reg [0:0] reset_sync_stage_1;
    reg [0:0] reset_sync_stage_2;
    reg [31:0] uart_framing_error_count_reg;
    reg [31:0] internal_overflow_count_reg;

    wire [0:0] reset_sync;
    wire [0:0] datapath_reset;
    wire [0:0] uart_rx_valid;
    wire [0:0] uart_rx_ready;
    wire [7:0] uart_rx_data;
    wire [0:0] uart_rx_framing_error;
    wire [0:0] uart_rx_overflow_error;
    wire [0:0] rx_fifo_valid;
    wire [0:0] rx_fifo_ready;
    wire [7:0] rx_fifo_data;
    wire [0:0] rx_fifo_overflow;
    wire [0:0] rx_fifo_underflow;
    wire [0:0] pipeline_valid;
    wire [0:0] pipeline_ready;
    wire [7:0] pipeline_data;
    wire [0:0] tx_fifo_valid;
    wire [0:0] tx_fifo_ready;
    wire [7:0] tx_fifo_data;
    wire [0:0] tx_fifo_overflow;
    wire [0:0] tx_fifo_underflow;

    assign reset_sync = reset_sync_stage_2;
    // A framing error invalidates the byte boundary of every partially buffered Frame.
    assign datapath_reset = reset_sync || uart_rx_framing_error;
    assign uart_framing_error_count = uart_framing_error_count_reg;
    assign internal_overflow_count = internal_overflow_count_reg;

    uart_rx #(
        .CLOCK_HZ(CLOCK_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) receiver (
        .clk(clk),
        .reset(reset_sync),
        .rx(uart_rx_pin),
        .output_valid(uart_rx_valid),
        .output_ready(uart_rx_ready),
        .output_data(uart_rx_data),
        .framing_error(uart_rx_framing_error),
        .overflow_error(uart_rx_overflow_error)
    );

    stream_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(RX_FIFO_DEPTH)
    ) rx_fifo (
        .clk(clk),
        .reset(datapath_reset),
        .input_valid(uart_rx_valid),
        .input_ready(uart_rx_ready),
        .input_data(uart_rx_data),
        .output_valid(rx_fifo_valid),
        .output_ready(rx_fifo_ready),
        .output_data(rx_fifo_data),
        .overflow_attempt(rx_fifo_overflow),
        .underflow_attempt(rx_fifo_underflow)
    );

    frame_pipeline #(
        .IDLE_TIMEOUT_CYCLES(FRAME_IDLE_TIMEOUT_CYCLES),
        .INJECT_ERROR_BIT(INJECT_ERROR_BIT)
    ) pipeline (
        .clk(clk),
        .reset(datapath_reset),
        .in_valid(rx_fifo_valid),
        .in_ready(rx_fifo_ready),
        .in_data(rx_fifo_data),
        .out_valid(pipeline_valid),
        .out_ready(pipeline_ready),
        .out_data(pipeline_data),
        .crc_error_count(crc_error_count),
        .length_error_count(length_error_count),
        .version_error_count(version_error_count),
        .timeout_error_count(timeout_error_count),
        .handler_error_count(handler_error_count)
    );

    stream_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(TX_FIFO_DEPTH)
    ) tx_fifo (
        .clk(clk),
        .reset(datapath_reset),
        .input_valid(pipeline_valid),
        .input_ready(pipeline_ready),
        .input_data(pipeline_data),
        .output_valid(tx_fifo_valid),
        .output_ready(tx_fifo_ready),
        .output_data(tx_fifo_data),
        .overflow_attempt(tx_fifo_overflow),
        .underflow_attempt(tx_fifo_underflow)
    );

    uart_tx #(
        .CLOCK_HZ(CLOCK_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) transmitter (
        .clk(clk),
        .reset(datapath_reset),
        .input_valid(tx_fifo_valid),
        .input_ready(tx_fifo_ready),
        .input_data(tx_fifo_data),
        .tx(uart_tx_pin)
    );

    initial begin
        // One complete maximum-size Frame must fit so UART input never depends
        // on downstream metadata acceptance while the Frame CRC is pending.
        if (RX_FIFO_DEPTH < 1036) begin
            $fatal(1, "uart_frame_pipeline RX_FIFO_DEPTH must be at least 1036");
        end
        if (TX_FIFO_DEPTH < 1036) begin
            $fatal(1, "uart_frame_pipeline TX_FIFO_DEPTH must be at least 1036");
        end
    end

    // Assertion is asynchronous for external safety; two stages prevent reset
    // release from entering the synchronous datapath near an active clock edge.
    always @(posedge clk or posedge reset_async) begin
        if (reset_async) begin
            reset_sync_stage_1 <= 1'b1;
            reset_sync_stage_2 <= 1'b1;
        end
        else begin
            reset_sync_stage_1 <= 1'b0;
            reset_sync_stage_2 <= reset_sync_stage_1;
        end
    end

    always @(posedge clk or posedge reset_async) begin
        if (reset_async) begin
            uart_framing_error_count_reg <= 32'h00000000;
            internal_overflow_count_reg <= 32'h00000000;
        end
        else if (!reset_sync) begin
            if (uart_rx_framing_error) begin
                uart_framing_error_count_reg <= uart_framing_error_count_reg + 1'b1;
            end
            if (uart_rx_overflow_error || rx_fifo_overflow || tx_fifo_overflow) begin
                internal_overflow_count_reg <= internal_overflow_count_reg + 1'b1;
            end
        end
    end
endmodule
