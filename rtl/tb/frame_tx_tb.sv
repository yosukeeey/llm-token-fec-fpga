module frame_tx_tb;
    localparam integer MAX_PAYLOAD_BYTES = 1024;
    localparam integer MAX_FRAME_BYTES = MAX_PAYLOAD_BYTES + 12;
    localparam integer MAX_VECTOR_COUNT = 8;

    reg [0:0]  clk;
    reg [0:0]  reset;
    reg [0:0]  frame_valid;
    wire [0:0] frame_ready;
    reg [7:0]  message_type;
    reg [15:0] flags;
    reg [15:0] payload_length;
    reg [0:0]  payload_valid;
    wire [0:0] payload_ready;
    reg [7:0]  payload_data;
    wire [0:0] out_valid;
    reg [0:0]  out_ready;
    wire [7:0] out_data;
    wire [31:0] length_error_count;

    reg [8*128-1:0] vector_case_ids [0:MAX_VECTOR_COUNT-1];
    reg [(8*MAX_FRAME_BYTES)-1:0] vector_frames [0:MAX_VECTOR_COUNT-1];
    reg [(8*MAX_PAYLOAD_BYTES)-1:0] vector_payloads [0:MAX_VECTOR_COUNT-1];
    integer vector_frame_lengths [0:MAX_VECTOR_COUNT-1];
    integer vector_message_types [0:MAX_VECTOR_COUNT-1];
    integer vector_flags [0:MAX_VECTOR_COUNT-1];
    integer vector_payload_lengths [0:MAX_VECTOR_COUNT-1];

    reg [8*128-1:0] scanned_case_id;
    reg [(8*MAX_FRAME_BYTES)-1:0] scanned_frame;
    reg [(8*MAX_PAYLOAD_BYTES)-1:0] scanned_payload;
    integer scanned_frame_length;
    integer scanned_message_type;
    integer scanned_flags;
    integer scanned_payload_length;

    integer vector_file;
    integer result_file;
    integer vector_count;
    integer vector_index;
    integer fields_read;
    integer failure_count;
    integer case_count;
    integer expected_vector_index;
    integer expected_byte_index;
    integer source_vector_index;
    integer payload_source_vector;
    integer payload_source_index;
    integer cycle_count;
    integer metadata_stall_count;
    integer payload_stall_count;
    integer output_stall_count;
    integer back_to_back_hold_count;
    integer max_payload_bytes_accepted;
    integer error_count_before;
    reg [7:0] expected_byte;
    reg [7:0] metadata_lfsr;
    reg [7:0] payload_lfsr;
    reg [7:0] output_lfsr;
    reg metadata_pending;
    reg payload_active;
    reg payload_pending;
    reg last_frame_accepted;
    reg last_payload_accepted;
    reg scoreboard_enabled;
    reg scoreboard_reset_case;
    reg reset_frame_complete;
    reg [8*260-1:0] vector_path;
    reg [8*260-1:0] result_path;

    frame_tx #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
    ) dut (
        .clk(clk),
        .reset(reset),
        .frame_valid(frame_valid),
        .frame_ready(frame_ready),
        .message_type(message_type),
        .flags(flags),
        .payload_length(payload_length),
        .payload_valid(payload_valid),
        .payload_ready(payload_ready),
        .payload_data(payload_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_data(out_data),
        .length_error_count(length_error_count)
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

    always @(posedge clk) begin
        last_frame_accepted = 1'b0;
        last_payload_accepted = 1'b0;

        if (reset) begin
            if (
                (frame_ready !== 1'b0) ||
                (payload_ready !== 1'b0) ||
                (out_valid !== 1'b0) ||
                (out_data !== 8'h00)
            ) begin
                $display("FAIL reset did not suppress Frame TX outputs");
                failure_count = failure_count + 1;
            end
        end
        else begin
            last_frame_accepted = frame_valid && frame_ready;
            last_payload_accepted = payload_valid && payload_ready;

            if (frame_valid && !frame_ready) begin
                metadata_stall_count = metadata_stall_count + 1;
                if (source_vector_index != 0) begin
                    back_to_back_hold_count = back_to_back_hold_count + 1;
                end
            end
            if (payload_valid && !payload_ready) begin
                payload_stall_count = payload_stall_count + 1;
            end
            if (out_valid && !out_ready) begin
                output_stall_count = output_stall_count + 1;
            end

            if (scoreboard_enabled && out_valid && out_ready) begin
                if (expected_vector_index >= vector_count) begin
                    $display("FAIL unexpected output byte %02x", out_data);
                    failure_count = failure_count + 1;
                end
                else begin
                    expected_byte = vector_frames[expected_vector_index][
                        (expected_byte_index * 8) +: 8
                    ];
                    if (out_data !== expected_byte) begin
                        $display(
                            "FAIL %0s byte=%0d actual=%02x expected=%02x",
                            vector_case_ids[expected_vector_index],
                            expected_byte_index,
                            out_data,
                            expected_byte
                        );
                        failure_count = failure_count + 1;
                    end

                    if (expected_byte_index + 1 ==
                        vector_frame_lengths[expected_vector_index]) begin
                        if (scoreboard_reset_case) begin
                            record_case("reset_recovery");
                            reset_frame_complete = 1'b1;
                            scoreboard_enabled = 1'b0;
                        end
                        else begin
                            record_case(vector_case_ids[expected_vector_index]);
                            expected_vector_index = expected_vector_index + 1;
                        end
                        expected_byte_index = 0;
                    end
                    else begin
                        expected_byte_index = expected_byte_index + 1;
                    end
                end
            end
        end
    end

    task apply_reset;
        begin
            @(negedge clk);
            frame_valid = 1'b0;
            payload_valid = 1'b0;
            out_ready = 1'b0;
            reset = 1'b1;
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task send_metadata;
        input [7:0] task_message_type;
        input [15:0] task_flags;
        input [15:0] task_payload_length;
        begin
            @(negedge clk);
            message_type = task_message_type;
            flags = task_flags;
            payload_length = task_payload_length;
            frame_valid = 1'b1;
            while (last_frame_accepted !== 1'b1) begin
                @(negedge clk);
            end
            frame_valid = 1'b0;
        end
    endtask

    task send_payload_byte;
        input [7:0] value;
        begin
            @(negedge clk);
            payload_data = value;
            payload_valid = 1'b1;
            while (last_payload_accepted !== 1'b1) begin
                @(negedge clk);
            end
            payload_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        frame_valid = 1'b0;
        message_type = 8'h00;
        flags = 16'h0000;
        payload_length = 16'h0000;
        payload_valid = 1'b0;
        payload_data = 8'h00;
        out_ready = 1'b0;
        failure_count = 0;
        case_count = 0;
        expected_vector_index = 0;
        expected_byte_index = 0;
        metadata_stall_count = 0;
        payload_stall_count = 0;
        output_stall_count = 0;
        back_to_back_hold_count = 0;
        max_payload_bytes_accepted = 0;
        scoreboard_enabled = 1'b0;
        scoreboard_reset_case = 1'b0;
        reset_frame_complete = 1'b0;
        last_frame_accepted = 1'b0;
        last_payload_accepted = 1'b0;

        if (!$value$plusargs("VECTOR_FILE=%s", vector_path)) begin
            $fatal(1, "VECTOR_FILE plusarg is required");
        end
        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end

        vector_file = $fopen(vector_path, "r");
        result_file = $fopen(result_path, "w");
        if ((vector_file == 0) || (result_file == 0)) begin
            $fatal(1, "failed to open Frame TX vector or result file");
        end

        fields_read = $fscanf(vector_file, "%d\n", vector_count);
        if ((fields_read != 1) || (vector_count < 1) ||
            (vector_count > MAX_VECTOR_COUNT)) begin
            $fatal(1, "Frame TX vector count is outside testbench capacity");
        end
        for (vector_index = 0; vector_index < vector_count; vector_index = vector_index + 1) begin
            fields_read = $fscanf(
                vector_file,
                "%s %d %h %d %d %d %h\n",
                scanned_case_id,
                scanned_frame_length,
                scanned_frame,
                scanned_message_type,
                scanned_flags,
                scanned_payload_length,
                scanned_payload
            );
            if (fields_read != 7) begin
                $fatal(1, "failed to read Frame TX vector %0d", vector_index);
            end
            if ((scanned_payload_length > MAX_PAYLOAD_BYTES) ||
                (scanned_frame_length != scanned_payload_length + 12)) begin
                $fatal(1, "invalid Frame TX vector length %0d", vector_index);
            end
            vector_case_ids[vector_index] = scanned_case_id;
            vector_frame_lengths[vector_index] = scanned_frame_length;
            vector_frames[vector_index] = scanned_frame;
            vector_message_types[vector_index] = scanned_message_type;
            vector_flags[vector_index] = scanned_flags;
            vector_payload_lengths[vector_index] = scanned_payload_length;
            vector_payloads[vector_index] = scanned_payload;
        end
        $fclose(vector_file);

        apply_reset();
        scoreboard_enabled = 1'b1;
        source_vector_index = 0;
        payload_source_vector = 0;
        payload_source_index = 0;
        metadata_pending = 1'b0;
        payload_active = 1'b0;
        payload_pending = 1'b0;
        metadata_lfsr = 8'hb4;
        payload_lfsr = 8'h69;
        output_lfsr = 8'he1;
        cycle_count = 0;

        while ((expected_vector_index < vector_count) && (cycle_count < 20000)) begin
            @(negedge clk);

            if (last_frame_accepted) begin
                metadata_pending = 1'b0;
                frame_valid = 1'b0;
                if (vector_payload_lengths[source_vector_index] != 0) begin
                    payload_active = 1'b1;
                    payload_source_vector = source_vector_index;
                    payload_source_index = 0;
                end
                source_vector_index = source_vector_index + 1;
            end

            if (last_payload_accepted) begin
                if (vector_payload_lengths[payload_source_vector] ==
                    MAX_PAYLOAD_BYTES) begin
                    max_payload_bytes_accepted = max_payload_bytes_accepted + 1;
                end
                payload_pending = 1'b0;
                payload_valid = 1'b0;
                if (payload_source_index + 1 ==
                    vector_payload_lengths[payload_source_vector]) begin
                    payload_active = 1'b0;
                end
                else begin
                    payload_source_index = payload_source_index + 1;
                end
            end

            if (
                !metadata_pending &&
                !payload_active &&
                (source_vector_index < vector_count) &&
                ((source_vector_index == 1) || metadata_lfsr[0])
            ) begin
                metadata_pending = 1'b1;
                frame_valid = 1'b1;
                message_type = vector_message_types[source_vector_index];
                flags = vector_flags[source_vector_index];
                payload_length = vector_payload_lengths[source_vector_index];
            end

            if (payload_active && !payload_pending && payload_lfsr[0]) begin
                payload_pending = 1'b1;
                payload_valid = 1'b1;
                payload_data = vector_payloads[payload_source_vector][
                    (payload_source_index * 8) +: 8
                ];
            end

            out_ready = output_lfsr[0];
            metadata_lfsr = {
                metadata_lfsr[6:0],
                metadata_lfsr[7] ^ metadata_lfsr[5] ^ metadata_lfsr[4] ^ metadata_lfsr[3]
            };
            payload_lfsr = {
                payload_lfsr[6:0],
                payload_lfsr[7] ^ payload_lfsr[5] ^ payload_lfsr[1] ^ payload_lfsr[0]
            };
            output_lfsr = {
                output_lfsr[6:0],
                output_lfsr[7] ^ output_lfsr[4] ^ output_lfsr[2] ^ output_lfsr[1]
            };
            cycle_count = cycle_count + 1;
        end

        frame_valid = 1'b0;
        payload_valid = 1'b0;
        out_ready = 1'b0;
        if (expected_vector_index != vector_count) begin
            $fatal(1, "fixed Frame TX vectors timed out");
        end
        if (
            (metadata_stall_count == 0) ||
            (payload_stall_count == 0) ||
            (output_stall_count == 0) ||
            (back_to_back_hold_count == 0)
        ) begin
            $display("FAIL independent stream stalls were not exercised");
            failure_count = failure_count + 1;
        end
        if (max_payload_bytes_accepted != MAX_PAYLOAD_BYTES) begin
            $display(
                "FAIL maximum payload transferred %0d bytes",
                max_payload_bytes_accepted
            );
            failure_count = failure_count + 1;
        end

        error_count_before = length_error_count;
        out_ready = 1'b1;
        send_metadata(8'h7f, 16'h55aa, MAX_PAYLOAD_BYTES + 1);
        repeat (4) @(negedge clk);
        if (
            (length_error_count != error_count_before + 1) ||
            (out_valid !== 1'b0) ||
            (out_data !== 8'h00) ||
            (payload_ready !== 1'b0)
        ) begin
            $display("FAIL oversize frame was not rejected cleanly");
            failure_count = failure_count + 1;
        end
        record_case("oversize_rejected");

        scoreboard_enabled = 1'b0;
        out_ready = 1'b1;
        send_metadata(8'h10, 16'h1234, 16'd4);
        send_payload_byte(8'hde);
        send_payload_byte(8'had);
        @(negedge clk);
        out_ready = 1'b0;
        reset = 1'b1;
        #1;
        if ((out_valid !== 1'b0) || (out_data !== 8'h00)) begin
            $display("FAIL reset exposed a partial frame");
            failure_count = failure_count + 1;
        end
        @(negedge clk);
        reset = 1'b0;
        if ((out_valid !== 1'b0) || (out_data !== 8'h00)) begin
            $display("FAIL stale output remained after reset");
            failure_count = failure_count + 1;
        end

        expected_vector_index = 0;
        expected_byte_index = 0;
        scoreboard_reset_case = 1'b1;
        scoreboard_enabled = 1'b1;
        out_ready = 1'b1;
        send_metadata(
            vector_message_types[0],
            vector_flags[0],
            vector_payload_lengths[0]
        );
        cycle_count = 0;
        while (!reset_frame_complete && (cycle_count < 100)) begin
            @(negedge clk);
            cycle_count = cycle_count + 1;
        end
        if (!reset_frame_complete) begin
            $fatal(1, "Frame TX reset recovery timed out");
        end

        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "frame_tx: %0d checks failed", failure_count);
        end
        if (case_count != vector_count + 2) begin
            $fatal(1, "frame_tx: unexpected case count %0d", case_count);
        end
        $display("frame_tx: %0d cases passed", case_count);
        $finish;
    end
endmodule
