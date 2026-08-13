module frame_pipeline_tb;
    localparam integer MAX_FRAME_BYTES = 1036;

    reg [0:0]  clk;
    reg [0:0]  reset;
    reg [0:0]  in_valid;
    wire [0:0] in_ready;
    reg [7:0]  in_data;
    wire [0:0] out_valid;
    reg [0:0]  out_ready;
    wire [7:0] out_data;
    wire [31:0] crc_error_count;
    wire [31:0] length_error_count;
    wire [31:0] version_error_count;
    wire [31:0] timeout_error_count;
    wire [31:0] handler_error_count;

    reg [8*128-1:0] ping_case_id;
    reg [(8*MAX_FRAME_BYTES)-1:0] ping_request;
    reg [(8*MAX_FRAME_BYTES)-1:0] ping_response;
    reg [(8*MAX_FRAME_BYTES)-1:0] unsupported_request;
    integer ping_request_length;
    integer ping_response_length;
    integer unsupported_request_length;
    integer vector_count;
    integer vector_file;
    integer result_file;
    integer fields_read;
    integer failure_count;
    integer case_count;
    integer input_stall_count;
    integer output_stall_count;
    integer expected_response_index;
    integer received_response_count;
    integer target_response_count;
    integer cycle_count;
    integer handler_count_before;
    integer byte_index;
    integer repeat_index;
    integer protected_index;
    reg [31:0] unsupported_crc;
    reg [7:0] expected_byte;
    reg [7:0] input_lfsr;
    reg [7:0] output_lfsr;
    reg last_input_accepted;
    reg scoreboard_enabled;
    reg reject_output_watch;
    reg random_output_ready;
    reg [8*260-1:0] vector_path;
    reg [8*260-1:0] result_path;

    frame_pipeline dut (
        .clk(clk),
        .reset(reset),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_data(in_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_data(out_data),
        .crc_error_count(crc_error_count),
        .length_error_count(length_error_count),
        .version_error_count(version_error_count),
        .timeout_error_count(timeout_error_count),
        .handler_error_count(handler_error_count)
    );

    stream_assertions #(
        .DATA_WIDTH(8),
        .SIDEBAND_WIDTH(1)
    ) output_invariants (
        .clk(clk),
        .reset(reset),
        .valid(out_valid),
        .ready(out_ready),
        .data(out_data),
        .sideband(1'b0)
    );

    always #5 clk = ~clk;

    function [7:0] next_lfsr;
        input [7:0] value;
        begin
            next_lfsr = {
                value[6:0],
                value[7] ^ value[5] ^ value[4] ^ value[3]
            };
        end
    endfunction

    function [31:0] crc32c_byte;
        input [31:0] crc;
        input [7:0] data;
        integer bit_position;
        reg [31:0] value;
        begin
            value = crc ^ {24'h000000, data};
            for (bit_position = 0; bit_position < 8; bit_position = bit_position + 1) begin
                if (value[0]) begin
                    value = (value >> 1) ^ 32'h82f63b78;
                end
                else begin
                    value = value >> 1;
                end
            end
            crc32c_byte = value;
        end
    endfunction

    task record_case;
        input [8*128-1:0] case_id;
        begin
            $fwrite(
                result_file,
                "{\"case_id\":\"%0s\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n",
                case_id
            );
            case_count = case_count + 1;
        end
    endtask

    always @(negedge clk) begin
        if (reset) begin
            out_ready = 1'b0;
        end
        else if (random_output_ready) begin
            out_ready = output_lfsr[0];
            output_lfsr = next_lfsr(output_lfsr);
        end
    end

    always @(posedge clk) begin
        last_input_accepted = 1'b0;
        if (reset) begin
            if ((out_valid !== 1'b0) || (out_data !== 8'h00)) begin
                $display("FAIL reset exposed pipeline output");
                failure_count = failure_count + 1;
            end
        end
        else begin
            last_input_accepted = in_valid && in_ready;
            if (in_valid && !in_ready) begin
                input_stall_count = input_stall_count + 1;
            end
            if (out_valid && !out_ready) begin
                output_stall_count = output_stall_count + 1;
            end

            if (out_valid && out_ready) begin
                if (scoreboard_enabled) begin
                    expected_byte = ping_response[(expected_response_index * 8) +: 8];
                    if (out_data !== expected_byte) begin
                        $display(
                            "FAIL response=%0d byte=%0d actual=%02x expected=%02x",
                            received_response_count,
                            expected_response_index,
                            out_data,
                            expected_byte
                        );
                        failure_count = failure_count + 1;
                    end
                    if (expected_response_index + 1 == ping_response_length) begin
                        expected_response_index = 0;
                        received_response_count = received_response_count + 1;
                    end
                    else begin
                        expected_response_index = expected_response_index + 1;
                    end
                end
                else if (reject_output_watch) begin
                    $display("FAIL unsupported frame produced output %02x", out_data);
                    failure_count = failure_count + 1;
                end
            end
        end
    end

    task apply_reset;
        begin
            @(negedge clk);
            in_valid = 1'b0;
            random_output_ready = 1'b0;
            out_ready = 1'b0;
            reset = 1'b1;
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task send_repeated_stream;
        input integer stream_length;
        input [(8*MAX_FRAME_BYTES)-1:0] stream_data;
        input integer stream_repeat_count;
        input integer enable_input_stalls;
        reg started;
        begin
            started = 1'b0;
            for (repeat_index = 0; repeat_index < stream_repeat_count;
                 repeat_index = repeat_index + 1) begin
                for (byte_index = 0; byte_index < stream_length;
                     byte_index = byte_index + 1) begin
                    if (!started) begin
                        @(negedge clk);
                        started = 1'b1;
                    end
                    while (enable_input_stalls && !input_lfsr[0]) begin
                        in_valid = 1'b0;
                        input_lfsr = next_lfsr(input_lfsr);
                        @(negedge clk);
                    end
                    in_data = stream_data[(byte_index * 8) +: 8];
                    in_valid = 1'b1;
                    input_lfsr = next_lfsr(input_lfsr);
                    @(negedge clk);
                    while (last_input_accepted !== 1'b1) begin
                        @(negedge clk);
                    end
                    in_valid = 1'b0;
                end
            end
        end
    endtask

    task build_unsupported_request;
        begin
            unsupported_request = {(8*MAX_FRAME_BYTES){1'b0}};
            unsupported_request_length = 15;
            unsupported_request[0 +: 8] = protocol_pkg::FRAME_SOF_0;
            unsupported_request[8 +: 8] = protocol_pkg::FRAME_SOF_1;
            unsupported_request[16 +: 8] = protocol_pkg::FRAME_VERSION;
            unsupported_request[24 +: 8] = protocol_pkg::MESSAGE_TYPE_TOKEN_REQUEST;
            unsupported_request[32 +: 8] = 8'h00;
            unsupported_request[40 +: 8] = 8'h00;
            unsupported_request[48 +: 8] = 8'h03;
            unsupported_request[56 +: 8] = 8'h00;
            unsupported_request[64 +: 8] = 8'h11;
            unsupported_request[72 +: 8] = 8'h22;
            unsupported_request[80 +: 8] = 8'h33;

            unsupported_crc = 32'hffffffff;
            for (protected_index = 2; protected_index < 11;
                 protected_index = protected_index + 1) begin
                unsupported_crc = crc32c_byte(
                    unsupported_crc,
                    unsupported_request[(protected_index * 8) +: 8]
                );
            end
            unsupported_crc = unsupported_crc ^ 32'hffffffff;
            unsupported_request[88 +: 8] = unsupported_crc[7:0];
            unsupported_request[96 +: 8] = unsupported_crc[15:8];
            unsupported_request[104 +: 8] = unsupported_crc[23:16];
            unsupported_request[112 +: 8] = unsupported_crc[31:24];
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        in_valid = 1'b0;
        in_data = 8'h00;
        out_ready = 1'b0;
        failure_count = 0;
        case_count = 0;
        input_stall_count = 0;
        output_stall_count = 0;
        expected_response_index = 0;
        received_response_count = 0;
        target_response_count = 0;
        scoreboard_enabled = 1'b0;
        reject_output_watch = 1'b0;
        random_output_ready = 1'b0;
        last_input_accepted = 1'b0;
        input_lfsr = 8'h6d;
        output_lfsr = 8'hb7;

        if (!$value$plusargs("VECTOR_FILE=%s", vector_path)) begin
            $fatal(1, "VECTOR_FILE plusarg is required");
        end
        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end
        vector_file = $fopen(vector_path, "r");
        result_file = $fopen(result_path, "w");
        if ((vector_file == 0) || (result_file == 0)) begin
            $fatal(1, "failed to open pipeline vector or result file");
        end

        fields_read = $fscanf(vector_file, "%d\n", vector_count);
        if ((fields_read != 1) || (vector_count < 1)) begin
            $fatal(1, "pipeline vector file is empty");
        end
        fields_read = $fscanf(
            vector_file,
            "%s %d %h %d %h\n",
            ping_case_id,
            ping_request_length,
            ping_request,
            ping_response_length,
            ping_response
        );
        if ((fields_read != 5) || (ping_request_length == 0) ||
            (ping_response_length == 0)) begin
            $fatal(1, "failed to read the first PING pipeline vector");
        end
        $fclose(vector_file);
        build_unsupported_request();

        apply_reset();
        scoreboard_enabled = 1'b1;
        received_response_count = 0;
        expected_response_index = 0;
        target_response_count = 2;
        random_output_ready = 1'b1;
        send_repeated_stream(ping_request_length, ping_request, 2, 1);
        cycle_count = 0;
        while ((received_response_count < target_response_count) &&
               (cycle_count < 2000)) begin
            @(negedge clk);
            cycle_count = cycle_count + 1;
        end
        if (received_response_count != target_response_count) begin
            $fatal(1, "continuous PING responses timed out");
        end
        if ((input_stall_count == 0) || (output_stall_count == 0)) begin
            $display("FAIL independent input/output stalls were not exercised");
            failure_count = failure_count + 1;
        end
        if ((crc_error_count != 0) || (length_error_count != 0) ||
            (version_error_count != 0) || (timeout_error_count != 0) ||
            (handler_error_count != 0)) begin
            $display("FAIL valid PING changed an error counter");
            failure_count = failure_count + 1;
        end
        scoreboard_enabled = 1'b0;
        record_case("continuous_ping");

        reject_output_watch = 1'b1;
        handler_count_before = handler_error_count;
        send_repeated_stream(unsupported_request_length, unsupported_request, 1, 1);
        cycle_count = 0;
        while ((handler_error_count == handler_count_before) && (cycle_count < 100)) begin
            @(negedge clk);
            cycle_count = cycle_count + 1;
        end
        repeat (8) @(negedge clk);
        if (handler_error_count != handler_count_before + 1) begin
            $display("FAIL unsupported frame was not counted once");
            failure_count = failure_count + 1;
        end
        if ((crc_error_count != 0) || (length_error_count != 0) ||
            (version_error_count != 0) || (timeout_error_count != 0)) begin
            $display("FAIL valid unsupported frame changed an RX error counter");
            failure_count = failure_count + 1;
        end
        reject_output_watch = 1'b0;
        record_case("non_ping_drain");

        send_repeated_stream(5, ping_request, 1, 0);
        apply_reset();
        if ((crc_error_count != 0) || (length_error_count != 0) ||
            (version_error_count != 0) || (timeout_error_count != 0) ||
            (handler_error_count != 0) || (out_valid !== 1'b0) ||
            (out_data !== 8'h00)) begin
            $display("FAIL pipeline reset did not clear partial state");
            failure_count = failure_count + 1;
        end

        received_response_count = 0;
        expected_response_index = 0;
        target_response_count = 1;
        scoreboard_enabled = 1'b1;
        random_output_ready = 1'b1;
        send_repeated_stream(ping_request_length, ping_request, 1, 1);
        cycle_count = 0;
        while ((received_response_count < target_response_count) &&
               (cycle_count < 1000)) begin
            @(negedge clk);
            cycle_count = cycle_count + 1;
        end
        if (received_response_count != target_response_count) begin
            $fatal(1, "pipeline reset recovery timed out");
        end
        scoreboard_enabled = 1'b0;
        record_case("reset_recovery");

        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "frame_pipeline: %0d checks failed", failure_count);
        end
        if (case_count != 3) begin
            $fatal(1, "frame_pipeline: unexpected case count %0d", case_count);
        end
        $display("frame_pipeline: 3 cases passed");
        $finish;
    end
endmodule
