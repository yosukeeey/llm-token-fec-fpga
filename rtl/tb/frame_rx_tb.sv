module frame_rx_tb;
    localparam integer MAX_PAYLOAD_BYTES = 1024;
    localparam integer MAX_FRAME_BYTES = MAX_PAYLOAD_BYTES + 12;
    localparam integer IDLE_TIMEOUT_CYCLES = 4;

    reg [0:0] clk;
    reg [0:0] reset;
    reg [0:0] in_valid;
    wire [0:0] in_ready;
    reg [7:0] in_data;
    wire [0:0] frame_valid;
    reg [0:0] frame_ready;
    wire [7:0] message_type;
    wire [15:0] flags;
    wire [15:0] payload_length;
    wire [0:0] payload_valid;
    reg [0:0] payload_ready;
    wire [7:0] payload_data;
    wire [0:0] payload_last;
    wire [31:0] crc_error_count;
    wire [31:0] length_error_count;
    wire [31:0] version_error_count;
    wire [31:0] timeout_error_count;

    integer vector_file;
    integer result_file;
    integer vector_count;
    integer result_count;
    integer failure_count;
    integer fields_read;
    integer vector_index;
    integer byte_index;
    integer frame_length_value;
    integer expected_message_type;
    integer expected_flags;
    integer expected_payload_length;
    reg [8*128-1:0] vector_case_id;
    reg [8*260-1:0] vector_path;
    reg [8*260-1:0] result_path;
    reg [8*MAX_FRAME_BYTES-1:0] frame_value;
    reg [8*MAX_PAYLOAD_BYTES-1:0] expected_payload;
    reg [8*MAX_FRAME_BYTES-1:0] saved_frame;
    reg [8*MAX_PAYLOAD_BYTES-1:0] saved_payload;
    reg [8*MAX_FRAME_BYTES-1:0] second_frame;
    reg [8*MAX_PAYLOAD_BYTES-1:0] second_payload;
    reg [8*MAX_FRAME_BYTES-1:0] max_frame;
    integer saved_frame_length;
    integer saved_message_type;
    integer saved_flags;
    integer saved_payload_length;
    integer second_frame_length;
    integer second_message_type;
    integer second_flags;
    integer second_payload_length;
    integer max_frame_length;
    integer max_message_type;
    integer max_flags;
    integer max_vector_found;
    reg [7:0] held_payload;
    reg [0:0] held_last;
    reg [8*MAX_FRAME_BYTES-1:0] sof_payload_frame;
    reg [8*MAX_PAYLOAD_BYTES-1:0] sof_payload;

    frame_rx #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES),
        .IDLE_TIMEOUT_CYCLES(IDLE_TIMEOUT_CYCLES)
    ) dut (
        .clk(clk),
        .reset(reset),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_data(in_data),
        .frame_valid(frame_valid),
        .frame_ready(frame_ready),
        .message_type(message_type),
        .flags(flags),
        .payload_length(payload_length),
        .payload_valid(payload_valid),
        .payload_ready(payload_ready),
        .payload_data(payload_data),
        .payload_last(payload_last),
        .crc_error_count(crc_error_count),
        .length_error_count(length_error_count),
        .version_error_count(version_error_count),
        .timeout_error_count(timeout_error_count)
    );

    stream_assertions #(
        .DATA_WIDTH(40),
        .SIDEBAND_WIDTH(1)
    ) metadata_invariants (
        .clk(clk),
        .reset(reset),
        .valid(frame_valid),
        .ready(frame_ready),
        .data({message_type, flags, payload_length}),
        .sideband(1'b0)
    );

    stream_assertions #(
        .DATA_WIDTH(8),
        .SIDEBAND_WIDTH(1)
    ) payload_invariants (
        .clk(clk),
        .reset(reset),
        .valid(payload_valid),
        .ready(payload_ready),
        .data(payload_data),
        .sideband(payload_last)
    );

    always #5 clk = ~clk;

    task apply_reset;
        begin
            @(negedge clk);
            reset = 1'b1;
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task check_max_payload_frame;
        input integer wanted_message_type;
        input integer wanted_flags;
        integer payload_index;
        begin
            while (frame_valid !== 1'b1) begin
                @(negedge clk);
            end
            if (
                (message_type !== wanted_message_type[7:0]) ||
                (flags !== wanted_flags[15:0]) ||
                (payload_length !== MAX_PAYLOAD_BYTES)
            ) begin
                $display("FAIL maximum payload metadata");
                failure_count = failure_count + 1;
            end
            frame_ready = 1'b1;
            @(negedge clk);
            frame_ready = 1'b0;
            for (payload_index = 0; payload_index < MAX_PAYLOAD_BYTES;
                 payload_index = payload_index + 1) begin
                while (payload_valid !== 1'b1) begin
                    @(negedge clk);
                end
                if (
                    (payload_data !== payload_index[7:0]) ||
                    (payload_last !== (payload_index == MAX_PAYLOAD_BYTES - 1))
                ) begin
                    $display("FAIL maximum payload byte %0d", payload_index);
                    failure_count = failure_count + 1;
                end
                payload_ready = 1'b1;
                @(negedge clk);
                payload_ready = 1'b0;
            end
        end
    endtask

    task send_byte;
        input [7:0] value;
        begin
            in_data = value;
            in_valid = 1'b1;
            while (in_ready !== 1'b1) begin
                @(negedge clk);
            end
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task send_frame;
        input integer frame_length;
        input [8*MAX_FRAME_BYTES-1:0] packed_frame;
        input integer corrupt_byte;
        reg [7:0] value;
        begin
            for (byte_index = 0; byte_index < frame_length; byte_index = byte_index + 1) begin
                value = packed_frame[byte_index*8 +: 8];
                if (byte_index == corrupt_byte) begin
                    value = value ^ 8'h01;
                end
                send_byte(value);
            end
        end
    endtask

    task send_frame_range;
        input integer first_byte;
        input integer final_byte;
        input [8*MAX_FRAME_BYTES-1:0] packed_frame;
        begin
            for (byte_index = first_byte; byte_index <= final_byte;
                 byte_index = byte_index + 1) begin
                send_byte(packed_frame[byte_index*8 +: 8]);
            end
        end
    endtask

    task send_two_frames_continuous;
        input integer first_length;
        input [8*MAX_FRAME_BYTES-1:0] first_frame;
        input integer second_length;
        input [8*MAX_FRAME_BYTES-1:0] following_frame;
        integer source_index;
        begin
            in_valid = 1'b1;
            for (source_index = 0; source_index < first_length + second_length;
                 source_index = source_index + 1) begin
                if (source_index < first_length) begin
                    in_data = first_frame[source_index*8 +: 8];
                end
                else begin
                    in_data = following_frame[(source_index-first_length)*8 +: 8];
                end
                while (in_ready !== 1'b1) begin
                    @(negedge clk);
                end
                @(negedge clk);
            end
            in_valid = 1'b0;
        end
    endtask

    task check_frame;
        input integer wanted_message_type;
        input integer wanted_flags;
        input integer wanted_payload_length;
        input [8*MAX_PAYLOAD_BYTES-1:0] wanted_payload;
        input integer apply_stalls;
        integer payload_index;
        integer stall_index;
        reg [39:0] held_metadata;
        begin
            while (frame_valid !== 1'b1) begin
                @(negedge clk);
            end
            if (
                (message_type !== wanted_message_type[7:0]) ||
                (flags !== wanted_flags[15:0]) ||
                (payload_length !== wanted_payload_length[15:0])
            ) begin
                $display("FAIL metadata");
                failure_count = failure_count + 1;
            end

            if (apply_stalls != 0) begin
                held_metadata = {message_type, flags, payload_length};
                for (stall_index = 0; stall_index < 3; stall_index = stall_index + 1) begin
                    @(negedge clk);
                    if (
                        (frame_valid !== 1'b1) ||
                        ({message_type, flags, payload_length} !== held_metadata)
                    ) begin
                        $display("FAIL metadata backpressure");
                        failure_count = failure_count + 1;
                    end
                end
            end

            frame_ready = 1'b1;
            @(negedge clk);
            frame_ready = 1'b0;

            for (payload_index = 0; payload_index < wanted_payload_length;
                 payload_index = payload_index + 1) begin
                while (payload_valid !== 1'b1) begin
                    @(negedge clk);
                end
                if (
                    (payload_data !== wanted_payload[payload_index*8 +: 8]) ||
                    (payload_last !== (payload_index == wanted_payload_length - 1))
                ) begin
                    $display("FAIL payload byte %0d", payload_index);
                    failure_count = failure_count + 1;
                end

                if ((apply_stalls != 0) && (payload_index == 0)) begin
                    held_payload = payload_data;
                    held_last = payload_last;
                    repeat (3) begin
                        @(negedge clk);
                        if (
                            (payload_valid !== 1'b1) ||
                            (payload_data !== held_payload) ||
                            (payload_last !== held_last)
                        ) begin
                            $display("FAIL payload backpressure");
                            failure_count = failure_count + 1;
                        end
                    end
                end

                payload_ready = 1'b1;
                @(negedge clk);
                payload_ready = 1'b0;
            end

            if ((wanted_payload_length == 0) && (payload_valid !== 1'b0)) begin
                $display("FAIL empty payload became valid");
                failure_count = failure_count + 1;
            end
        end
    endtask

    task check_frame_random_stalls;
        input integer wanted_message_type;
        input integer wanted_flags;
        input integer wanted_payload_length;
        input [8*MAX_PAYLOAD_BYTES-1:0] wanted_payload;
        integer payload_index;
        integer stall_cycles;
        integer lfsr;
        begin
            lfsr = 16'h1d3f;
            while (frame_valid !== 1'b1) begin
                @(negedge clk);
            end
            if (
                (message_type !== wanted_message_type[7:0]) ||
                (flags !== wanted_flags[15:0]) ||
                (payload_length !== wanted_payload_length[15:0])
            ) begin
                $display("FAIL random-stall metadata");
                failure_count = failure_count + 1;
            end
            stall_cycles = (lfsr & 3) + 1;
            repeat (stall_cycles) @(negedge clk);
            frame_ready = 1'b1;
            @(negedge clk);
            frame_ready = 1'b0;

            for (payload_index = 0; payload_index < wanted_payload_length;
                 payload_index = payload_index + 1) begin
                while (payload_valid !== 1'b1) begin
                    @(negedge clk);
                end
                if (
                    (payload_data !== wanted_payload[payload_index*8 +: 8]) ||
                    (payload_last !== (payload_index == wanted_payload_length - 1))
                ) begin
                    $display("FAIL random-stall payload byte %0d", payload_index);
                    failure_count = failure_count + 1;
                end
                lfsr = (lfsr >> 1) ^ ((lfsr & 1) ? 16'hb400 : 0);
                stall_cycles = lfsr & 3;
                repeat (stall_cycles) @(negedge clk);
                payload_ready = 1'b1;
                @(negedge clk);
                payload_ready = 1'b0;
            end
        end
    endtask

    task record_pass;
        input [8*64-1:0] case_id;
        begin
            $fwrite(
                result_file,
                "{\"case_id\":\"%0s\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n",
                case_id
            );
            result_count = result_count + 1;
            $fflush(result_file);
        end
    endtask

    initial begin
        repeat (20000) @(posedge clk);
        $fatal(1, "frame_rx testbench watchdog expired");
    end

    initial begin
        clk = 1'b0;
        reset = 1'b0;
        in_valid = 1'b0;
        in_data = 8'h00;
        frame_ready = 1'b0;
        payload_ready = 1'b0;
        result_count = 0;
        failure_count = 0;
        max_vector_found = 0;
        sof_payload_frame = '0;
        sof_payload_frame[0 +: 112] = 112'hb8ebaf785aa50002000001005aa5;
        sof_payload = '0;
        sof_payload[0 +: 16] = 16'h5aa5;

        if (!$value$plusargs("VECTOR_FILE=%s", vector_path)) begin
            $fatal(1, "VECTOR_FILE plusarg is required");
        end
        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end
        vector_file = $fopen(vector_path, "r");
        result_file = $fopen(result_path, "w");
        if ((vector_file == 0) || (result_file == 0)) begin
            $fatal(1, "failed to open Frame RX vector or result file");
        end

        apply_reset();

        fields_read = $fscanf(vector_file, "%d\n", vector_count);
        if (fields_read != 1) begin
            $fatal(1, "failed to read Frame RX vector count");
        end
        for (vector_index = 0; vector_index < vector_count;
             vector_index = vector_index + 1) begin
            frame_value = '0;
            expected_payload = '0;
            fields_read = $fscanf(
                vector_file,
                "%s %d %h %d %d %d %h\n",
                vector_case_id,
                frame_length_value,
                frame_value,
                expected_message_type,
                expected_flags,
                expected_payload_length,
                expected_payload
            );
            if (fields_read != 7) begin
                $fatal(1, "failed to read Frame RX vector %0d", vector_index);
            end
            if (frame_length_value > MAX_FRAME_BYTES) begin
                $fatal(1, "Frame RX vector exceeds testbench capacity");
            end

            if (vector_index == 0) begin
                saved_frame = frame_value;
                saved_payload = expected_payload;
                saved_frame_length = frame_length_value;
                saved_message_type = expected_message_type;
                saved_flags = expected_flags;
                saved_payload_length = expected_payload_length;
            end
            if (vector_index == 1) begin
                second_frame = frame_value;
                second_payload = expected_payload;
                second_frame_length = frame_length_value;
                second_message_type = expected_message_type;
                second_flags = expected_flags;
                second_payload_length = expected_payload_length;
            end
            if (expected_payload_length == MAX_PAYLOAD_BYTES) begin
                max_frame = frame_value;
                max_frame_length = frame_length_value;
                max_message_type = expected_message_type;
                max_flags = expected_flags;
                max_vector_found = 1;
            end

            send_frame(frame_length_value, frame_value, -1);
            if (expected_payload_length == MAX_PAYLOAD_BYTES) begin
                check_max_payload_frame(expected_message_type, expected_flags);
            end
            else begin
                check_frame(
                    expected_message_type,
                    expected_flags,
                    expected_payload_length,
                    expected_payload,
                    0
                );
            end
        end
        record_pass("fixed_vectors");

        if (max_vector_found == 0) begin
            $fatal(1, "maximum payload vector is required");
        end
        send_frame(max_frame_length, max_frame, -1);
        check_max_payload_frame(max_message_type, max_flags);
        record_pass("max_payload");

        send_frame(saved_frame_length, saved_frame, -1);
        check_frame(
            saved_message_type,
            saved_flags,
            saved_payload_length,
            saved_payload,
            1
        );
        record_pass("output_stalls");

        send_frame(saved_frame_length, saved_frame, saved_frame_length - 1);
        repeat (3) @(negedge clk);
        if ((frame_valid !== 1'b0) || (crc_error_count !== 1)) begin
            $display("FAIL CRC rejection");
            failure_count = failure_count + 1;
        end
        send_frame(saved_frame_length, saved_frame, -1);
        check_frame(
            saved_message_type,
            saved_flags,
            saved_payload_length,
            saved_payload,
            0
        );
        record_pass("crc_recovery");

        send_byte(protocol_pkg::FRAME_SOF_0);
        send_byte(protocol_pkg::FRAME_SOF_1);
        send_byte(protocol_pkg::FRAME_VERSION);
        send_byte(8'h01);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h01);
        send_byte(8'h04);
        send_byte(protocol_pkg::FRAME_SOF_0);
        send_byte(protocol_pkg::FRAME_SOF_1);
        send_byte(8'h01);
        if ((length_error_count !== 1) || (version_error_count !== 1)) begin
            $display("FAIL header error counters");
            failure_count = failure_count + 1;
        end
        send_frame(saved_frame_length, saved_frame, -1);
        check_frame(
            saved_message_type,
            saved_flags,
            saved_payload_length,
            saved_payload,
            0
        );
        record_pass("header_errors");

        send_byte(protocol_pkg::FRAME_SOF_0);
        send_byte(protocol_pkg::FRAME_SOF_1);
        send_byte(protocol_pkg::FRAME_VERSION);
        repeat (IDLE_TIMEOUT_CYCLES + 1) @(negedge clk);
        if (timeout_error_count !== 1) begin
            $display("FAIL timeout counter");
            failure_count = failure_count + 1;
        end
        send_frame(saved_frame_length, saved_frame, -1);
        check_frame(
            saved_message_type,
            saved_flags,
            saved_payload_length,
            saved_payload,
            0
        );
        record_pass("timeout_recovery");

        send_byte(protocol_pkg::FRAME_SOF_0);
        send_byte(protocol_pkg::FRAME_SOF_1);
        send_byte(protocol_pkg::FRAME_VERSION);
        send_byte(8'h01);
        apply_reset();
        if (
            (crc_error_count !== 0) ||
            (length_error_count !== 0) ||
            (version_error_count !== 0) ||
            (timeout_error_count !== 0)
        ) begin
            $display("FAIL reset counters");
            failure_count = failure_count + 1;
        end
        send_frame(saved_frame_length, saved_frame, -1);
        check_frame(
            saved_message_type,
            saved_flags,
            saved_payload_length,
            saved_payload,
            0
        );
        record_pass("reset_recovery");

        send_byte(8'h00);
        send_byte(8'h3c);
        send_byte(protocol_pkg::FRAME_SOF_0);
        send_byte(protocol_pkg::FRAME_SOF_0);
        send_byte(protocol_pkg::FRAME_SOF_1);
        send_frame_range(2, 13, sof_payload_frame);
        check_frame(1, 0, 2, sof_payload, 0);
        record_pass("sof_resynchronization");

        send_frame_range(0, 2, sof_payload_frame);
        repeat (IDLE_TIMEOUT_CYCLES + 1) @(negedge clk);
        send_frame(14, sof_payload_frame, -1);
        check_frame(1, 0, 2, sof_payload, 0);

        send_frame_range(0, 8, sof_payload_frame);
        repeat (IDLE_TIMEOUT_CYCLES + 1) @(negedge clk);
        send_frame(14, sof_payload_frame, -1);
        check_frame(1, 0, 2, sof_payload, 0);

        send_frame_range(0, 10, sof_payload_frame);
        repeat (IDLE_TIMEOUT_CYCLES + 1) @(negedge clk);
        send_frame(14, sof_payload_frame, -1);
        check_frame(1, 0, 2, sof_payload, 0);
        if (timeout_error_count !== 3) begin
            $display("FAIL timeout positions count=%0d", timeout_error_count);
            failure_count = failure_count + 1;
        end
        record_pass("timeout_positions");

        fork
            send_two_frames_continuous(
                saved_frame_length,
                saved_frame,
                second_frame_length,
                second_frame
            );
            begin
                check_frame_random_stalls(
                    saved_message_type,
                    saved_flags,
                    saved_payload_length,
                    saved_payload
                );
                check_frame_random_stalls(
                    second_message_type,
                    second_flags,
                    second_payload_length,
                    second_payload
                );
            end
        join
        record_pass("continuous_source_random_stalls");

        $fclose(vector_file);
        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "frame_rx: %0d checks failed", failure_count);
        end
        if (result_count != 10) begin
            $fatal(1, "frame_rx: unexpected result count %0d", result_count);
        end
        $display("frame_rx: 10 cases passed");
        $finish;
    end
endmodule
