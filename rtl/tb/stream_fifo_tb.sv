module stream_fifo_tb #(
    parameter integer DEPTH = 3
);
    localparam integer DATA_WIDTH = 8;

    reg                  clk;
    reg                  reset;
    reg                  input_valid;
    wire                 input_ready;
    reg [DATA_WIDTH-1:0] input_data;
    wire                 output_valid;
    reg                  output_ready;
    wire [DATA_WIDTH-1:0] output_data;
    wire                 overflow_attempt;
    wire                 underflow_attempt;

    reg [DATA_WIDTH-1:0] model_storage [0:255];
    integer model_write_pointer;
    integer model_read_pointer;
    integer model_count;
    integer failure_count;
    integer case_count;
    integer accepted_push_count;
    integer accepted_pop_count;
    integer random_index;
    integer stall_index;
    integer push_count_before;
    integer pop_count_before;
    integer result_file;
    reg last_push_accepted;
    reg last_pop_accepted;
    reg producer_pending;
    reg [7:0] producer_data;
    reg [7:0] next_producer_data;
    reg [7:0] source_lfsr;
    reg [7:0] sink_lfsr;
    reg [7:0] stalled_output;
    reg [8*260-1:0] result_path;

    stream_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .reset(reset),
        .input_valid(input_valid),
        .input_ready(input_ready),
        .input_data(input_data),
        .output_valid(output_valid),
        .output_ready(output_ready),
        .output_data(output_data),
        .overflow_attempt(overflow_attempt),
        .underflow_attempt(underflow_attempt)
    );

    stream_assertions #(
        .DATA_WIDTH(DATA_WIDTH),
        .SIDEBAND_WIDTH(1)
    ) output_invariants (
        .clk(clk),
        .reset(reset),
        .valid(output_valid),
        .ready(output_ready),
        .data(output_data),
        .sideband(1'b0)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        last_push_accepted = 1'b0;
        last_pop_accepted = 1'b0;

        if (reset) begin
            model_write_pointer = 0;
            model_read_pointer = 0;
            model_count = 0;
            if (
                (input_ready !== 1'b0) ||
                (output_valid !== 1'b0) ||
                (output_data !== {DATA_WIDTH{1'b0}}) ||
                (overflow_attempt !== 1'b0) ||
                (underflow_attempt !== 1'b0)
            ) begin
                $display("FAIL reset did not suppress the stream interface");
                failure_count = failure_count + 1;
            end
        end
        else begin
            if (output_valid !== (model_count != 0)) begin
                $display("FAIL output_valid count=%0d valid=%b", model_count, output_valid);
                failure_count = failure_count + 1;
            end
            if ((model_count != 0) && (output_data !== model_storage[model_read_pointer])) begin
                $display(
                    "FAIL reordered data=%02x expected=%02x count=%0d",
                    output_data,
                    model_storage[model_read_pointer],
                    model_count
                );
                failure_count = failure_count + 1;
            end
            if ((model_count == 0) && (output_data !== {DATA_WIDTH{1'b0}})) begin
                $display("FAIL stale output=%02x", output_data);
                failure_count = failure_count + 1;
            end
            if (input_ready !== (
                (model_count < DEPTH) || ((model_count != 0) && output_ready)
            )) begin
                $display("FAIL input_ready count=%0d ready=%b", model_count, input_ready);
                failure_count = failure_count + 1;
            end
            if (overflow_attempt !== (input_valid && !input_ready)) begin
                $display("FAIL overflow_attempt mismatch");
                failure_count = failure_count + 1;
            end
            if (underflow_attempt !== (output_ready && !output_valid)) begin
                $display("FAIL underflow_attempt mismatch");
                failure_count = failure_count + 1;
            end

            last_push_accepted = input_valid && input_ready;
            last_pop_accepted = output_valid && output_ready;

            if (last_pop_accepted) begin
                model_read_pointer = model_read_pointer + 1;
                model_count = model_count - 1;
                accepted_pop_count = accepted_pop_count + 1;
            end
            if (last_push_accepted) begin
                model_storage[model_write_pointer] = input_data;
                model_write_pointer = model_write_pointer + 1;
                model_count = model_count + 1;
                accepted_push_count = accepted_push_count + 1;
            end
        end
    end

    task apply_reset;
        begin
            @(negedge clk);
            input_valid = 1'b0;
            output_ready = 1'b0;
            reset = 1'b1;
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task run_cycle;
        input drive_valid;
        input [DATA_WIDTH-1:0] drive_data;
        input drive_ready;
        begin
            input_valid = drive_valid;
            input_data = drive_data;
            output_ready = drive_ready;
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task drain_fifo;
        begin
            while (model_count != 0) begin
                run_cycle(1'b0, 8'h00, 1'b1);
            end
            run_cycle(1'b0, 8'h00, 1'b0);
        end
    endtask

    task record_case;
        input [8*64-1:0] case_id;
        begin
            $fwrite(
                result_file,
                "{\"case_id\":\"%0s\",\"implementation\":\"rtl\",\"output_hex\":\"01\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n",
                case_id
            );
            case_count = case_count + 1;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        input_valid = 1'b0;
        input_data = 8'h00;
        output_ready = 1'b0;
        failure_count = 0;
        case_count = 0;
        accepted_push_count = 0;
        accepted_pop_count = 0;
        model_write_pointer = 0;
        model_read_pointer = 0;
        model_count = 0;

        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end
        result_file = $fopen(result_path, "w");
        if (result_file == 0) begin
            $fatal(1, "failed to open FIFO result file");
        end

        apply_reset();
        run_cycle(1'b0, 8'h00, 1'b1);
        for (random_index = 0; random_index < DEPTH; random_index = random_index + 1) begin
            run_cycle(1'b1, 8'h10 + random_index, 1'b0);
        end
        run_cycle(1'b1, 8'hff, 1'b0);
        drain_fifo();
        record_case("empty_full");

        apply_reset();
        for (random_index = 0; random_index < DEPTH; random_index = random_index + 1) begin
            run_cycle(1'b1, 8'h20 + random_index, 1'b0);
        end
        for (random_index = 0; random_index < DEPTH - 1; random_index = random_index + 1) begin
            run_cycle(1'b0, 8'h00, 1'b1);
        end
        for (random_index = 0; random_index < DEPTH - 1; random_index = random_index + 1) begin
            run_cycle(1'b1, 8'h40 + random_index, 1'b0);
        end
        drain_fifo();
        record_case("wraparound");

        apply_reset();
        for (random_index = 0; random_index < DEPTH; random_index = random_index + 1) begin
            run_cycle(1'b1, 8'h60 + random_index, 1'b0);
        end
        push_count_before = accepted_push_count;
        pop_count_before = accepted_pop_count;
        run_cycle(1'b1, 8'h70, 1'b1);
        if (
            (accepted_push_count != push_count_before + 1) ||
            (accepted_pop_count != pop_count_before + 1) ||
            (model_count != DEPTH)
        ) begin
            $display("FAIL simultaneous full push/pop was not accepted");
            failure_count = failure_count + 1;
        end
        drain_fifo();
        record_case("simultaneous_push_pop");

        apply_reset();
        producer_pending = 1'b0;
        producer_data = 8'h00;
        next_producer_data = 8'h40;
        source_lfsr = 8'h5a;
        sink_lfsr = 8'hc3;
        push_count_before = accepted_push_count;
        for (random_index = 0; random_index < 96; random_index = random_index + 1) begin
            if (!producer_pending && source_lfsr[0]) begin
                producer_pending = 1'b1;
                producer_data = next_producer_data;
                next_producer_data = next_producer_data + 1'b1;
            end
            run_cycle(producer_pending, producer_data, sink_lfsr[0]);
            if (last_push_accepted) begin
                producer_pending = 1'b0;
            end
            source_lfsr = {
                source_lfsr[6:0],
                source_lfsr[7] ^ source_lfsr[5] ^ source_lfsr[4] ^ source_lfsr[3]
            };
            sink_lfsr = {
                sink_lfsr[6:0],
                sink_lfsr[7] ^ sink_lfsr[5] ^ sink_lfsr[1] ^ sink_lfsr[0]
            };
        end
        while (producer_pending) begin
            run_cycle(1'b1, producer_data, 1'b1);
            if (last_push_accepted) begin
                producer_pending = 1'b0;
            end
        end
        drain_fifo();
        if (
            (accepted_push_count == push_count_before) ||
            (accepted_push_count != accepted_pop_count)
        ) begin
            $display("FAIL randomized traffic did not drain without loss");
            failure_count = failure_count + 1;
        end
        record_case("random_backpressure");

        apply_reset();
        run_cycle(1'b1, 8'h50, 1'b0);
        run_cycle(1'b1, 8'h51, 1'b0);
        stalled_output = output_data;
        for (stall_index = 0; stall_index < 3; stall_index = stall_index + 1) begin
            run_cycle(1'b0, 8'h00, 1'b0);
            if ((output_valid !== 1'b1) || (output_data !== stalled_output)) begin
                $display("FAIL stalled output changed");
                failure_count = failure_count + 1;
            end
        end
        apply_reset();
        if ((output_valid !== 1'b0) || (output_data !== 8'h00)) begin
            $display("FAIL reset exposed pre-reset data");
            failure_count = failure_count + 1;
        end
        run_cycle(1'b1, 8'h52, 1'b0);
        drain_fifo();
        record_case("reset_recovery");

        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "stream_fifo: %0d checks failed", failure_count);
        end
        if (case_count != 5) begin
            $fatal(1, "stream_fifo: unexpected case count %0d", case_count);
        end
        $display("stream_fifo: 5 cases passed");
        $finish;
    end
endmodule
