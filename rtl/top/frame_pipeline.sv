module frame_pipeline #(
    parameter integer MAX_PAYLOAD_BYTES = protocol_pkg::FRAME_MAX_PAYLOAD_BYTES,
    parameter integer IDLE_TIMEOUT_CYCLES = 0,
    parameter integer INJECT_ERROR_BIT = -1
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
    localparam [1:0] ROUTE_IDLE = 2'd0;
    localparam [1:0] ROUTE_TOKEN = 2'd1;
    localparam [1:0] ROUTE_DROP = 2'd2;

    wire [0:0]  received_frame_valid;
    wire [0:0]  received_frame_ready;
    wire [7:0]  received_message_type;
    wire [15:0] received_flags;
    wire [15:0] received_payload_length;
    wire [0:0]  received_payload_valid;
    wire [0:0]  received_payload_ready;
    wire [7:0]  received_payload_data;
    wire [0:0]  received_payload_last;

    wire [0:0]  handler_request_valid;
    wire [0:0]  handler_request_ready;
    wire [0:0]  handler_payload_ready;
    wire [0:0]  handler_response_valid;
    wire [0:0]  handler_response_ready;
    wire [7:0]  handler_response_message_type;
    wire [15:0] handler_response_flags;
    wire [15:0] handler_response_length;
    wire [0:0]  handler_response_payload_valid;
    wire [0:0]  handler_response_payload_ready;
    wire [7:0]  handler_response_payload_data;
    wire [0:0]  handler_response_payload_last;

    wire [0:0]  transmit_frame_valid;
    wire [0:0]  transmit_frame_ready;
    wire [0:0]  transmit_payload_ready;
    wire [31:0] transmit_length_error_count;
    wire [0:0]  supported_ping;
    wire [0:0]  token_request;
    wire [0:0]  ping_response_valid;
    wire [0:0]  ping_response_ready;
    wire [0:0]  received_frame_accepted;
    wire [0:0]  received_payload_accepted;
    wire [0:0]  handler_error_response_accepted;
    wire [0:0]  unsupported_drop_accepted;
    wire [7:0]  transmit_message_type;
    wire [15:0] transmit_flags;
    wire [15:0] transmit_payload_length;
    reg [1:0]   payload_route;
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

    token_request_handler #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES),
        .INJECT_ERROR_BIT(INJECT_ERROR_BIT)
    ) token_handler (
        .clk(clk),
        .reset(reset),
        .request_valid(handler_request_valid),
        .request_ready(handler_request_ready),
        .request_flags(received_flags),
        .request_length(received_payload_length),
        .request_payload_valid(received_payload_valid && (payload_route == ROUTE_TOKEN)),
        .request_payload_ready(handler_payload_ready),
        .request_payload_data(received_payload_data),
        .request_payload_last(received_payload_last),
        .response_valid(handler_response_valid),
        .response_ready(handler_response_ready),
        .response_message_type(handler_response_message_type),
        .response_flags(handler_response_flags),
        .response_length(handler_response_length),
        .response_payload_valid(handler_response_payload_valid),
        .response_payload_ready(handler_response_payload_ready),
        .response_payload_data(handler_response_payload_data),
        .response_payload_last(handler_response_payload_last)
    );

    frame_tx #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
    ) transmitter (
        .clk(clk),
        .reset(reset),
        .frame_valid(transmit_frame_valid),
        .frame_ready(transmit_frame_ready),
        .message_type(transmit_message_type),
        .flags(transmit_flags),
        .payload_length(transmit_payload_length),
        .payload_valid(handler_response_payload_valid),
        .payload_ready(transmit_payload_ready),
        .payload_data(handler_response_payload_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_data(out_data),
        .length_error_count(transmit_length_error_count)
    );

    assign supported_ping =
        (received_message_type == protocol_pkg::MESSAGE_TYPE_PING) &&
        (received_flags == 0) &&
        (received_payload_length == 0);
    assign token_request =
        received_message_type == protocol_pkg::MESSAGE_TYPE_TOKEN_REQUEST;
    assign handler_request_valid = received_frame_valid && token_request;
    assign ping_response_valid = received_frame_valid && supported_ping;

    // Handler responses take priority so its buffered payload cannot block new requests.
    assign transmit_frame_valid = handler_response_valid || ping_response_valid;
    assign transmit_message_type = handler_response_valid
        ? handler_response_message_type
        : protocol_pkg::MESSAGE_TYPE_PONG[7:0];
    assign transmit_flags = handler_response_valid ? handler_response_flags : 16'h0000;
    assign transmit_payload_length = handler_response_valid
        ? handler_response_length
        : 16'h0000;
    assign handler_response_ready = transmit_frame_ready && handler_response_valid;
    assign ping_response_ready = transmit_frame_ready && !handler_response_valid;
    assign handler_response_payload_ready = transmit_payload_ready;

    assign received_frame_ready = token_request
        ? handler_request_ready
        : (supported_ping ? ping_response_ready : 1'b1);
    assign received_frame_accepted = received_frame_valid && received_frame_ready;

    // The route is fixed from metadata acceptance through the final payload byte.
    assign received_payload_ready = (payload_route == ROUTE_TOKEN)
        ? handler_payload_ready
        : ((payload_route == ROUTE_DROP) && !reset);
    assign received_payload_accepted = received_payload_valid && received_payload_ready;
    assign handler_error_response_accepted =
        handler_response_valid && handler_response_ready &&
        (handler_response_message_type == protocol_pkg::MESSAGE_TYPE_ERROR_RESPONSE);
    assign unsupported_drop_accepted =
        received_frame_accepted && !supported_ping && !token_request;
    assign handler_error_count = handler_error_count_reg;

    always @(posedge clk) begin
        if (reset) begin
            payload_route <= ROUTE_IDLE;
            handler_error_count_reg <= 32'h00000000;
        end
        else begin
            if (received_frame_accepted && (received_payload_length != 0)) begin
                if (token_request) begin
                    payload_route <= ROUTE_TOKEN;
                end
                else if (!supported_ping) begin
                    payload_route <= ROUTE_DROP;
                end
            end
            else if (received_payload_accepted && received_payload_last) begin
                payload_route <= ROUTE_IDLE;
            end

            case ({handler_error_response_accepted, unsupported_drop_accepted})
                2'b01, 2'b10:
                    handler_error_count_reg <= handler_error_count_reg + 1'b1;
                2'b11:
                    handler_error_count_reg <= handler_error_count_reg + 2'd2;
                default:
                    handler_error_count_reg <= handler_error_count_reg;
            endcase
        end
    end
endmodule
