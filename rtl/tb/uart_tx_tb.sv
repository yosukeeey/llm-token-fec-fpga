module uart_tx_tb;
    localparam integer CLOCK_HZ = 100_000_000;
    localparam integer BAUD_RATE = 115_200;
    localparam integer CLKS_PER_BIT = (CLOCK_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam integer EFFECTIVE_BAUD = CLOCK_HZ / CLKS_PER_BIT;
    localparam integer ERROR_PPM =
        ((EFFECTIVE_BAUD - BAUD_RATE) * 1_000_000) / BAUD_RATE;

    reg [0:0]  clk;
    reg [0:0]  reset;
    reg [0:0]  input_valid;
    wire [0:0] input_ready;
    reg [7:0]  input_data;
    wire [0:0] tx;

    integer result_file;
    integer failure_count;
    integer case_count;
    integer bit_index;
    integer clock_index;
    integer stall_count;
    reg [0:0] expected_bit;
    reg [8*260-1:0] result_path;

    uart_tx dut (
        .clk(clk),
        .reset(reset),
        .input_valid(input_valid),
        .input_ready(input_ready),
        .input_data(input_data),
        .tx(tx)
    );

    always #5 clk = ~clk;

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

    function [0:0] uart_bit;
        input [7:0] value;
        input integer position;
        begin
            if (position == 0) begin
                uart_bit = 1'b0;
            end
            else if (position == 9) begin
                uart_bit = 1'b1;
            end
            else begin
                uart_bit = value[position - 1];
            end
        end
    endfunction

    task apply_reset;
        begin
            @(negedge clk);
            input_valid = 1'b0;
            reset = 1'b1;
            repeat (3) begin
                @(posedge clk);
                #1;
                if ((tx !== 1'b1) || (input_ready !== 1'b0)) begin
                    $display("FAIL UART TX reset levels");
                    failure_count = failure_count + 1;
                end
            end
            @(negedge clk);
            reset = 1'b0;
            #1;
            if ((tx !== 1'b1) || (input_ready !== 1'b1)) begin
                $display("FAIL UART TX idle levels");
                failure_count = failure_count + 1;
            end
        end
    endtask

    task begin_byte;
        input [7:0] value;
        begin
            @(negedge clk);
            input_data = value;
            input_valid = 1'b1;
            @(posedge clk);
            #1;
            if ((input_ready !== 1'b0) || (tx !== 1'b0)) begin
                $display("FAIL UART TX did not accept byte %02x", value);
                failure_count = failure_count + 1;
            end
            @(negedge clk);
            input_valid = 1'b0;
        end
    endtask

    task check_byte;
        input [7:0] value;
        begin
            for (bit_index = 0; bit_index < 10; bit_index = bit_index + 1) begin
                expected_bit = uart_bit(value, bit_index);
                for (clock_index = 0; clock_index < CLKS_PER_BIT;
                     clock_index = clock_index + 1) begin
                    if (tx !== expected_bit) begin
                        $display(
                            "FAIL UART byte=%02x bit=%0d cycle=%0d actual=%b expected=%b",
                            value,
                            bit_index,
                            clock_index,
                            tx,
                            expected_bit
                        );
                        failure_count = failure_count + 1;
                    end
                    if ((clock_index == (CLKS_PER_BIT / 2)) &&
                        (tx !== expected_bit)) begin
                        $display("FAIL UART bit-center sample");
                        failure_count = failure_count + 1;
                    end
                    if (clock_index + 1 < CLKS_PER_BIT) begin
                        @(negedge clk);
                    end
                end
                @(negedge clk);
            end
            if ((tx !== 1'b1) || (input_ready !== 1'b1)) begin
                $display("FAIL UART TX did not return idle after %02x", value);
                failure_count = failure_count + 1;
            end
        end
    endtask

    task check_standalone_byte;
        input [7:0] value;
        input [8*64-1:0] case_id;
        begin
            begin_byte(value);
            check_byte(value);
            record_case(case_id);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        input_valid = 1'b0;
        input_data = 8'h00;
        failure_count = 0;
        case_count = 0;
        stall_count = 0;

        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end
        result_file = $fopen(result_path, "w");
        if (result_file == 0) begin
            $fatal(1, "failed to open UART TX result file");
        end

        $display(
            "uart_tx: divisor=%0d effective_baud=%0d error_ppm=%0d",
            CLKS_PER_BIT,
            EFFECTIVE_BAUD,
            ERROR_PPM
        );
        if ((CLKS_PER_BIT != 868) || (EFFECTIVE_BAUD != 115207) ||
            (ERROR_PPM != 60)) begin
            $display("FAIL UART default timing calculation");
            failure_count = failure_count + 1;
        end

        apply_reset();
        record_case("reset_idle_high");
        check_standalone_byte(8'h00, "byte_00");
        check_standalone_byte(8'hff, "byte_ff");
        check_standalone_byte(8'h55, "byte_55");
        check_standalone_byte(8'haa, "byte_aa");

        begin_byte(8'h3c);
        input_data = 8'ha5;
        input_valid = 1'b1;
        for (bit_index = 0; bit_index < 10; bit_index = bit_index + 1) begin
            expected_bit = uart_bit(8'h3c, bit_index);
            for (clock_index = 0; clock_index < CLKS_PER_BIT;
                 clock_index = clock_index + 1) begin
                if (tx !== expected_bit) begin
                    $display("FAIL continuous first byte timing");
                    failure_count = failure_count + 1;
                end
                if (!input_ready) begin
                    stall_count = stall_count + 1;
                end
                if (clock_index + 1 < CLKS_PER_BIT) begin
                    @(negedge clk);
                end
            end
            @(negedge clk);
        end
        if ((input_ready !== 1'b0) || (tx !== 1'b0)) begin
            $display("FAIL continuous byte inserted an idle bit gap");
            failure_count = failure_count + 1;
        end
        input_valid = 1'b0;
        check_byte(8'ha5);
        if (stall_count == 0) begin
            $display("FAIL input backpressure was not exercised");
            failure_count = failure_count + 1;
        end
        record_case("continuous_backpressure");

        begin_byte(8'h01);
        check_byte(8'h01);
        record_case("bit_width_center");

        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "uart_tx: %0d checks failed", failure_count);
        end
        if (case_count != 7) begin
            $fatal(1, "uart_tx: unexpected case count %0d", case_count);
        end
        $display("uart_tx: 7 cases passed");
        $finish;
    end
endmodule
