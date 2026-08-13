// Only empty PING is handled until the token handler owns other frame types.
module frame_pipeline #(
    parameter integer MAX_PAYLOAD_BYTES = protocol_pkg::FRAME_MAX_PAYLOAD_BYTES,
    parameter integer IDLE_TIMEOUT_CYCLES = 0
) (
    input  wire [0:0]  clk,
    input  wire [0:0]  reset,
    input  wire [0:0]  in_valid,
    output wire [0:0]  in_ready,
    input  wire [7:0]  in_data,
    output wire [0:0]  out_valid,
    input  wire [0:0]  out_ready,
    output wire [7:0]  out_data,
    output wire [31:0] crc_error_count,
    output wire [31:0] length_error_count,
    output wire [31:0] version_error_count,
    output wire [31:0] timeout_error_count,
    output wire [31:0] handler_error_count
);
    wire [0:0]  received_frame_valid;
    wire [0:0]  received_frame_ready;
    wire [7:0]  received_message_type;
    wire [15:0] received_flags;
    wire [15:0] received_payload_length;
    wire [0:0]  received_payload_valid;
    wire [0:0]  received_payload_ready;
    wire [7:0]  received_payload_data;
    wire [0:0]  received_payload_last;

    wire [0:0]  transmit_frame_valid;
    wire [0:0]  transmit_frame_ready;
    wire [0:0]  transmit_payload_ready;
    wire [31:0] transmit_length_error_count;
    wire [0:0]  supported_ping;
    wire [0:0]  received_frame_accepted;
    reg [31:0]  handler_error_count_reg;

    frame_rx #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES),
        .IDLE_TIMEOUT_CYCLES(IDLE_TIMEOUT_CYCLES)
    ) receiver (
        .clk(clk),
        .reset(reset),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_data(in_data),
        .frame_valid(received_frame_valid),
        .frame_ready(received_frame_ready),
        .message_type(received_message_type),
        .flags(received_flags),
        .payload_length(received_payload_length),
        .payload_valid(received_payload_valid),
        .payload_ready(received_payload_ready),
        .payload_data(received_payload_data),
        .payload_last(received_payload_last),
        .crc_error_count(crc_error_count),
        .length_error_count(length_error_count),
        .version_error_count(version_error_count),
        .timeout_error_count(timeout_error_count)
    );

    frame_tx #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
    ) transmitter (
        .clk(clk),
        .reset(reset),
        .frame_valid(transmit_frame_valid),
        .frame_ready(transmit_frame_ready),
        .message_type(protocol_pkg::MESSAGE_TYPE_PONG[7:0]),
        .flags(16'h0000),
        .payload_length(16'h0000),
        .payload_valid(1'b0),
        .payload_ready(transmit_payload_ready),
        .payload_data(8'h00),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_data(out_data),
        .length_error_count(transmit_length_error_count)
    );

    assign supported_ping =
        (received_message_type == protocol_pkg::MESSAGE_TYPE_PING) &&
        (received_flags == 0) &&
        (received_payload_length == 0);
    assign transmit_frame_valid = received_frame_valid && supported_ping;
    assign received_frame_ready = supported_ping ? transmit_frame_ready : 1'b1;

    // Unsupported payload must drain so the buffered receiver can accept another frame.
    assign received_payload_ready = !reset;
    assign received_frame_accepted = received_frame_valid && received_frame_ready;
    assign handler_error_count = handler_error_count_reg;

    always @(posedge clk) begin
        if (reset) begin
            handler_error_count_reg <= 32'h00000000;
        end
        else if (received_frame_accepted && !supported_ping) begin
            handler_error_count_reg <= handler_error_count_reg + 1'b1;
        end
    end
endmodule
