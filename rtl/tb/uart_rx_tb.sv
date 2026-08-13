module uart_rx_tb;
    localparam integer CLOCK_HZ = 3_686_400;
    localparam integer BAUD_RATE = 115_200;
    localparam integer CLOCKS_PER_BIT = 32;
    localparam integer DEFAULT_DIVISOR = 868;
    localparam integer DEFAULT_EFFECTIVE_BAUD = 100_000_000 / DEFAULT_DIVISOR;
    localparam [63:0] DEFAULT_ERROR_PPM =
        ((64'd100_000_000 - (64'd115_200 * DEFAULT_DIVISOR)) * 64'd1_000_000) /
        (64'd115_200 * DEFAULT_DIVISOR);

    reg [0:0] clk;
    reg [0:0] reset;
    reg [0:0] rx;
    wire [0:0] output_valid;
    reg [0:0] output_ready;
    wire [7:0] output_data;
    wire [0:0] framing_error;
    wire [0:0] overflow_error;

    integer result_file;
    integer result_count;
    integer failure_count;
    integer framing_error_count;
    integer overflow_error_count;
    integer case_index;
    reg [8*260-1:0] result_path;

    uart_rx #(
        .CLOCK_HZ(CLOCK_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .output_valid(output_valid),
        .output_ready(output_ready),
        .output_data(output_data),
        .framing_error(framing_error),
        .overflow_error(overflow_error)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (framing_error) begin
            framing_error_count = framing_error_count + 1;
        end
        if (overflow_error) begin
            overflow_error_count = overflow_error_count + 1;
        end
    end

    task apply_reset;
        begin
            @(negedge clk);
            reset = 1'b1;
            @(negedge clk);
            reset = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask

    task drive_level;
        input [0:0] level;
        input integer cycles;
        integer cycle_index;
        begin
            rx = level;
            for (cycle_index = 0; cycle_index < cycles; cycle_index = cycle_index + 1) begin
                @(negedge clk);
            end
        end
    endtask

    task send_uart_byte;
        input [7:0] value;
        input integer host_divisor;
        input integer stop_level;
        integer bit_index;
        begin
            drive_level(1'b0, host_divisor);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                drive_level(value[bit_index], host_divisor);
            end
            drive_level(stop_level[0], host_divisor);
        end
    endtask

    task expect_byte;
        input [7:0] expected;
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while ((output_valid !== 1'b1) && (wait_cycles < 400)) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if ((output_valid !== 1'b1) || (output_data !== expected)) begin
                $display(
                    "FAIL byte: actual=%02x valid=%b expected=%02x",
                    output_data,
                    output_valid,
                    expected
                );
                failure_count = failure_count + 1;
            end
            output_ready = 1'b1;
            @(negedge clk);
            output_ready = 1'b0;
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
            $fflush(result_file);
            result_count = result_count + 1;
        end
    endtask

    initial begin
        repeat (15000) @(posedge clk);
        $fatal(1, "uart_rx testbench watchdog expired");
    end

    initial begin
        clk = 1'b0;
        reset = 1'b0;
        rx = 1'b1;
        output_ready = 1'b0;
        result_count = 0;
        failure_count = 0;
        framing_error_count = 0;
        overflow_error_count = 0;

        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end
        result_file = $fopen(result_path, "w");
        if (result_file == 0) begin
            $fatal(1, "failed to open UART RX result file");
        end
        if (
            (DEFAULT_DIVISOR != 868) ||
            (DEFAULT_EFFECTIVE_BAUD != 115207) ||
            (DEFAULT_ERROR_PPM != 64)
        ) begin
            $fatal(1, "default UART divisor calculation changed");
        end
        $display(
            "uart_rx default divisor=%0d effective_baud=%0d error_ppm=%0d",
            DEFAULT_DIVISOR,
            DEFAULT_EFFECTIVE_BAUD,
            DEFAULT_ERROR_PPM
        );

        apply_reset();

        for (case_index = 0; case_index < 4; case_index = case_index + 1) begin
            case (case_index)
                0: send_uart_byte(8'h00, CLOCKS_PER_BIT, 1);
                1: send_uart_byte(8'hff, CLOCKS_PER_BIT, 1);
                2: send_uart_byte(8'h55, CLOCKS_PER_BIT, 1);
                default: send_uart_byte(8'haa, CLOCKS_PER_BIT, 1);
            endcase
            case (case_index)
                0: expect_byte(8'h00);
                1: expect_byte(8'hff);
                2: expect_byte(8'h55);
                default: expect_byte(8'haa);
            endcase
        end
        record_pass("byte_patterns");

        fork
            begin
                send_uart_byte(8'h12, CLOCKS_PER_BIT, 1);
                send_uart_byte(8'h34, CLOCKS_PER_BIT, 1);
            end
            begin
                expect_byte(8'h12);
                expect_byte(8'h34);
            end
        join
        record_pass("back_to_back");

        drive_level(1'b0, CLOCKS_PER_BIT / 4);
        drive_level(1'b1, CLOCKS_PER_BIT);
        if (output_valid !== 1'b0) begin
            $display("FAIL false start produced output");
            failure_count = failure_count + 1;
        end
        send_uart_byte(8'h5a, CLOCKS_PER_BIT, 1);
        expect_byte(8'h5a);
        record_pass("false_start");

        send_uart_byte(8'ha6, CLOCKS_PER_BIT, 0);
        drive_level(1'b1, CLOCKS_PER_BIT);
        if ((framing_error_count != 1) || (output_valid !== 1'b0)) begin
            $display("FAIL framing error handling");
            failure_count = failure_count + 1;
        end
        send_uart_byte(8'h6a, CLOCKS_PER_BIT, 1);
        expect_byte(8'h6a);
        record_pass("framing_recovery");

        drive_level(1'b1, 7);
        send_uart_byte(8'h3c, CLOCKS_PER_BIT, 1);
        expect_byte(8'h3c);
        record_pass("clock_phase");

        send_uart_byte(8'h81, 31, 1);
        expect_byte(8'h81);
        send_uart_byte(8'h42, 32, 1);
        expect_byte(8'h42);
        send_uart_byte(8'h24, 33, 1);
        expect_byte(8'h24);
        record_pass("host_divisors");

        send_uart_byte(8'hc3, CLOCKS_PER_BIT, 1);
        while (output_valid !== 1'b1) begin
            @(negedge clk);
        end
        repeat (5) @(negedge clk);
        if ((output_valid !== 1'b1) || (output_data !== 8'hc3)) begin
            $display("FAIL stalled output changed");
            failure_count = failure_count + 1;
        end
        send_uart_byte(8'h7e, CLOCKS_PER_BIT, 1);
        repeat (3) @(negedge clk);
        if (
            (overflow_error_count != 1) ||
            (output_valid !== 1'b1) ||
            (output_data !== 8'hc3)
        ) begin
            $display("FAIL overflow policy");
            failure_count = failure_count + 1;
        end
        output_ready = 1'b1;
        @(negedge clk);
        output_ready = 1'b0;
        record_pass("output_stall_overflow");

        drive_level(1'b0, CLOCKS_PER_BIT * 3);
        apply_reset();
        drive_level(1'b1, CLOCKS_PER_BIT);
        if (
            (output_valid !== 1'b0) ||
            (framing_error !== 1'b0) ||
            (overflow_error !== 1'b0)
        ) begin
            $display("FAIL reset state");
            failure_count = failure_count + 1;
        end
        send_uart_byte(8'h96, CLOCKS_PER_BIT, 1);
        expect_byte(8'h96);
        record_pass("reset_recovery");

        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "uart_rx: %0d checks failed", failure_count);
        end
        if (result_count != 8) begin
            $fatal(1, "uart_rx: unexpected result count %0d", result_count);
        end
        $display("uart_rx: 8 cases passed");
        $finish;
    end
endmodule
