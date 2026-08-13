// Frame V0 is fully buffered so no payload is exposed before CRC validation.
module frame_rx #(
    parameter integer MAX_PAYLOAD_BYTES = protocol_pkg::FRAME_MAX_PAYLOAD_BYTES,
    parameter integer IDLE_TIMEOUT_CYCLES = 0
) (
    input  wire [0:0]  clk,
    input  wire [0:0]  reset,
    input  wire [0:0]  in_valid,
    output wire [0:0]  in_ready,
    input  wire [7:0]  in_data,
    output wire [0:0]  frame_valid,
    input  wire [0:0]  frame_ready,
    output wire [7:0]  message_type,
    output wire [15:0] flags,
    output wire [15:0] payload_length,
    output wire [0:0]  payload_valid,
    input  wire [0:0]  payload_ready,
    output wire [7:0]  payload_data,
    output wire [0:0]  payload_last,
    output wire [31:0] crc_error_count,
    output wire [31:0] length_error_count,
    output wire [31:0] version_error_count,
    output wire [31:0] timeout_error_count
);
    localparam [3:0] STATE_SEARCH_0 = 4'h0;
    localparam [3:0] STATE_SEARCH_1 = 4'h1;
    localparam [3:0] STATE_VERSION = 4'h2;
    localparam [3:0] STATE_MESSAGE_TYPE = 4'h3;
    localparam [3:0] STATE_FLAGS_LOW = 4'h4;
    localparam [3:0] STATE_FLAGS_HIGH = 4'h5;
    localparam [3:0] STATE_LENGTH_LOW = 4'h6;
    localparam [3:0] STATE_LENGTH_HIGH = 4'h7;
    localparam [3:0] STATE_PAYLOAD = 4'h8;
    localparam [3:0] STATE_CRC_0 = 4'h9;
    localparam [3:0] STATE_CRC_1 = 4'ha;
    localparam [3:0] STATE_CRC_2 = 4'hb;
    localparam [3:0] STATE_CRC_3 = 4'hc;
    localparam [3:0] STATE_VALIDATE = 4'hd;
    localparam [3:0] STATE_OUTPUT_FRAME = 4'he;
    localparam [3:0] STATE_OUTPUT_PAYLOAD = 4'hf;
    localparam [15:0] MAX_PAYLOAD_LENGTH = MAX_PAYLOAD_BYTES;

    reg [3:0] state;
    reg [7:0] message_type_reg;
    reg [15:0] flags_reg;
    reg [15:0] payload_length_reg;
    reg [31:0] expected_crc_reg;
    reg [15:0] payload_write_index;
    reg [15:0] payload_read_index;
    reg [31:0] idle_count;
    reg [31:0] crc_error_count_reg;
    reg [31:0] length_error_count_reg;
    reg [31:0] version_error_count_reg;
    reg [31:0] timeout_error_count_reg;
    reg [7:0] payload_memory [0:MAX_PAYLOAD_BYTES-1];

    wire [0:0] crc_input_valid;
    wire [0:0] crc_input_ready;
    wire [0:0] crc_input_start;
    wire [0:0] crc_input_last;
    wire [0:0] crc_output_valid;
    wire [0:0] crc_output_ready;
    wire [31:0] crc_output;
    wire [0:0] input_accepted;
    wire [0:0] crc_input_state;
    wire [0:0] receiving_frame;
    wire [15:0] incoming_payload_length;

    crc32c_stream crc (
        .clk(clk),
        .reset(reset),
        .input_valid(crc_input_valid),
        .input_ready(crc_input_ready),
        .input_data(in_data),
        .input_start(crc_input_start),
        .input_last(crc_input_last),
        .input_empty(1'b0),
        .output_valid(crc_output_valid),
        .output_ready(crc_output_ready),
        .output_crc(crc_output)
    );

    assign incoming_payload_length = {in_data, payload_length_reg[7:0]};
    assign crc_input_state =
        ((state >= STATE_VERSION) && (state <= STATE_LENGTH_HIGH)) ||
        (state == STATE_PAYLOAD);
    assign receiving_frame =
        (state >= STATE_VERSION) && (state <= STATE_CRC_3);
    assign crc_input_valid = in_valid && crc_input_state;
    assign crc_input_start = state == STATE_VERSION;
    assign crc_input_last =
        ((state == STATE_LENGTH_HIGH) && (incoming_payload_length == 0)) ||
        ((state == STATE_PAYLOAD) &&
         (payload_write_index == payload_length_reg - 1'b1));
    assign crc_output_ready = state == STATE_VALIDATE;

    assign in_ready = !reset && (
        crc_input_state ? crc_input_ready :
        ((state <= STATE_SEARCH_1) ||
         ((state >= STATE_CRC_0) && (state <= STATE_CRC_3)))
    );
    assign input_accepted = in_valid && in_ready;

    assign frame_valid = !reset && (state == STATE_OUTPUT_FRAME);
    assign message_type = message_type_reg;
    assign flags = flags_reg;
    assign payload_length = payload_length_reg;
    assign payload_valid = !reset && (state == STATE_OUTPUT_PAYLOAD);
    assign payload_data = payload_valid ? payload_memory[payload_read_index] : 8'h00;
    assign payload_last =
        (state == STATE_OUTPUT_PAYLOAD) &&
        (payload_read_index == payload_length_reg - 1'b1);

    assign crc_error_count = crc_error_count_reg;
    assign length_error_count = length_error_count_reg;
    assign version_error_count = version_error_count_reg;
    assign timeout_error_count = timeout_error_count_reg;

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_SEARCH_0;
            message_type_reg <= 8'h00;
            flags_reg <= 16'h0000;
            payload_length_reg <= 16'h0000;
            expected_crc_reg <= 32'h00000000;
            payload_write_index <= 16'h0000;
            payload_read_index <= 16'h0000;
            idle_count <= 32'h00000000;
            crc_error_count_reg <= 32'h00000000;
            length_error_count_reg <= 32'h00000000;
            version_error_count_reg <= 32'h00000000;
            timeout_error_count_reg <= 32'h00000000;
        end
        else begin
            if (receiving_frame) begin
                if (input_accepted) begin
                    idle_count <= 32'h00000000;
                end
                else if (IDLE_TIMEOUT_CYCLES != 0) begin
                    if (idle_count >= IDLE_TIMEOUT_CYCLES - 1) begin
                        state <= STATE_SEARCH_0;
                        idle_count <= 32'h00000000;
                        timeout_error_count_reg <= timeout_error_count_reg + 1'b1;
                    end
                    else begin
                        idle_count <= idle_count + 1'b1;
                    end
                end
            end
            else begin
                idle_count <= 32'h00000000;
            end

            case (state)
                STATE_SEARCH_0: begin
                    if (input_accepted && (in_data == protocol_pkg::FRAME_SOF_0)) begin
                        state <= STATE_SEARCH_1;
                    end
                end
                STATE_SEARCH_1: begin
                    if (input_accepted) begin
                        if (in_data == protocol_pkg::FRAME_SOF_1) begin
                            state <= STATE_VERSION;
                        end
                        else if (in_data != protocol_pkg::FRAME_SOF_0) begin
                            state <= STATE_SEARCH_0;
                        end
                    end
                end
                STATE_VERSION: begin
                    if (input_accepted) begin
                        if (in_data == protocol_pkg::FRAME_VERSION) begin
                            state <= STATE_MESSAGE_TYPE;
                        end
                        else begin
                            state <= STATE_SEARCH_0;
                            version_error_count_reg <= version_error_count_reg + 1'b1;
                        end
                    end
                end
                STATE_MESSAGE_TYPE: begin
                    if (input_accepted) begin
                        message_type_reg <= in_data;
                        state <= STATE_FLAGS_LOW;
                    end
                end
                STATE_FLAGS_LOW: begin
                    if (input_accepted) begin
                        flags_reg[7:0] <= in_data;
                        state <= STATE_FLAGS_HIGH;
                    end
                end
                STATE_FLAGS_HIGH: begin
                    if (input_accepted) begin
                        flags_reg[15:8] <= in_data;
                        state <= STATE_LENGTH_LOW;
                    end
                end
                STATE_LENGTH_LOW: begin
                    if (input_accepted) begin
                        payload_length_reg[7:0] <= in_data;
                        state <= STATE_LENGTH_HIGH;
                    end
                end
                STATE_LENGTH_HIGH: begin
                    if (input_accepted) begin
                        payload_length_reg <= incoming_payload_length;
                        payload_write_index <= 16'h0000;
                        if (incoming_payload_length > MAX_PAYLOAD_LENGTH) begin
                            state <= STATE_SEARCH_0;
                            length_error_count_reg <= length_error_count_reg + 1'b1;
                        end
                        else if (incoming_payload_length == 0) begin
                            state <= STATE_CRC_0;
                        end
                        else begin
                            state <= STATE_PAYLOAD;
                        end
                    end
                end
                STATE_PAYLOAD: begin
                    if (input_accepted) begin
                        payload_memory[payload_write_index] <= in_data;
                        if (payload_write_index == payload_length_reg - 1'b1) begin
                            state <= STATE_CRC_0;
                        end
                        else begin
                            payload_write_index <= payload_write_index + 1'b1;
                        end
                    end
                end
                STATE_CRC_0: begin
                    if (input_accepted) begin
                        expected_crc_reg[7:0] <= in_data;
                        state <= STATE_CRC_1;
                    end
                end
                STATE_CRC_1: begin
                    if (input_accepted) begin
                        expected_crc_reg[15:8] <= in_data;
                        state <= STATE_CRC_2;
                    end
                end
                STATE_CRC_2: begin
                    if (input_accepted) begin
                        expected_crc_reg[23:16] <= in_data;
                        state <= STATE_CRC_3;
                    end
                end
                STATE_CRC_3: begin
                    if (input_accepted) begin
                        expected_crc_reg[31:24] <= in_data;
                        state <= STATE_VALIDATE;
                    end
                end
                STATE_VALIDATE: begin
                    if (crc_output_valid) begin
                        if (crc_output == expected_crc_reg) begin
                            payload_read_index <= 16'h0000;
                            state <= STATE_OUTPUT_FRAME;
                        end
                        else begin
                            state <= STATE_SEARCH_0;
                            crc_error_count_reg <= crc_error_count_reg + 1'b1;
                        end
                    end
                end
                STATE_OUTPUT_FRAME: begin
                    if (frame_ready) begin
                        if (payload_length_reg == 0) begin
                            state <= STATE_SEARCH_0;
                        end
                        else begin
                            state <= STATE_OUTPUT_PAYLOAD;
                        end
                    end
                end
                STATE_OUTPUT_PAYLOAD: begin
                    if (payload_ready) begin
                        if (payload_read_index == payload_length_reg - 1'b1) begin
                            state <= STATE_SEARCH_0;
                        end
                        else begin
                            payload_read_index <= payload_read_index + 1'b1;
                        end
                    end
                end
                default: begin
                    state <= STATE_SEARCH_0;
                end
            endcase
        end
    end
endmodule
