module token_request_handler_tb;
    localparam integer MAX_PAYLOAD_BYTES = 1024;
    localparam integer CASE_COUNT = 6;

    reg [0:0] clk;
    reg [0:0] reset;
    reg [0:0] request_valid;
    wire [0:0] request_ready;
    reg [15:0] request_flags;
    reg [15:0] request_length;
    reg [0:0] request_payload_valid;
    wire [0:0] request_payload_ready;
    reg [7:0] request_payload_data;
    reg [0:0] request_payload_last;
    wire [0:0] response_valid;
    reg [0:0] response_ready;
    wire [7:0] response_message_type;
    wire [15:0] response_flags;
    wire [15:0] response_length;
    wire [0:0] response_payload_valid;
    reg [0:0] response_payload_ready;
    wire [7:0] response_payload_data;
    wire [0:0] response_payload_last;

    reg [7:0] base_request [0:MAX_PAYLOAD_BYTES-1];
    reg [7:0] request_bytes [0:MAX_PAYLOAD_BYTES-1];
    reg [7:0] expected_result [0:MAX_PAYLOAD_BYTES-1];
    reg [7:0] received_bytes [0:MAX_PAYLOAD_BYTES-1];
    reg [8*128-1:0] vector_case_id;
    reg [8*1100-1:0] vector_frame;
    reg [8*1100-1:0] vector_payload;
    reg [8*260-1:0] vector_path;
    reg [8*260-1:0] result_path;
    reg [7:0] stalled_data;
    reg [0:0] stalled_last;
    reg [7:0] stalled_message_type;
    reg [15:0] stalled_flags;
    reg [15:0] stalled_length;

    integer vector_file;
    integer result_file;
    integer vector_count;
    integer fields_read;
    integer frame_length_field;
    integer message_type_field;
    integer flags_field;
    integer payload_length_field;
    integer base_request_length;
    integer expected_result_length;
    integer input_index;
    integer output_index;
    integer failure_count;
    integer case_index;
    integer protection_offset;

    token_request_handler #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES),
        .INJECT_ERROR_BIT(0)
    ) dut (
        .clk(clk),
        .reset(reset),
        .request_valid(request_valid),
        .request_ready(request_ready),
        .request_flags(request_flags),
        .request_length(request_length),
        .request_payload_valid(request_payload_valid),
        .request_payload_ready(request_payload_ready),
        .request_payload_data(request_payload_data),
        .request_payload_last(request_payload_last),
        .response_valid(response_valid),
        .response_ready(response_ready),
        .response_message_type(response_message_type),
        .response_flags(response_flags),
        .response_length(response_length),
        .response_payload_valid(response_payload_valid),
        .response_payload_ready(response_payload_ready),
        .response_payload_data(response_payload_data),
        .response_payload_last(response_payload_last)
    );

    task reset_dut;
        begin
            reset = 1'b1;
            request_valid = 1'b0;
            request_flags = 16'h0000;
            request_length = 16'h0000;
            request_payload_valid = 1'b0;
            request_payload_data = 8'h00;
            request_payload_last = 1'b0;
            response_ready = 1'b0;
            response_payload_ready = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task send_current_request;
        input integer length;
        input integer insert_gaps;
        begin
            @(negedge clk);
            request_valid = 1'b1;
            request_flags = 16'h35a7;
            request_length = length;
            while (!request_ready) begin
                @(negedge clk);
            end
            @(posedge clk);
            @(negedge clk);
            request_valid = 1'b0;

            for (input_index = 0; input_index < length; input_index = input_index + 1) begin
                if (insert_gaps && ((input_index % 7) == 3)) begin
                    request_payload_valid = 1'b0;
                    request_payload_last = 1'b0;
                    @(posedge clk);
                    @(negedge clk);
                end
                request_payload_valid = 1'b1;
                request_payload_data = request_bytes[input_index];
                request_payload_last = ((input_index + 1) == length);
                while (!request_payload_ready) begin
                    @(negedge clk);
                end
                @(posedge clk);
                @(negedge clk);
            end
            request_payload_valid = 1'b0;
            request_payload_last = 1'b0;
        end
    endtask

    task receive_response;
        input [7:0] expected_type;
        input integer expected_length;
        begin
            while (!response_valid) begin
                @(negedge clk);
            end

            stalled_message_type = response_message_type;
            stalled_flags = response_flags;
            stalled_length = response_length;
            response_ready = 1'b0;
            repeat (3) begin
                @(posedge clk);
                #1;
                if (
                    (response_valid !== 1'b1) ||
                    (response_message_type !== stalled_message_type) ||
                    (response_flags !== stalled_flags) ||
                    (response_length !== stalled_length)
                ) begin
                    $display("FAIL response header changed during stall");
                    failure_count = failure_count + 1;
                end
            end
            if (
                (response_message_type !== expected_type) ||
                (response_flags !== 16'h35a7) ||
                (response_length !== expected_length)
            ) begin
                $display(
                    "FAIL response header type=%02x flags=%04x length=%0d",
                    response_message_type,
                    response_flags,
                    response_length
                );
                failure_count = failure_count + 1;
            end

            @(negedge clk);
            response_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            response_ready = 1'b0;

            output_index = 0;
            while (output_index < expected_length) begin
                while (!response_payload_valid) begin
                    @(negedge clk);
                end
                if ((output_index % 9) == 2) begin
                    response_payload_ready = 1'b0;
                    stalled_data = response_payload_data;
                    stalled_last = response_payload_last;
                    repeat (2) begin
                        @(posedge clk);
                        #1;
                        if (
                            (response_payload_valid !== 1'b1) ||
                            (response_payload_data !== stalled_data) ||
                            (response_payload_last !== stalled_last)
                        ) begin
                            $display("FAIL response payload changed during stall");
                            failure_count = failure_count + 1;
                        end
                    end
                    @(negedge clk);
                end
                response_payload_ready = 1'b1;
                received_bytes[output_index] = response_payload_data;
                if (response_payload_last !== ((output_index + 1) == expected_length)) begin
                    $display("FAIL response last at byte %0d", output_index);
                    failure_count = failure_count + 1;
                end
                @(posedge clk);
                @(negedge clk);
                response_payload_ready = 1'b0;
                output_index = output_index + 1;
            end
        end
    endtask

    task expect_token_result;
        input integer expected_mode;
        integer index;
        integer expected_corrected;
        begin
            receive_response(protocol_pkg::MESSAGE_TYPE_TOKEN_RESULT, expected_result_length);
            expected_corrected = (expected_mode == protocol_pkg::PROTECTION_MODE_NONE) ? 0 : 1;
            for (index = 0; index < expected_result_length; index = index + 1) begin
                if (expected_mode == protocol_pkg::PROTECTION_MODE_HAMMING_7_4) begin
                    if (received_bytes[index] !== expected_result[index]) begin
                        $display("FAIL Hamming fixed result byte %0d", index);
                        failure_count = failure_count + 1;
                    end
                end
                else if (index < (base_request_length - 20)) begin
                    if (
                        received_bytes[index] !==
                        (base_request[index] ^ ((expected_mode == 0 && index == 0) ? 8'h01 : 8'h00))
                    ) begin
                        $display("FAIL recovered Token byte %0d mode=%0d", index, expected_mode);
                        failure_count = failure_count + 1;
                    end
                end
            end
            if (
                (received_bytes[expected_result_length - 8] !==
                    (expected_corrected ? 8'h02 : 8'h00)) ||
                (received_bytes[expected_result_length - 4] !== expected_corrected)
            ) begin
                $display("FAIL ResultStatus mode=%0d", expected_mode);
                failure_count = failure_count + 1;
            end
        end
    endtask

    task expect_error;
        input [31:0] expected_flags;
        begin
            receive_response(protocol_pkg::MESSAGE_TYPE_ERROR_RESPONSE, 8);
            if (
                (received_bytes[0] !== expected_flags[7:0]) ||
                (received_bytes[1] !== expected_flags[15:8]) ||
                (received_bytes[2] !== expected_flags[23:16]) ||
                (received_bytes[3] !== expected_flags[31:24]) ||
                (received_bytes[4] !== protocol_pkg::MESSAGE_TYPE_TOKEN_REQUEST) ||
                (received_bytes[5] !== 0) ||
                (received_bytes[6] !== 0) ||
                (received_bytes[7] !== 0)
            ) begin
                $display("FAIL error response flags=%08x", expected_flags);
                failure_count = failure_count + 1;
            end
        end
    endtask

    task copy_base_request;
        integer index;
        begin
            for (index = 0; index < base_request_length; index = index + 1) begin
                request_bytes[index] = base_request[index];
            end
        end
    endtask

    task set_protection;
        input [7:0] mode;
        input [7:0] repetition_count;
        input [15:0] rate_num;
        input [15:0] rate_den;
        begin
            request_bytes[protection_offset + 1] = mode;
            request_bytes[protection_offset + 6] = repetition_count;
            request_bytes[protection_offset + 8] = rate_num[7:0];
            request_bytes[protection_offset + 9] = rate_num[15:8];
            request_bytes[protection_offset + 10] = rate_den[7:0];
            request_bytes[protection_offset + 11] = rate_den[15:8];
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        failure_count = 0;
        base_request_length = 0;
        expected_result_length = 0;

        if (!$value$plusargs("VECTOR_FILE=%s", vector_path)) begin
            $fatal(1, "VECTOR_FILE plusarg is required");
        end
        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end
        vector_file = $fopen(vector_path, "r");
        result_file = $fopen(result_path, "w");
        if ((vector_file == 0) || (result_file == 0)) begin
            $fatal(1, "failed to open Token handler vector or result file");
        end

        fields_read = $fscanf(vector_file, "%d\n", vector_count);
        if (fields_read != 1) begin
            $fatal(1, "failed to read protocol vector count");
        end
        for (case_index = 0; case_index < vector_count; case_index = case_index + 1) begin
            fields_read = $fscanf(
                vector_file,
                "%s %d %h %d %d %d %h\n",
                vector_case_id,
                frame_length_field,
                vector_frame,
                message_type_field,
                flags_field,
                payload_length_field,
                vector_payload
            );
            if (fields_read != 7) begin
                $fatal(1, "failed to read protocol vector %0d", case_index);
            end
            if (message_type_field == protocol_pkg::MESSAGE_TYPE_TOKEN_REQUEST) begin
                base_request_length = payload_length_field;
                for (input_index = 0; input_index < payload_length_field; input_index = input_index + 1) begin
                    base_request[input_index] = vector_payload[(input_index * 8) +: 8];
                end
            end
            if (message_type_field == protocol_pkg::MESSAGE_TYPE_TOKEN_RESULT) begin
                expected_result_length = payload_length_field;
                for (input_index = 0; input_index < payload_length_field; input_index = input_index + 1) begin
                    expected_result[input_index] = vector_payload[(input_index * 8) +: 8];
                end
            end
        end
        $fclose(vector_file);
        if ((base_request_length == 0) || (expected_result_length == 0)) begin
            $fatal(1, "protocol vectors lack Token request/result cases");
        end
        protection_offset = 40 + base_request[36] + (base_request[37] << 8);

        reset_dut;

        // Reset must discard a partial request rather than completing it after release.
        copy_base_request;
        @(negedge clk);
        request_valid = 1'b1;
        request_length = base_request_length;
        request_flags = 16'h35a7;
        @(posedge clk);
        @(negedge clk);
        request_valid = 1'b0;
        request_payload_valid = 1'b1;
        request_payload_data = request_bytes[0];
        request_payload_last = 1'b0;
        @(posedge clk);
        @(negedge clk);
        reset = 1'b1;
        request_payload_valid = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        #1;
        if (!request_ready || response_valid || response_payload_valid) begin
            $display("FAIL reset retained partial request state");
            failure_count = failure_count + 1;
        end

        copy_base_request;
        send_current_request(base_request_length, 1);
        expect_token_result(protocol_pkg::PROTECTION_MODE_HAMMING_7_4);

        copy_base_request;
        set_protection(protocol_pkg::PROTECTION_MODE_NONE, 1, 1, 1);
        send_current_request(base_request_length, 0);
        expect_token_result(protocol_pkg::PROTECTION_MODE_NONE);

        copy_base_request;
        set_protection(protocol_pkg::PROTECTION_MODE_REPETITION, 3, 1, 3);
        send_current_request(base_request_length, 1);
        expect_token_result(protocol_pkg::PROTECTION_MODE_REPETITION);

        copy_base_request;
        send_current_request(8, 0);
        expect_error(protocol_pkg::RESULT_FLAG_MALFORMED_REQUEST);

        copy_base_request;
        request_bytes[0] = 8'h02;
        send_current_request(base_request_length, 0);
        expect_error(protocol_pkg::RESULT_FLAG_UNSUPPORTED_VERSION);

        copy_base_request;
        request_bytes[protection_offset + 1] = 8'h7e;
        send_current_request(base_request_length, 0);
        expect_error(protocol_pkg::RESULT_FLAG_UNSUPPORTED_PROTECTION);

        if (failure_count == 0) begin
            $fwrite(result_file, "{\"case_id\":\"token_handler_hamming\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n");
            $fwrite(result_file, "{\"case_id\":\"token_handler_none\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n");
            $fwrite(result_file, "{\"case_id\":\"token_handler_repetition_r3\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n");
            $fwrite(result_file, "{\"case_id\":\"token_handler_malformed\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n");
            $fwrite(result_file, "{\"case_id\":\"token_handler_version\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n");
            $fwrite(result_file, "{\"case_id\":\"token_handler_protection\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n");
        end
        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "token_request_handler: %0d failures", failure_count);
        end
        $display("token_request_handler: 6 cases passed");
        $finish;
    end

    always #5 clk = ~clk;
endmodule
