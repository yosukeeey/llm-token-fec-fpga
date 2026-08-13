module token_request_handler #(
    parameter integer MAX_PAYLOAD_BYTES = protocol_pkg::FRAME_MAX_PAYLOAD_BYTES,
    parameter integer INJECT_ERROR_BIT = -1
) (
    input  wire [0:0]  clk,
    input  wire [0:0]  reset,
    input  wire [0:0]  request_valid,
    output wire [0:0]  request_ready,
    input  wire [15:0] request_flags,
    input  wire [15:0] request_length,
    input  wire [0:0]  request_payload_valid,
    output wire [0:0]  request_payload_ready,
    input  wire [7:0]  request_payload_data,
    input  wire [0:0]  request_payload_last,
    output wire [0:0]  response_valid,
    input  wire [0:0]  response_ready,
    output wire [7:0]  response_message_type,
    output wire [15:0] response_flags,
    output wire [15:0] response_length,
    output wire [0:0]  response_payload_valid,
    input  wire [0:0]  response_payload_ready,
    output wire [7:0]  response_payload_data,
    output wire [0:0]  response_payload_last
);
    // CRC is verified by the upstream Frame receiver before this payload boundary.
    localparam [3:0] STATE_IDLE = 4'd0;
    localparam [3:0] STATE_COLLECT = 4'd1;
    localparam [3:0] STATE_VALIDATE = 4'd2;
    localparam [3:0] STATE_VALIDATE_TLV = 4'd3;
    localparam [3:0] STATE_PROCESS_NONE = 4'd4;
    localparam [3:0] STATE_PROCESS_REPETITION = 4'd5;
    localparam [3:0] STATE_PROCESS_HAMMING = 4'd6;
    localparam [3:0] STATE_FINALIZE = 4'd7;
    localparam [3:0] STATE_RESPONSE_HEADER = 4'd8;
    localparam [3:0] STATE_RESPONSE_PAYLOAD = 4'd9;

    localparam [7:0] MESSAGE_TOKEN_REQUEST = protocol_pkg::MESSAGE_TYPE_TOKEN_REQUEST;
    localparam [7:0] MESSAGE_TOKEN_RESULT = protocol_pkg::MESSAGE_TYPE_TOKEN_RESULT;
    localparam [7:0] MESSAGE_ERROR_RESPONSE = protocol_pkg::MESSAGE_TYPE_ERROR_RESPONSE;
    localparam [31:0] FLAG_FEC_CORRECTED = protocol_pkg::RESULT_FLAG_FEC_CORRECTED;
    localparam [31:0] FLAG_MALFORMED = protocol_pkg::RESULT_FLAG_MALFORMED_REQUEST;
    localparam [31:0] FLAG_UNSUPPORTED_VERSION =
        protocol_pkg::RESULT_FLAG_UNSUPPORTED_VERSION;
    localparam [31:0] FLAG_UNSUPPORTED_PROTECTION =
        protocol_pkg::RESULT_FLAG_UNSUPPORTED_PROTECTION;

    reg [3:0] state;
    reg [7:0] request_buffer [0:MAX_PAYLOAD_BYTES-1];
    reg [7:0] response_buffer [0:MAX_PAYLOAD_BYTES-1];
    reg [15:0] request_flags_reg;
    reg [15:0] request_length_reg;
    reg [15:0] response_flags_reg;
    reg [15:0] response_length_reg;
    reg [7:0] response_message_type_reg;
    reg [15:0] token_length_reg;
    reg [7:0] protection_mode_reg;
    reg [7:0] repetition_count_reg;
    reg [15:0] corrected_count_reg;
    integer payload_index;
    integer response_index;
    integer process_index;
    integer tlv_index;
    integer candidate_token_length;
    integer protection_offset;
    integer channel_offset;
    integer validation_failed;
    integer validation_index;
    integer tlv_value_length;

    wire [7:0] codec_byte;
    wire [3:0] codec_nibble;
    wire [7:0] repetition_r1_encoded;
    wire [7:0] repetition_r1_received;
    wire [7:0] repetition_r1_decoded;
    wire [7:0] repetition_r1_disagreement;
    wire [23:0] repetition_r3_encoded;
    wire [23:0] repetition_r3_received;
    wire [7:0] repetition_r3_decoded;
    wire [7:0] repetition_r3_disagreement;
    wire [6:0] hamming_encoded;
    wire [6:0] hamming_received;
    wire [3:0] hamming_decoded;
    wire [2:0] hamming_syndrome;
    wire [0:0] hamming_corrected;

    function [15:0] buffer_u16;
        input integer offset;
        begin
            buffer_u16 = {request_buffer[offset + 1], request_buffer[offset]};
        end
    endfunction

    function integer buffer_range_is_zero;
        input integer offset;
        input integer length;
        integer index;
        begin
            buffer_range_is_zero = 1;
            for (index = 0; index < length; index = index + 1) begin
                if (request_buffer[offset + index] != 8'h00) begin
                    buffer_range_is_zero = 0;
                end
            end
        end
    endfunction

    function [7:0] none_error_mask;
        input integer byte_index;
        integer relative_bit;
        begin
            none_error_mask = 8'h00;
            relative_bit = INJECT_ERROR_BIT - (byte_index * 8);
            if ((INJECT_ERROR_BIT >= 0) && (relative_bit >= 0) && (relative_bit < 8)) begin
                none_error_mask[relative_bit] = 1'b1;
            end
        end
    endfunction

    function [7:0] repetition_r1_error_mask;
        input integer byte_index;
        integer relative_bit;
        begin
            repetition_r1_error_mask = 8'h00;
            relative_bit = INJECT_ERROR_BIT - (byte_index * 8);
            if ((INJECT_ERROR_BIT >= 0) && (relative_bit >= 0) && (relative_bit < 8)) begin
                repetition_r1_error_mask[relative_bit] = 1'b1;
            end
        end
    endfunction

    function [23:0] repetition_r3_error_mask;
        input integer byte_index;
        integer relative_bit;
        begin
            repetition_r3_error_mask = 24'h000000;
            relative_bit = INJECT_ERROR_BIT - (byte_index * 24);
            if ((INJECT_ERROR_BIT >= 0) && (relative_bit >= 0) && (relative_bit < 24)) begin
                repetition_r3_error_mask[relative_bit] = 1'b1;
            end
        end
    endfunction

    function [6:0] hamming_error_mask;
        input integer nibble_index;
        integer relative_bit;
        begin
            hamming_error_mask = 7'h00;
            relative_bit = INJECT_ERROR_BIT - (nibble_index * 7);
            if ((INJECT_ERROR_BIT >= 0) && (relative_bit >= 0) && (relative_bit < 7)) begin
                hamming_error_mask[relative_bit] = 1'b1;
            end
        end
    endfunction

    function [4:0] count_set_bits;
        input [7:0] value;
        integer bit_index;
        begin
            count_set_bits = 5'd0;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                count_set_bits = count_set_bits + value[bit_index];
            end
        end
    endfunction

    task prepare_error_response;
        input [31:0] error_flags;
        begin
            response_buffer[0] <= error_flags[7:0];
            response_buffer[1] <= error_flags[15:8];
            response_buffer[2] <= error_flags[23:16];
            response_buffer[3] <= error_flags[31:24];
            response_buffer[4] <= MESSAGE_TOKEN_REQUEST;
            response_buffer[5] <= 8'h00;
            response_buffer[6] <= 8'h00;
            response_buffer[7] <= 8'h00;
            response_message_type_reg <= MESSAGE_ERROR_RESPONSE;
            response_flags_reg <= request_flags_reg;
            response_length_reg <= 16'd8;
            state <= STATE_RESPONSE_HEADER;
        end
    endtask

    task begin_fec_processing;
        begin
            process_index <= 0;
            corrected_count_reg <= 16'd0;
            if (protection_mode_reg == protocol_pkg::PROTECTION_MODE_NONE) begin
                state <= STATE_PROCESS_NONE;
            end
            else if (protection_mode_reg == protocol_pkg::PROTECTION_MODE_REPETITION) begin
                state <= STATE_PROCESS_REPETITION;
            end
            else begin
                state <= STATE_PROCESS_HAMMING;
            end
        end
    endtask

    assign codec_byte = request_buffer[process_index];
    assign codec_nibble = process_index[0]
        ? request_buffer[process_index >> 1][7:4]
        : request_buffer[process_index >> 1][3:0];

    repetition_encoder #(
        .DATA_WIDTH(8),
        .REPETITION_COUNT(1)
    ) repetition_encoder_r1 (
        .data(codec_byte),
        .encoded(repetition_r1_encoded)
    );
    assign repetition_r1_received =
        repetition_r1_encoded ^ repetition_r1_error_mask(process_index);
    majority_decoder #(
        .DATA_WIDTH(8),
        .REPETITION_COUNT(1)
    ) repetition_decoder_r1 (
        .encoded(repetition_r1_received),
        .data(repetition_r1_decoded),
        .group_disagreement(repetition_r1_disagreement)
    );

    repetition_encoder #(
        .DATA_WIDTH(8),
        .REPETITION_COUNT(3)
    ) repetition_encoder_r3 (
        .data(codec_byte),
        .encoded(repetition_r3_encoded)
    );
    assign repetition_r3_received =
        repetition_r3_encoded ^ repetition_r3_error_mask(process_index);
    majority_decoder #(
        .DATA_WIDTH(8),
        .REPETITION_COUNT(3)
    ) repetition_decoder_r3 (
        .encoded(repetition_r3_received),
        .data(repetition_r3_decoded),
        .group_disagreement(repetition_r3_disagreement)
    );

    hamming74_encoder hamming_encoder (
        .data(codec_nibble),
        .codeword(hamming_encoded)
    );
    assign hamming_received = hamming_encoded ^ hamming_error_mask(process_index);
    hamming74_decoder hamming_decoder (
        .codeword(hamming_received),
        .data(hamming_decoded),
        .syndrome(hamming_syndrome),
        .corrected(hamming_corrected)
    );

    assign request_ready = !reset && (state == STATE_IDLE);
    assign request_payload_ready = !reset && (state == STATE_COLLECT);
    assign response_valid = !reset && (state == STATE_RESPONSE_HEADER);
    assign response_message_type = response_message_type_reg;
    assign response_flags = response_flags_reg;
    assign response_length = response_length_reg;
    assign response_payload_valid = !reset && (state == STATE_RESPONSE_PAYLOAD);
    assign response_payload_data = response_payload_valid
        ? response_buffer[response_index]
        : 8'h00;
    assign response_payload_last =
        (state == STATE_RESPONSE_PAYLOAD) &&
        ((response_index + 1) == response_length_reg);

    // Payload memory is not exposed until all validation and FEC processing
    // finish, so malformed requests cannot leak partially received Token data.
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            request_flags_reg <= 16'h0000;
            request_length_reg <= 16'h0000;
            response_flags_reg <= 16'h0000;
            response_length_reg <= 16'h0000;
            response_message_type_reg <= 8'h00;
            token_length_reg <= 16'h0000;
            protection_mode_reg <= 8'h00;
            repetition_count_reg <= 8'h01;
            corrected_count_reg <= 16'h0000;
            payload_index <= 0;
            response_index <= 0;
            process_index <= 0;
            tlv_index <= 0;
        end
        else begin
            case (state)
                STATE_IDLE: begin
                    if (request_valid && request_ready) begin
                        request_flags_reg <= request_flags;
                        request_length_reg <= request_length;
                        payload_index <= 0;
                        if (request_length == 0) begin
                            state <= STATE_VALIDATE;
                        end
                        else begin
                            state <= STATE_COLLECT;
                        end
                    end
                end

                STATE_COLLECT: begin
                    if (request_payload_valid && request_payload_ready) begin
                        if (payload_index < MAX_PAYLOAD_BYTES) begin
                            request_buffer[payload_index] <= request_payload_data;
                        end
                        if (request_payload_last) begin
                            if (
                                ((payload_index + 1) == request_length_reg) &&
                                (request_length_reg <= MAX_PAYLOAD_BYTES)
                            ) begin
                                state <= STATE_VALIDATE;
                            end
                            else begin
                                prepare_error_response(FLAG_MALFORMED);
                            end
                        end
                        else if ((payload_index + 1) == request_length_reg) begin
                            prepare_error_response(FLAG_MALFORMED);
                        end
                        else begin
                            payload_index <= payload_index + 1;
                        end
                    end
                end

                STATE_VALIDATE: begin
                    validation_failed = 0;
                    if (request_length_reg < 16'd60) begin
                        prepare_error_response(FLAG_MALFORMED);
                        validation_failed = 1;
                    end
                    else if (request_buffer[0] != protocol_pkg::TOKEN_RECORD_VERSION) begin
                        prepare_error_response(FLAG_UNSUPPORTED_VERSION);
                        validation_failed = 1;
                    end
                    else begin
                        candidate_token_length = 40 + buffer_u16(36);
                        protection_offset = candidate_token_length;
                        channel_offset = protection_offset + 16;
                        if (
                            (buffer_u16(2) != protocol_pkg::TOKEN_RECORD_BASE_SIZE) ||
                            (candidate_token_length > (request_length_reg - 20)) ||
                            (request_length_reg != (candidate_token_length + 20)) ||
                            ((request_buffer[1] & 8'hfc) != 0) ||
                            (request_buffer[16] != 0) ||
                            !buffer_range_is_zero(17, 3) ||
                            !buffer_range_is_zero(38, 2)
                        ) begin
                            prepare_error_response(FLAG_MALFORMED);
                            validation_failed = 1;
                        end
                        else if (
                            (((request_buffer[1] & 8'h01) == 0) &&
                                !buffer_range_is_zero(20, 8)) ||
                            (((request_buffer[1] & 8'h02) == 0) &&
                                !buffer_range_is_zero(28, 8))
                        ) begin
                            prepare_error_response(FLAG_MALFORMED);
                            validation_failed = 1;
                        end
                        else if (
                            (request_buffer[protection_offset] !=
                                protocol_pkg::PROTECTION_REQUEST_VERSION) ||
                            (request_buffer[channel_offset] !=
                                protocol_pkg::CHANNEL_STATE_VERSION)
                        ) begin
                            prepare_error_response(FLAG_UNSUPPORTED_VERSION);
                            validation_failed = 1;
                        end
                        else if (
                            request_buffer[protection_offset + 1] >
                                protocol_pkg::PROTECTION_MODE_HAMMING_7_4
                        ) begin
                            prepare_error_response(FLAG_UNSUPPORTED_PROTECTION);
                            validation_failed = 1;
                        end
                        else if (
                            (buffer_u16(protection_offset + 2) != 0) ||
                            (buffer_u16(protection_offset + 4) !=
                                (candidate_token_length * 8)) ||
                            (request_buffer[protection_offset + 7] != 0) ||
                            !buffer_range_is_zero(protection_offset + 12, 4) ||
                            ((request_buffer[channel_offset + 1] & 8'hfe) != 0) ||
                            (((request_buffer[channel_offset + 1] & 8'h01) == 0) &&
                                (buffer_u16(channel_offset + 2) != 0))
                        ) begin
                            prepare_error_response(FLAG_MALFORMED);
                            validation_failed = 1;
                        end
                        else begin
                            protection_mode_reg <= request_buffer[protection_offset + 1];
                            repetition_count_reg <= request_buffer[protection_offset + 6];
                            if (
                                (request_buffer[protection_offset + 1] ==
                                    protocol_pkg::PROTECTION_MODE_NONE) &&
                                !(
                                    (request_buffer[protection_offset + 6] == 1) &&
                                    (buffer_u16(protection_offset + 8) == 1) &&
                                    (buffer_u16(protection_offset + 10) == 1)
                                )
                            ) begin
                                prepare_error_response(FLAG_MALFORMED);
                                validation_failed = 1;
                            end
                            else if (
                                (request_buffer[protection_offset + 1] ==
                                    protocol_pkg::PROTECTION_MODE_REPETITION) &&
                                !(
                                    ((request_buffer[protection_offset + 6] == 1) ||
                                        (request_buffer[protection_offset + 6] == 3)) &&
                                    (buffer_u16(protection_offset + 8) == 1) &&
                                    (buffer_u16(protection_offset + 10) ==
                                        request_buffer[protection_offset + 6])
                                )
                            ) begin
                                prepare_error_response(FLAG_MALFORMED);
                                validation_failed = 1;
                            end
                            else if (
                                (request_buffer[protection_offset + 1] ==
                                    protocol_pkg::PROTECTION_MODE_HAMMING_7_4) &&
                                !(
                                    (request_buffer[protection_offset + 6] == 1) &&
                                    (buffer_u16(protection_offset + 8) == 4) &&
                                    (buffer_u16(protection_offset + 10) == 7)
                                )
                            ) begin
                                prepare_error_response(FLAG_MALFORMED);
                                validation_failed = 1;
                            end
                        end

                        if (!validation_failed) begin
                            token_length_reg <= candidate_token_length;
                            tlv_index <= 40;
                            state <= STATE_VALIDATE_TLV;
                        end
                    end
                end

                STATE_VALIDATE_TLV: begin
                    if (tlv_index == token_length_reg) begin
                        begin_fec_processing;
                    end
                    else if ((tlv_index + 2) > token_length_reg) begin
                        prepare_error_response(FLAG_MALFORMED);
                    end
                    else begin
                        tlv_value_length = request_buffer[tlv_index + 1];
                        if ((tlv_index + 2 + tlv_value_length) > token_length_reg) begin
                            prepare_error_response(FLAG_MALFORMED);
                        end
                        else begin
                            tlv_index <= tlv_index + 2 + tlv_value_length;
                        end
                    end
                end

                STATE_PROCESS_NONE: begin
                    response_buffer[process_index] <=
                        codec_byte ^ none_error_mask(process_index);
                    if ((process_index + 1) == token_length_reg) begin
                        state <= STATE_FINALIZE;
                    end
                    else begin
                        process_index <= process_index + 1;
                    end
                end

                STATE_PROCESS_REPETITION: begin
                    if (repetition_count_reg == 3) begin
                        response_buffer[process_index] <= repetition_r3_decoded;
                        corrected_count_reg <= corrected_count_reg +
                            count_set_bits(repetition_r3_disagreement);
                    end
                    else begin
                        response_buffer[process_index] <= repetition_r1_decoded;
                    end
                    if ((process_index + 1) == token_length_reg) begin
                        state <= STATE_FINALIZE;
                    end
                    else begin
                        process_index <= process_index + 1;
                    end
                end

                STATE_PROCESS_HAMMING: begin
                    if (process_index[0]) begin
                        response_buffer[process_index >> 1][7:4] <= hamming_decoded;
                    end
                    else begin
                        response_buffer[process_index >> 1][3:0] <= hamming_decoded;
                    end
                    if (hamming_corrected) begin
                        corrected_count_reg <= corrected_count_reg + 1'b1;
                    end
                    if ((process_index + 1) == (token_length_reg * 2)) begin
                        state <= STATE_FINALIZE;
                    end
                    else begin
                        process_index <= process_index + 1;
                    end
                end

                STATE_FINALIZE: begin
                    if (corrected_count_reg != 0) begin
                        response_buffer[token_length_reg] <= FLAG_FEC_CORRECTED[7:0];
                    end
                    else begin
                        response_buffer[token_length_reg] <= 8'h00;
                    end
                    response_buffer[token_length_reg + 1] <= 8'h00;
                    response_buffer[token_length_reg + 2] <= 8'h00;
                    response_buffer[token_length_reg + 3] <= 8'h00;
                    response_buffer[token_length_reg + 4] <= corrected_count_reg[7:0];
                    response_buffer[token_length_reg + 5] <= corrected_count_reg[15:8];
                    response_buffer[token_length_reg + 6] <= 8'h00;
                    response_buffer[token_length_reg + 7] <= 8'h00;
                    response_message_type_reg <= MESSAGE_TOKEN_RESULT;
                    response_flags_reg <= request_flags_reg;
                    response_length_reg <= token_length_reg + 8;
                    state <= STATE_RESPONSE_HEADER;
                end

                STATE_RESPONSE_HEADER: begin
                    if (response_valid && response_ready) begin
                        response_index <= 0;
                        state <= STATE_RESPONSE_PAYLOAD;
                    end
                end

                STATE_RESPONSE_PAYLOAD: begin
                    if (response_payload_valid && response_payload_ready) begin
                        if ((response_index + 1) == response_length_reg) begin
                            state <= STATE_IDLE;
                        end
                        else begin
                            response_index <= response_index + 1;
                        end
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule
