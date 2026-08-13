/**
 * @note Frame V0 is serialized one byte per accepted output cycle; the CRC
 *       pipeline adds two cycles between the final protected byte and CRC.
 * @note Multi-byte fields and CRC-32C are emitted little-endian.
 */
module frame_tx #(
    parameter integer MAX_PAYLOAD_BYTES = protocol_pkg::FRAME_MAX_PAYLOAD_BYTES
) (
    input  wire [0:0]  clk,
    input  wire [0:0]  reset,
    input  wire [0:0]  frame_valid,
    output wire [0:0]  frame_ready,
    input  wire [7:0]  message_type,
    input  wire [15:0] flags,
    input  wire [15:0] payload_length,
    input  wire [0:0]  payload_valid,
    output wire [0:0]  payload_ready,
    input  wire [7:0]  payload_data,
    output wire [0:0]  out_valid,
    input  wire [0:0]  out_ready,
    output wire [7:0]  out_data,
    output wire [31:0] length_error_count
);
    localparam [3:0] STATE_IDLE = 4'd0;
    localparam [3:0] STATE_SOF_0 = 4'd1;
    localparam [3:0] STATE_SOF_1 = 4'd2;
    localparam [3:0] STATE_HEADER = 4'd3;
    localparam [3:0] STATE_PAYLOAD = 4'd4;
    localparam [3:0] STATE_WAIT_CRC = 4'd5;
    localparam [3:0] STATE_CRC = 4'd6;

    reg [3:0] state;
    reg [2:0] header_index;
    reg [1:0] crc_index;
    reg [7:0] message_type_reg;
    reg [15:0] flags_reg;
    reg [15:0] payload_length_reg;
    reg [15:0] payload_remaining;
    reg [31:0] length_error_count_reg;

    reg        out_valid_reg;
    reg [7:0]  out_data_reg;
    reg        payload_ready_reg;

    reg        crc_feed_valid;
    reg [7:0]  crc_feed_data;
    reg        crc_feed_start;
    reg        crc_feed_last;
    wire [0:0] crc_feed_ready;
    wire [0:0] crc_result_valid;
    wire [0:0] crc_result_ready;
    wire [31:0] crc_result;

    wire frame_accepted;
    wire output_accepted;
    wire output_is_protected;

    crc32c_stream crc (
        .clk(clk),
        .reset(reset),
        .input_valid(crc_feed_valid),
        .input_ready(crc_feed_ready),
        .input_data(crc_feed_data),
        .input_start(crc_feed_start),
        .input_last(crc_feed_last),
        .input_empty(1'b0),
        .output_valid(crc_result_valid),
        .output_ready(crc_result_ready),
        .output_crc(crc_result)
    );

    assign frame_ready = !reset && (state == STATE_IDLE);
    assign frame_accepted = frame_valid && frame_ready;
    assign payload_ready = payload_ready_reg;
    assign out_valid = !reset && out_valid_reg;
    assign out_data = out_valid ? out_data_reg : 8'h00;
    assign output_accepted = out_valid && out_ready;
    assign output_is_protected = (state == STATE_HEADER) || (state == STATE_PAYLOAD);
    assign crc_result_ready = !reset && (state == STATE_WAIT_CRC);
    assign length_error_count = length_error_count_reg;

    initial begin
        // The length field cannot represent a larger configured bound.
        if ((MAX_PAYLOAD_BYTES < 0) || (MAX_PAYLOAD_BYTES > 65535)) begin
            $fatal(1, "frame_tx MAX_PAYLOAD_BYTES must fit in 16 bits");
        end
    end

    always @* begin
        out_valid_reg = 1'b0;
        out_data_reg = 8'h00;
        payload_ready_reg = 1'b0;

        case (state)
            STATE_SOF_0: begin
                out_valid_reg = 1'b1;
                out_data_reg = protocol_pkg::FRAME_SOF_0;
            end
            STATE_SOF_1: begin
                out_valid_reg = 1'b1;
                out_data_reg = protocol_pkg::FRAME_SOF_1;
            end
            STATE_HEADER: begin
                out_valid_reg = 1'b1;
                case (header_index)
                    3'd0: out_data_reg = protocol_pkg::FRAME_VERSION[7:0];
                    3'd1: out_data_reg = message_type_reg;
                    3'd2: out_data_reg = flags_reg[7:0];
                    3'd3: out_data_reg = flags_reg[15:8];
                    3'd4: out_data_reg = payload_length_reg[7:0];
                    default: out_data_reg = payload_length_reg[15:8];
                endcase
            end
            STATE_PAYLOAD: begin
                out_valid_reg = payload_valid;
                out_data_reg = payload_data;
                payload_ready_reg = !reset && out_ready;
            end
            STATE_CRC: begin
                out_valid_reg = 1'b1;
                case (crc_index)
                    2'd0: out_data_reg = crc_result[7:0];
                    2'd1: out_data_reg = crc_result[15:8];
                    2'd2: out_data_reg = crc_result[23:16];
                    default: out_data_reg = crc_result[31:24];
                endcase
            end
            default: begin
                out_valid_reg = 1'b0;
                out_data_reg = 8'h00;
            end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            header_index <= 3'd0;
            crc_index <= 2'd0;
            message_type_reg <= 8'h00;
            flags_reg <= 16'h0000;
            payload_length_reg <= 16'h0000;
            payload_remaining <= 16'h0000;
            length_error_count_reg <= 32'h00000000;
            crc_feed_valid <= 1'b0;
            crc_feed_data <= 8'h00;
            crc_feed_start <= 1'b0;
            crc_feed_last <= 1'b0;
        end
        else begin
            // CRC input stays ready until the final protected byte creates a result.
            crc_feed_valid <= 1'b0;
            if (output_accepted && output_is_protected) begin
                crc_feed_valid <= 1'b1;
                crc_feed_data <= out_data_reg;
                crc_feed_start <= (state == STATE_HEADER) && (header_index == 0);
                crc_feed_last <= (
                    ((state == STATE_HEADER) &&
                     (header_index == 5) &&
                     (payload_length_reg == 0)) ||
                    ((state == STATE_PAYLOAD) && (payload_remaining == 1))
                );
            end

            case (state)
                STATE_IDLE: begin
                    if (frame_accepted) begin
                        if (payload_length > MAX_PAYLOAD_BYTES) begin
                            length_error_count_reg <= length_error_count_reg + 1'b1;
                        end
                        else begin
                            message_type_reg <= message_type;
                            flags_reg <= flags;
                            payload_length_reg <= payload_length;
                            payload_remaining <= payload_length;
                            state <= STATE_SOF_0;
                        end
                    end
                end
                STATE_SOF_0: begin
                    if (output_accepted) begin
                        state <= STATE_SOF_1;
                    end
                end
                STATE_SOF_1: begin
                    if (output_accepted) begin
                        header_index <= 3'd0;
                        state <= STATE_HEADER;
                    end
                end
                STATE_HEADER: begin
                    if (output_accepted) begin
                        if (header_index == 5) begin
                            if (payload_length_reg == 0) begin
                                state <= STATE_WAIT_CRC;
                            end
                            else begin
                                state <= STATE_PAYLOAD;
                            end
                        end
                        else begin
                            header_index <= header_index + 1'b1;
                        end
                    end
                end
                STATE_PAYLOAD: begin
                    if (output_accepted) begin
                        if (payload_remaining == 1) begin
                            payload_remaining <= 16'h0000;
                            state <= STATE_WAIT_CRC;
                        end
                        else begin
                            payload_remaining <= payload_remaining - 1'b1;
                        end
                    end
                end
                STATE_WAIT_CRC: begin
                    if (crc_result_valid) begin
                        crc_index <= 2'd0;
                        state <= STATE_CRC;
                    end
                end
                STATE_CRC: begin
                    if (output_accepted) begin
                        if (crc_index == 3) begin
                            state <= STATE_IDLE;
                        end
                        else begin
                            crc_index <= crc_index + 1'b1;
                        end
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
