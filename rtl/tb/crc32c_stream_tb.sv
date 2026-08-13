module crc32c_stream_tb;
    reg         clk;
    reg         reset;
    reg         input_valid;
    wire        input_ready;
    reg  [7:0]  input_data;
    reg         input_start;
    reg         input_last;
    reg         input_empty;
    wire        output_valid;
    reg         output_ready;
    wire [31:0] output_crc;

    integer result_file;
    integer case_count;
    integer failure_count;
    integer stall_index;
    reg [31:0] held_crc;
    reg [8*260-1:0] result_path;

    crc32c_stream dut (
        .clk(clk),
        .reset(reset),
        .input_valid(input_valid),
        .input_ready(input_ready),
        .input_data(input_data),
        .input_start(input_start),
        .input_last(input_last),
        .input_empty(input_empty),
        .output_valid(output_valid),
        .output_ready(output_ready),
        .output_crc(output_crc)
    );

    stream_assertions #(
        .DATA_WIDTH(32),
        .SIDEBAND_WIDTH(1)
    ) output_invariants (
        .clk(clk),
        .reset(reset),
        .valid(output_valid),
        .ready(output_ready),
        .data(output_crc),
        .sideband(1'b0)
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

    task send_beat;
        input [7:0] value;
        input first;
        input last_beat;
        input empty;
        input integer idle_cycles;
        integer idle_index;
        begin
            input_valid = 1'b0;
            for (idle_index = 0; idle_index < idle_cycles; idle_index = idle_index + 1) begin
                @(negedge clk);
            end
            input_data = value;
            input_start = first;
            input_last = last_beat;
            input_empty = empty;
            input_valid = 1'b1;
            while (input_ready !== 1'b1) begin
                @(negedge clk);
            end
            @(negedge clk);
            input_valid = 1'b0;
            input_start = 1'b0;
            input_last = 1'b0;
            input_empty = 1'b0;
        end
    endtask

    task expect_result;
        input [31:0] expected_crc;
        input [8*64-1:0] case_id;
        begin
            if ((output_valid !== 1'b1) || (output_crc !== expected_crc)) begin
                $display(
                    "FAIL %0s: valid=%b crc=%08x expected=%08x",
                    case_id,
                    output_valid,
                    output_crc,
                    expected_crc
                );
                failure_count = failure_count + 1;
            end
            $fwrite(
                result_file,
                "{\"case_id\":\"%0s\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n",
                case_id
            );
            case_count = case_count + 1;
            @(negedge clk);
        end
    endtask

    task send_123456789;
        input integer idle_cycles;
        begin
            send_beat(8'h31, 1'b1, 1'b0, 1'b0, idle_cycles);
            send_beat(8'h32, 1'b0, 1'b0, 1'b0, idle_cycles);
            send_beat(8'h33, 1'b0, 1'b0, 1'b0, idle_cycles);
            send_beat(8'h34, 1'b0, 1'b0, 1'b0, idle_cycles);
            send_beat(8'h35, 1'b0, 1'b0, 1'b0, idle_cycles);
            send_beat(8'h36, 1'b0, 1'b0, 1'b0, idle_cycles);
            send_beat(8'h37, 1'b0, 1'b0, 1'b0, idle_cycles);
            send_beat(8'h38, 1'b0, 1'b0, 1'b0, idle_cycles);
            send_beat(8'h39, 1'b0, 1'b1, 1'b0, idle_cycles);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b0;
        input_valid = 1'b0;
        input_data = 8'h00;
        input_start = 1'b0;
        input_last = 1'b0;
        input_empty = 1'b0;
        output_ready = 1'b1;
        case_count = 0;
        failure_count = 0;

        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end
        result_file = $fopen(result_path, "w");
        if (result_file == 0) begin
            $fatal(1, "failed to open CRC result file");
        end

        apply_reset();

        send_123456789(0);
        expect_result(32'he3069283, "known_answer");

        send_beat(8'h00, 1'b1, 1'b1, 1'b1, 0);
        expect_result(32'h00000000, "empty_packet");

        send_beat(8'h61, 1'b1, 1'b1, 1'b0, 0);
        if ((output_valid !== 1'b1) || (output_crc !== 32'hc1d04330)) begin
            $display("FAIL packet_isolation: first packet crc=%08x", output_crc);
            failure_count = failure_count + 1;
        end
        @(negedge clk);
        send_beat(8'h62, 1'b1, 1'b1, 1'b0, 0);
        expect_result(32'hd280b0c4, "packet_isolation");

        send_123456789(2);
        expect_result(32'he3069283, "input_stalls");

        output_ready = 1'b0;
        send_beat(8'h61, 1'b1, 1'b1, 1'b0, 0);
        held_crc = output_crc;
        for (stall_index = 0; stall_index < 3; stall_index = stall_index + 1) begin
            @(negedge clk);
            if ((output_valid !== 1'b1) || (output_crc !== held_crc) || (input_ready !== 1'b0)) begin
                $display("FAIL output_stalls: result did not remain stable");
                failure_count = failure_count + 1;
            end
        end
        output_ready = 1'b1;
        @(negedge clk);

        send_beat(8'h78, 1'b1, 1'b0, 1'b0, 0);
        send_beat(8'h79, 1'b0, 1'b0, 1'b0, 0);
        apply_reset();
        send_123456789(0);
        expect_result(32'he3069283, "backpressure_reset");

        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "crc32c_stream: %0d checks failed", failure_count);
        end
        if (case_count != 5) begin
            $fatal(1, "crc32c_stream: unexpected case count %0d", case_count);
        end
        $display("crc32c_stream: 5 cases passed");
        $finish;
    end
endmodule
