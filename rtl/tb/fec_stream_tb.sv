module fec_stream_tb;
    parameter integer TRANSACTION_COUNT = 128;
    parameter integer MAX_CYCLES = 4096;

    reg clk;
    reg reset;

    reg         r1_in_valid;
    wire        r1_in_ready;
    reg  [7:0]  r1_in_data;
    reg         r1_in_last;
    wire        r1_out_valid;
    reg         r1_out_ready;
    wire [7:0]  r1_out_data;
    wire        r1_out_last;

    reg         r3_in_valid;
    wire        r3_in_ready;
    reg  [7:0]  r3_in_data;
    reg         r3_in_last;
    wire        r3_out_valid;
    reg         r3_out_ready;
    wire [23:0] r3_out_data;
    wire        r3_out_last;

    reg         hamming_in_valid;
    wire        hamming_in_ready;
    reg  [3:0]  hamming_in_data;
    reg         hamming_in_last;
    wire        hamming_out_valid;
    reg         hamming_out_ready;
    wire [6:0]  hamming_out_data;
    wire        hamming_out_last;

    reg         repetition_decode_in_valid;
    wire        repetition_decode_in_ready;
    reg  [23:0] repetition_decode_in_data;
    reg         repetition_decode_in_last;
    wire        repetition_decode_out_valid;
    reg         repetition_decode_out_ready;
    wire [7:0]  repetition_decode_out_data;
    wire [7:0]  repetition_decode_out_disagreement;
    wire        repetition_decode_out_last;

    reg         hamming_decode_in_valid;
    wire        hamming_decode_in_ready;
    reg  [6:0]  hamming_decode_in_data;
    reg         hamming_decode_in_last;
    wire        hamming_decode_out_valid;
    reg         hamming_decode_out_ready;
    wire [3:0]  hamming_decode_out_data;
    wire [2:0]  hamming_decode_out_syndrome;
    wire        hamming_decode_out_corrected;
    wire        hamming_decode_out_last;

    reg [7:0]  r1_expected_data [0:TRANSACTION_COUNT-1];
    reg        r1_expected_last [0:TRANSACTION_COUNT-1];
    reg [23:0] r3_expected_data [0:TRANSACTION_COUNT-1];
    reg        r3_expected_last [0:TRANSACTION_COUNT-1];
    reg [6:0]  hamming_expected_data [0:TRANSACTION_COUNT-1];
    reg        hamming_expected_last [0:TRANSACTION_COUNT-1];
    reg [7:0]  repetition_decode_expected_data [0:TRANSACTION_COUNT-1];
    reg [7:0]  repetition_decode_expected_disagreement [0:TRANSACTION_COUNT-1];
    reg        repetition_decode_expected_last [0:TRANSACTION_COUNT-1];
    reg [3:0]  hamming_decode_expected_data [0:TRANSACTION_COUNT-1];
    reg [2:0]  hamming_decode_expected_syndrome [0:TRANSACTION_COUNT-1];
    reg        hamming_decode_expected_corrected [0:TRANSACTION_COUNT-1];
    reg        hamming_decode_expected_last [0:TRANSACTION_COUNT-1];

    integer result_file;
    integer failure_count;
    reg [8*260-1:0] result_path;

    repetition_stream #(
        .DATA_WIDTH(8),
        .REPETITION_COUNT(1)
    ) repetition_r1 (
        .clk(clk),
        .reset(reset),
        .in_valid(r1_in_valid),
        .in_ready(r1_in_ready),
        .in_data(r1_in_data),
        .in_last(r1_in_last),
        .out_valid(r1_out_valid),
        .out_ready(r1_out_ready),
        .out_data(r1_out_data),
        .out_last(r1_out_last)
    );

    repetition_stream #(
        .DATA_WIDTH(8),
        .REPETITION_COUNT(3)
    ) repetition_r3 (
        .clk(clk),
        .reset(reset),
        .in_valid(r3_in_valid),
        .in_ready(r3_in_ready),
        .in_data(r3_in_data),
        .in_last(r3_in_last),
        .out_valid(r3_out_valid),
        .out_ready(r3_out_ready),
        .out_data(r3_out_data),
        .out_last(r3_out_last)
    );

    hamming74_stream hamming (
        .clk(clk),
        .reset(reset),
        .in_valid(hamming_in_valid),
        .in_ready(hamming_in_ready),
        .in_data(hamming_in_data),
        .in_last(hamming_in_last),
        .out_valid(hamming_out_valid),
        .out_ready(hamming_out_ready),
        .out_data(hamming_out_data),
        .out_last(hamming_out_last)
    );

    repetition_decoder_stream #(
        .DATA_WIDTH(8),
        .REPETITION_COUNT(3)
    ) repetition_decoder (
        .clk(clk),
        .reset(reset),
        .in_valid(repetition_decode_in_valid),
        .in_ready(repetition_decode_in_ready),
        .in_data(repetition_decode_in_data),
        .in_last(repetition_decode_in_last),
        .out_valid(repetition_decode_out_valid),
        .out_ready(repetition_decode_out_ready),
        .out_data(repetition_decode_out_data),
        .out_group_disagreement(repetition_decode_out_disagreement),
        .out_last(repetition_decode_out_last)
    );

    hamming74_decoder_stream hamming_decoder (
        .clk(clk),
        .reset(reset),
        .in_valid(hamming_decode_in_valid),
        .in_ready(hamming_decode_in_ready),
        .in_data(hamming_decode_in_data),
        .in_last(hamming_decode_in_last),
        .out_valid(hamming_decode_out_valid),
        .out_ready(hamming_decode_out_ready),
        .out_data(hamming_decode_out_data),
        .out_syndrome(hamming_decode_out_syndrome),
        .out_corrected(hamming_decode_out_corrected),
        .out_last(hamming_decode_out_last)
    );

    stream_assertions #(
        .DATA_WIDTH(8),
        .SIDEBAND_WIDTH(1)
    ) repetition_r1_assertions (
        .clk(clk),
        .reset(reset),
        .valid(r1_out_valid),
        .ready(r1_out_ready),
        .data(r1_out_data),
        .sideband(r1_out_last)
    );

    stream_assertions #(
        .DATA_WIDTH(24),
        .SIDEBAND_WIDTH(1)
    ) repetition_r3_assertions (
        .clk(clk),
        .reset(reset),
        .valid(r3_out_valid),
        .ready(r3_out_ready),
        .data(r3_out_data),
        .sideband(r3_out_last)
    );

    stream_assertions #(
        .DATA_WIDTH(7),
        .SIDEBAND_WIDTH(1)
    ) hamming_assertions (
        .clk(clk),
        .reset(reset),
        .valid(hamming_out_valid),
        .ready(hamming_out_ready),
        .data(hamming_out_data),
        .sideband(hamming_out_last)
    );

    stream_assertions #(
        .DATA_WIDTH(8),
        .SIDEBAND_WIDTH(9)
    ) repetition_decoder_assertions (
        .clk(clk),
        .reset(reset),
        .valid(repetition_decode_out_valid),
        .ready(repetition_decode_out_ready),
        .data(repetition_decode_out_data),
        .sideband({repetition_decode_out_disagreement, repetition_decode_out_last})
    );

    stream_assertions #(
        .DATA_WIDTH(4),
        .SIDEBAND_WIDTH(5)
    ) hamming_decoder_assertions (
        .clk(clk),
        .reset(reset),
        .valid(hamming_decode_out_valid),
        .ready(hamming_decode_out_ready),
        .data(hamming_decode_out_data),
        .sideband({
            hamming_decode_out_syndrome,
            hamming_decode_out_corrected,
            hamming_decode_out_last
        })
    );

    function [23:0] encode_repetition3;
        input [7:0] value;
        integer bit_index;
        integer copy_index;
        begin
            encode_repetition3 = 24'b0;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                for (copy_index = 0; copy_index < 3; copy_index = copy_index + 1) begin
                    encode_repetition3[(bit_index * 3) + copy_index] = value[bit_index];
                end
            end
        end
    endfunction

    function [6:0] encode_hamming74;
        input [3:0] value;
        begin
            encode_hamming74[0] = value[0] ^ value[1] ^ value[3];
            encode_hamming74[1] = value[0] ^ value[2] ^ value[3];
            encode_hamming74[2] = value[0];
            encode_hamming74[3] = value[1] ^ value[2] ^ value[3];
            encode_hamming74[4] = value[1];
            encode_hamming74[5] = value[2];
            encode_hamming74[6] = value[3];
        end
    endfunction

    task reset_all;
        begin
            reset = 1'b1;
            r1_in_valid = 1'b0;
            r1_in_data = 8'b0;
            r1_in_last = 1'b0;
            r1_out_ready = 1'b0;
            r3_in_valid = 1'b0;
            r3_in_data = 8'b0;
            r3_in_last = 1'b0;
            r3_out_ready = 1'b0;
            hamming_in_valid = 1'b0;
            hamming_in_data = 4'b0;
            hamming_in_last = 1'b0;
            hamming_out_ready = 1'b0;
            repetition_decode_in_valid = 1'b0;
            repetition_decode_in_data = 24'b0;
            repetition_decode_in_last = 1'b0;
            repetition_decode_out_ready = 1'b0;
            hamming_decode_in_valid = 1'b0;
            hamming_decode_in_data = 7'b0;
            hamming_decode_in_last = 1'b0;
            hamming_decode_out_ready = 1'b0;
            repeat (2) @(posedge clk);
            #1;
            if (
                (r1_out_valid !== 1'b0) ||
                (r3_out_valid !== 1'b0) ||
                (hamming_out_valid !== 1'b0) ||
                (repetition_decode_out_valid !== 1'b0) ||
                (hamming_decode_out_valid !== 1'b0)
            ) begin
                $display("FAIL reset did not clear output valid");
                failure_count = failure_count + 1;
            end
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task run_repetition_r1;
        integer sent_count;
        integer received_count;
        integer cycle_count;
        integer stall_count;
        reg [31:0] random_state;
        begin
            reset_all;
            sent_count = 0;
            received_count = 0;
            cycle_count = 0;
            stall_count = 0;
            random_state = 32'h13579bdf;

            begin : r1_transfer_loop
                while ((sent_count < TRANSACTION_COUNT) || (received_count < TRANSACTION_COUNT)) begin
                    @(negedge clk);
                    random_state = (random_state * 32'd1664525) + 32'd1013904223;
                    r1_in_valid = (sent_count < TRANSACTION_COUNT) &&
                        ((sent_count < 16) || random_state[0] || random_state[5]);
                    r1_in_data = (sent_count * 8'h3d) ^ (sent_count >> 1);
                    r1_in_last = (((sent_count + 1) % 13) == 0) ||
                        (sent_count == (TRANSACTION_COUNT - 1));
                    r1_out_ready = (cycle_count < 20) || random_state[2] || random_state[7];

                    @(posedge clk);
                    if ((cycle_count < 16) && !(r1_in_valid && r1_in_ready)) begin
                        $display("FAIL repetition R1 gapless input at cycle %0d", cycle_count);
                        failure_count = failure_count + 1;
                    end
                    if (r1_out_valid && !r1_out_ready) begin
                        stall_count = stall_count + 1;
                    end
                    if (r1_out_valid && r1_out_ready) begin
                        if (received_count >= sent_count) begin
                            $display("FAIL repetition R1 emitted without queued input");
                            failure_count = failure_count + 1;
                        end
                        else if (
                            (r1_out_data !== r1_expected_data[received_count]) ||
                            (r1_out_last !== r1_expected_last[received_count])
                        ) begin
                            $display("FAIL repetition R1 order at item %0d", received_count);
                            failure_count = failure_count + 1;
                        end
                        received_count = received_count + 1;
                    end
                    if (r1_in_valid && r1_in_ready) begin
                        r1_expected_data[sent_count] = r1_in_data;
                        r1_expected_last[sent_count] = r1_in_last;
                        sent_count = sent_count + 1;
                    end
                    cycle_count = cycle_count + 1;
                    if (cycle_count > MAX_CYCLES) begin
                        $display("FAIL repetition R1 timed out");
                        failure_count = failure_count + 1;
                        disable r1_transfer_loop;
                    end
                end
            end

            @(negedge clk);
            r1_in_valid = 1'b0;
            r1_out_ready = 1'b0;
            if ((sent_count != TRANSACTION_COUNT) || (received_count != TRANSACTION_COUNT)) begin
                $display("FAIL repetition R1 count sent=%0d received=%0d", sent_count, received_count);
                failure_count = failure_count + 1;
            end
            if (stall_count == 0) begin
                $display("FAIL repetition R1 did not exercise backpressure");
                failure_count = failure_count + 1;
            end
        end
    endtask

    task run_repetition_r3;
        integer sent_count;
        integer received_count;
        integer cycle_count;
        integer stall_count;
        reg [31:0] random_state;
        begin
            reset_all;
            sent_count = 0;
            received_count = 0;
            cycle_count = 0;
            stall_count = 0;
            random_state = 32'h2468ace1;

            begin : r3_transfer_loop
                while ((sent_count < TRANSACTION_COUNT) || (received_count < TRANSACTION_COUNT)) begin
                    @(negedge clk);
                    random_state = (random_state * 32'd1664525) + 32'd1013904223;
                    r3_in_valid = (sent_count < TRANSACTION_COUNT) &&
                        ((sent_count < 16) || random_state[1] || random_state[6]);
                    r3_in_data = (sent_count * 8'h6b) ^ (sent_count >> 2);
                    r3_in_last = (((sent_count + 1) % 17) == 0) ||
                        (sent_count == (TRANSACTION_COUNT - 1));
                    r3_out_ready = (cycle_count < 20) || random_state[3] || random_state[9];

                    @(posedge clk);
                    if ((cycle_count < 16) && !(r3_in_valid && r3_in_ready)) begin
                        $display("FAIL repetition R3 gapless input at cycle %0d", cycle_count);
                        failure_count = failure_count + 1;
                    end
                    if (r3_out_valid && !r3_out_ready) begin
                        stall_count = stall_count + 1;
                    end
                    if (r3_out_valid && r3_out_ready) begin
                        if (received_count >= sent_count) begin
                            $display("FAIL repetition R3 emitted without queued input");
                            failure_count = failure_count + 1;
                        end
                        else if (
                            (r3_out_data !== r3_expected_data[received_count]) ||
                            (r3_out_last !== r3_expected_last[received_count])
                        ) begin
                            $display("FAIL repetition R3 order at item %0d", received_count);
                            failure_count = failure_count + 1;
                        end
                        received_count = received_count + 1;
                    end
                    if (r3_in_valid && r3_in_ready) begin
                        r3_expected_data[sent_count] = encode_repetition3(r3_in_data);
                        r3_expected_last[sent_count] = r3_in_last;
                        sent_count = sent_count + 1;
                    end
                    cycle_count = cycle_count + 1;
                    if (cycle_count > MAX_CYCLES) begin
                        $display("FAIL repetition R3 timed out");
                        failure_count = failure_count + 1;
                        disable r3_transfer_loop;
                    end
                end
            end

            @(negedge clk);
            r3_in_valid = 1'b0;
            r3_out_ready = 1'b0;
            if ((sent_count != TRANSACTION_COUNT) || (received_count != TRANSACTION_COUNT)) begin
                $display("FAIL repetition R3 count sent=%0d received=%0d", sent_count, received_count);
                failure_count = failure_count + 1;
            end
            if (stall_count == 0) begin
                $display("FAIL repetition R3 did not exercise backpressure");
                failure_count = failure_count + 1;
            end
        end
    endtask

    task run_hamming74;
        integer sent_count;
        integer received_count;
        integer cycle_count;
        integer stall_count;
        reg [31:0] random_state;
        begin
            reset_all;
            sent_count = 0;
            received_count = 0;
            cycle_count = 0;
            stall_count = 0;
            random_state = 32'hdeadbeef;

            begin : hamming_transfer_loop
                while ((sent_count < TRANSACTION_COUNT) || (received_count < TRANSACTION_COUNT)) begin
                    @(negedge clk);
                    random_state = (random_state * 32'd1664525) + 32'd1013904223;
                    hamming_in_valid = (sent_count < TRANSACTION_COUNT) &&
                        ((sent_count < 16) || random_state[0] || random_state[8]);
                    hamming_in_data = (sent_count * 4'h9) ^ (sent_count >> 1);
                    hamming_in_last = (((sent_count + 1) % 19) == 0) ||
                        (sent_count == (TRANSACTION_COUNT - 1));
                    hamming_out_ready = (cycle_count < 20) || random_state[4] || random_state[10];

                    @(posedge clk);
                    if ((cycle_count < 16) && !(hamming_in_valid && hamming_in_ready)) begin
                        $display("FAIL Hamming gapless input at cycle %0d", cycle_count);
                        failure_count = failure_count + 1;
                    end
                    if (hamming_out_valid && !hamming_out_ready) begin
                        stall_count = stall_count + 1;
                    end
                    if (hamming_out_valid && hamming_out_ready) begin
                        if (received_count >= sent_count) begin
                            $display("FAIL Hamming emitted without queued input");
                            failure_count = failure_count + 1;
                        end
                        else if (
                            (hamming_out_data !== hamming_expected_data[received_count]) ||
                            (hamming_out_last !== hamming_expected_last[received_count])
                        ) begin
                            $display("FAIL Hamming order at item %0d", received_count);
                            failure_count = failure_count + 1;
                        end
                        received_count = received_count + 1;
                    end
                    if (hamming_in_valid && hamming_in_ready) begin
                        hamming_expected_data[sent_count] = encode_hamming74(hamming_in_data);
                        hamming_expected_last[sent_count] = hamming_in_last;
                        sent_count = sent_count + 1;
                    end
                    cycle_count = cycle_count + 1;
                    if (cycle_count > MAX_CYCLES) begin
                        $display("FAIL Hamming timed out");
                        failure_count = failure_count + 1;
                        disable hamming_transfer_loop;
                    end
                end
            end

            @(negedge clk);
            hamming_in_valid = 1'b0;
            hamming_out_ready = 1'b0;
            if ((sent_count != TRANSACTION_COUNT) || (received_count != TRANSACTION_COUNT)) begin
                $display("FAIL Hamming count sent=%0d received=%0d", sent_count, received_count);
                failure_count = failure_count + 1;
            end
            if (stall_count == 0) begin
                $display("FAIL Hamming did not exercise backpressure");
                failure_count = failure_count + 1;
            end
        end
    endtask

    task run_repetition_decode;
        integer sent_count;
        integer received_count;
        integer cycle_count;
        integer stall_count;
        integer error_position;
        reg [7:0] source_data;
        reg [31:0] random_state;
        begin
            reset_all;
            sent_count = 0;
            received_count = 0;
            cycle_count = 0;
            stall_count = 0;
            random_state = 32'h0badcafe;

            begin : repetition_decode_loop
                while ((sent_count < TRANSACTION_COUNT) || (received_count < TRANSACTION_COUNT)) begin
                    @(negedge clk);
                    random_state = (random_state * 32'd1664525) + 32'd1013904223;
                    source_data = (sent_count * 8'h47) ^ (sent_count >> 3);
                    error_position = (sent_count * 5) % 24;
                    repetition_decode_in_valid = (sent_count < TRANSACTION_COUNT) &&
                        ((sent_count < 16) || random_state[1] || random_state[7]);
                    repetition_decode_in_data = encode_repetition3(source_data);
                    if ((sent_count % 4) != 0) begin
                        repetition_decode_in_data = repetition_decode_in_data ^
                            (24'b1 << error_position);
                    end
                    repetition_decode_in_last = (((sent_count + 1) % 23) == 0) ||
                        (sent_count == (TRANSACTION_COUNT - 1));
                    repetition_decode_out_ready = (cycle_count < 20) ||
                        random_state[3] || random_state[11];

                    @(posedge clk);
                    if (
                        (cycle_count < 16) &&
                        !(repetition_decode_in_valid && repetition_decode_in_ready)
                    ) begin
                        $display("FAIL repetition decode gapless input at cycle %0d", cycle_count);
                        failure_count = failure_count + 1;
                    end
                    if (repetition_decode_out_valid && !repetition_decode_out_ready) begin
                        stall_count = stall_count + 1;
                    end
                    if (repetition_decode_out_valid && repetition_decode_out_ready) begin
                        if (received_count >= sent_count) begin
                            $display("FAIL repetition decode emitted without queued input");
                            failure_count = failure_count + 1;
                        end
                        else if (
                            (repetition_decode_out_data !==
                                repetition_decode_expected_data[received_count]) ||
                            (repetition_decode_out_disagreement !==
                                repetition_decode_expected_disagreement[received_count]) ||
                            (repetition_decode_out_last !==
                                repetition_decode_expected_last[received_count])
                        ) begin
                            $display("FAIL repetition decode order at item %0d", received_count);
                            failure_count = failure_count + 1;
                        end
                        received_count = received_count + 1;
                    end
                    if (repetition_decode_in_valid && repetition_decode_in_ready) begin
                        repetition_decode_expected_data[sent_count] = source_data;
                        if ((sent_count % 4) == 0) begin
                            repetition_decode_expected_disagreement[sent_count] = 8'b0;
                        end
                        else begin
                            repetition_decode_expected_disagreement[sent_count] =
                                8'b1 << (error_position / 3);
                        end
                        repetition_decode_expected_last[sent_count] = repetition_decode_in_last;
                        sent_count = sent_count + 1;
                    end
                    cycle_count = cycle_count + 1;
                    if (cycle_count > MAX_CYCLES) begin
                        $display("FAIL repetition decode timed out");
                        failure_count = failure_count + 1;
                        disable repetition_decode_loop;
                    end
                end
            end

            @(negedge clk);
            repetition_decode_in_valid = 1'b0;
            repetition_decode_out_ready = 1'b0;
            if ((sent_count != TRANSACTION_COUNT) || (received_count != TRANSACTION_COUNT)) begin
                $display(
                    "FAIL repetition decode count sent=%0d received=%0d",
                    sent_count,
                    received_count
                );
                failure_count = failure_count + 1;
            end
            if (stall_count == 0) begin
                $display("FAIL repetition decode did not exercise backpressure");
                failure_count = failure_count + 1;
            end
        end
    endtask

    task run_hamming_decode;
        integer sent_count;
        integer received_count;
        integer cycle_count;
        integer stall_count;
        integer error_position;
        reg [3:0] source_data;
        reg [31:0] random_state;
        begin
            reset_all;
            sent_count = 0;
            received_count = 0;
            cycle_count = 0;
            stall_count = 0;
            random_state = 32'h55aa1234;

            begin : hamming_decode_loop
                while ((sent_count < TRANSACTION_COUNT) || (received_count < TRANSACTION_COUNT)) begin
                    @(negedge clk);
                    random_state = (random_state * 32'd1664525) + 32'd1013904223;
                    source_data = (sent_count * 4'hd) ^ (sent_count >> 2);
                    error_position = (sent_count * 3) % 7;
                    hamming_decode_in_valid = (sent_count < TRANSACTION_COUNT) &&
                        ((sent_count < 16) || random_state[2] || random_state[8]);
                    hamming_decode_in_data = encode_hamming74(source_data);
                    if ((sent_count % 4) != 0) begin
                        hamming_decode_in_data = hamming_decode_in_data ^
                            (7'b1 << error_position);
                    end
                    hamming_decode_in_last = (((sent_count + 1) % 29) == 0) ||
                        (sent_count == (TRANSACTION_COUNT - 1));
                    hamming_decode_out_ready = (cycle_count < 20) ||
                        random_state[4] || random_state[12];

                    @(posedge clk);
                    if (
                        (cycle_count < 16) &&
                        !(hamming_decode_in_valid && hamming_decode_in_ready)
                    ) begin
                        $display("FAIL Hamming decode gapless input at cycle %0d", cycle_count);
                        failure_count = failure_count + 1;
                    end
                    if (hamming_decode_out_valid && !hamming_decode_out_ready) begin
                        stall_count = stall_count + 1;
                    end
                    if (hamming_decode_out_valid && hamming_decode_out_ready) begin
                        if (received_count >= sent_count) begin
                            $display("FAIL Hamming decode emitted without queued input");
                            failure_count = failure_count + 1;
                        end
                        else if (
                            (hamming_decode_out_data !==
                                hamming_decode_expected_data[received_count]) ||
                            (hamming_decode_out_syndrome !==
                                hamming_decode_expected_syndrome[received_count]) ||
                            (hamming_decode_out_corrected !==
                                hamming_decode_expected_corrected[received_count]) ||
                            (hamming_decode_out_last !==
                                hamming_decode_expected_last[received_count])
                        ) begin
                            $display("FAIL Hamming decode order at item %0d", received_count);
                            failure_count = failure_count + 1;
                        end
                        received_count = received_count + 1;
                    end
                    if (hamming_decode_in_valid && hamming_decode_in_ready) begin
                        hamming_decode_expected_data[sent_count] = source_data;
                        if ((sent_count % 4) == 0) begin
                            hamming_decode_expected_syndrome[sent_count] = 3'b000;
                            hamming_decode_expected_corrected[sent_count] = 1'b0;
                        end
                        else begin
                            hamming_decode_expected_syndrome[sent_count] = error_position + 1;
                            hamming_decode_expected_corrected[sent_count] = 1'b1;
                        end
                        hamming_decode_expected_last[sent_count] = hamming_decode_in_last;
                        sent_count = sent_count + 1;
                    end
                    cycle_count = cycle_count + 1;
                    if (cycle_count > MAX_CYCLES) begin
                        $display("FAIL Hamming decode timed out");
                        failure_count = failure_count + 1;
                        disable hamming_decode_loop;
                    end
                end
            end

            @(negedge clk);
            hamming_decode_in_valid = 1'b0;
            hamming_decode_out_ready = 1'b0;
            if ((sent_count != TRANSACTION_COUNT) || (received_count != TRANSACTION_COUNT)) begin
                $display(
                    "FAIL Hamming decode count sent=%0d received=%0d",
                    sent_count,
                    received_count
                );
                failure_count = failure_count + 1;
            end
            if (stall_count == 0) begin
                $display("FAIL Hamming decode did not exercise backpressure");
                failure_count = failure_count + 1;
            end
        end
    endtask

    task run_reset_pending;
        begin
            reset_all;

            @(negedge clk);
            r1_in_valid = 1'b1;
            r1_in_data = 8'h96;
            r1_in_last = 1'b1;
            r1_out_ready = 1'b0;
            r3_in_valid = 1'b1;
            r3_in_data = 8'h69;
            r3_in_last = 1'b0;
            r3_out_ready = 1'b0;
            hamming_in_valid = 1'b1;
            hamming_in_data = 4'hb;
            hamming_in_last = 1'b1;
            hamming_out_ready = 1'b0;
            repetition_decode_in_valid = 1'b1;
            repetition_decode_in_data = 24'h71c71c;
            repetition_decode_in_last = 1'b1;
            repetition_decode_out_ready = 1'b0;
            hamming_decode_in_valid = 1'b1;
            hamming_decode_in_data = 7'h55;
            hamming_decode_in_last = 1'b0;
            hamming_decode_out_ready = 1'b0;

            @(posedge clk);
            #1;
            if (
                (r1_out_valid !== 1'b1) ||
                (r3_out_valid !== 1'b1) ||
                (hamming_out_valid !== 1'b1) ||
                (repetition_decode_out_valid !== 1'b1) ||
                (hamming_decode_out_valid !== 1'b1)
            ) begin
                $display("FAIL reset case did not create pending outputs");
                failure_count = failure_count + 1;
            end

            @(negedge clk);
            r1_in_valid = 1'b0;
            r3_in_valid = 1'b0;
            hamming_in_valid = 1'b0;
            repetition_decode_in_valid = 1'b0;
            hamming_decode_in_valid = 1'b0;
            reset = 1'b1;
            @(posedge clk);
            #1;
            if (
                (r1_out_valid !== 1'b0) ||
                (r3_out_valid !== 1'b0) ||
                (hamming_out_valid !== 1'b0) ||
                (repetition_decode_out_valid !== 1'b0) ||
                (hamming_decode_out_valid !== 1'b0)
            ) begin
                $display("FAIL reset retained a pending output");
                failure_count = failure_count + 1;
            end

            @(negedge clk);
            reset = 1'b0;
            r1_out_ready = 1'b1;
            r3_out_ready = 1'b1;
            hamming_out_ready = 1'b1;
            repetition_decode_out_ready = 1'b1;
            hamming_decode_out_ready = 1'b1;
            @(posedge clk);
            #1;
            if (
                (r1_out_valid !== 1'b0) ||
                (r3_out_valid !== 1'b0) ||
                (hamming_out_valid !== 1'b0) ||
                (repetition_decode_out_valid !== 1'b0) ||
                (hamming_decode_out_valid !== 1'b0)
            ) begin
                $display("FAIL stale output reappeared after reset");
                failure_count = failure_count + 1;
            end

        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        failure_count = 0;

        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end
        result_file = $fopen(result_path, "w");
        if (result_file == 0) begin
            $fatal(1, "failed to open FEC stream result file");
        end

        run_repetition_r1;
        run_repetition_r3;
        run_repetition_decode;
        run_hamming74;
        run_hamming_decode;
        run_reset_pending;

        if (failure_count == 0) begin
            $fwrite(result_file, "{\"case_id\":\"fec_stream_repetition_encode\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n");
            $fwrite(result_file, "{\"case_id\":\"fec_stream_repetition_decode\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n");
            $fwrite(result_file, "{\"case_id\":\"fec_stream_hamming74_encode\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n");
            $fwrite(result_file, "{\"case_id\":\"fec_stream_hamming74_decode\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n");
        end
        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "fec_stream: %0d failures", failure_count);
        end
        $display("fec_stream: 4 cases passed");
        $finish;
    end

    always #5 clk = ~clk;
endmodule
