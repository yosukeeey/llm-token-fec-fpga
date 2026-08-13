module uart_frame_pipeline_tb;
    localparam integer CLOCK_HZ = 1600000;
    localparam integer BAUD_RATE = 100000;
    localparam integer CLOCKS_PER_BIT = 16;
    localparam integer MAX_FRAME_BYTES = 1036;
    localparam integer CASE_COUNT = 5;

    reg [0:0] clk;
    reg [0:0] reset_async;
    reg [0:0] uart_rx_pin;
    wire [0:0] uart_tx_pin;
    wire [31:0] crc_error_count;
    wire [31:0] length_error_count;
    wire [31:0] version_error_count;
    wire [31:0] timeout_error_count;
    wire [31:0] handler_error_count;
    wire [31:0] uart_framing_error_count;
    wire [31:0] internal_overflow_count;

    reg [(8*MAX_FRAME_BYTES)-1:0] ping_request;
    reg [(8*MAX_FRAME_BYTES)-1:0] ping_response;
    reg [(8*MAX_FRAME_BYTES)-1:0] token_request;
    reg [(8*MAX_FRAME_BYTES)-1:0] token_response;
    reg [(8*MAX_FRAME_BYTES)-1:0] combined_request;
    reg [(8*MAX_FRAME_BYTES)-1:0] combined_response;
    reg [(8*MAX_FRAME_BYTES)-1:0] received_response;
    reg [(8*MAX_FRAME_BYTES)-1:0] scanned_request;
    reg [(8*MAX_FRAME_BYTES)-1:0] scanned_response;
    reg [8*128-1:0] vector_case_id;
    reg [8*260-1:0] vector_path;
    reg [8*260-1:0] result_path;

    integer ping_request_length;
    integer ping_response_length;
    integer token_request_length;
    integer token_response_length;
    integer combined_request_length;
    integer combined_response_length;
    integer vector_file;
    integer result_file;
    integer vector_count;
    integer fields_read;
    integer scanned_request_length;
    integer scanned_response_length;
    integer failure_count;
    integer result_count;
    integer byte_index;
    integer case_index;
    integer framing_count_before;

    uart_frame_pipeline #(
        .CLOCK_HZ(CLOCK_HZ),
        .BAUD_RATE(BAUD_RATE),
        .RX_FIFO_DEPTH(2048),
        .TX_FIFO_DEPTH(2048),
        .FRAME_IDLE_TIMEOUT_CYCLES(0),
        .INJECT_ERROR_BIT(0)
    ) dut (
        .clk(clk),
        .reset_async(reset_async),
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin),
        .crc_error_count(crc_error_count),
        .length_error_count(length_error_count),
        .version_error_count(version_error_count),
        .timeout_error_count(timeout_error_count),
        .handler_error_count(handler_error_count),
        .uart_framing_error_count(uart_framing_error_count),
        .internal_overflow_count(internal_overflow_count)
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
            result_count = result_count + 1;
        end
    endtask

    task drive_level;
        input [0:0] level;
        input integer cycles;
        integer cycle_index;
        begin
            uart_rx_pin = level;
            for (cycle_index = 0; cycle_index < cycles; cycle_index = cycle_index + 1) begin
                @(negedge clk);
            end
        end
    endtask

    task send_uart_byte;
        input [7:0] value;
        input [0:0] stop_level;
        integer bit_position;
        begin
            drive_level(1'b0, CLOCKS_PER_BIT);
            for (bit_position = 0; bit_position < 8; bit_position = bit_position + 1) begin
                drive_level(value[bit_position], CLOCKS_PER_BIT);
            end
            drive_level(stop_level, CLOCKS_PER_BIT);
        end
    endtask

    task send_stream;
        input integer stream_length;
        input [(8*MAX_FRAME_BYTES)-1:0] stream_data;
        begin
            for (byte_index = 0; byte_index < stream_length; byte_index = byte_index + 1) begin
                send_uart_byte(stream_data[(byte_index * 8) +: 8], 1'b1);
            end
        end
    endtask

    task receive_uart_byte;
        output [7:0] value;
        integer bit_position;
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while ((uart_tx_pin !== 1'b0) && (wait_cycles < 200000)) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (uart_tx_pin !== 1'b0) begin
                $fatal(1, "UART response start bit timed out");
            end
            repeat (CLOCKS_PER_BIT + (CLOCKS_PER_BIT / 2)) @(negedge clk);
            for (bit_position = 0; bit_position < 8; bit_position = bit_position + 1) begin
                value[bit_position] = uart_tx_pin;
                repeat (CLOCKS_PER_BIT) @(negedge clk);
            end
            if (uart_tx_pin !== 1'b1) begin
                $display("FAIL UART response stop bit");
                failure_count = failure_count + 1;
            end
            repeat (CLOCKS_PER_BIT / 2) @(negedge clk);
        end
    endtask

    task receive_and_compare;
        input integer stream_length;
        input [(8*MAX_FRAME_BYTES)-1:0] expected_stream;
        reg [7:0] received_byte;
        integer receive_index;
        begin
            received_response = {(8*MAX_FRAME_BYTES){1'b0}};
            for (receive_index = 0; receive_index < stream_length;
                 receive_index = receive_index + 1) begin
                receive_uart_byte(received_byte);
                received_response[(receive_index * 8) +: 8] = received_byte;
                if (received_byte !== expected_stream[(receive_index * 8) +: 8]) begin
                    $display(
                        "FAIL UART response byte=%0d actual=%02x expected=%02x",
                        receive_index,
                        received_byte,
                        expected_stream[(receive_index * 8) +: 8]
                    );
                    failure_count = failure_count + 1;
                end
            end
        end
    endtask

    task apply_reset;
        begin
            uart_rx_pin = 1'b1;
            #3 reset_async = 1'b1;
            repeat (3) @(negedge clk);
            #2 reset_async = 1'b0;
            repeat (4) @(negedge clk);
        end
    endtask

    task assert_clean_counters;
        begin
            if (
                (crc_error_count != 0) ||
                (length_error_count != 0) ||
                (version_error_count != 0) ||
                (timeout_error_count != 0) ||
                (handler_error_count != 0) ||
                (internal_overflow_count != 0)
            ) begin
                $display("FAIL UART pipeline error counter changed");
                failure_count = failure_count + 1;
            end
        end
    endtask

    task append_stream;
        inout [(8*MAX_FRAME_BYTES)-1:0] destination;
        input integer destination_offset;
        input [(8*MAX_FRAME_BYTES)-1:0] source;
        input integer source_length;
        integer copy_index;
        begin
            for (copy_index = 0; copy_index < source_length;
                 copy_index = copy_index + 1) begin
                destination[((destination_offset + copy_index) * 8) +: 8] =
                    source[(copy_index * 8) +: 8];
            end
        end
    endtask

    initial begin
        repeat (1000000) @(posedge clk);
        $fatal(1, "UART Frame pipeline testbench watchdog expired");
    end

    initial begin
        clk = 1'b0;
        reset_async = 1'b0;
        uart_rx_pin = 1'b1;
        failure_count = 0;
        result_count = 0;
        ping_request_length = 0;
        ping_response_length = 0;
        token_request_length = 0;
        token_response_length = 0;

        if (!$value$plusargs("VECTOR_FILE=%s", vector_path)) begin
            $fatal(1, "VECTOR_FILE plusarg is required");
        end
        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end
        vector_file = $fopen(vector_path, "r");
        result_file = $fopen(result_path, "w");
        if ((vector_file == 0) || (result_file == 0)) begin
            $fatal(1, "failed to open UART Frame vector or result file");
        end
        fields_read = $fscanf(vector_file, "%d\n", vector_count);
        if ((fields_read != 1) || (vector_count != 2)) begin
            $fatal(1, "UART Frame vector file must contain two cases");
        end
        for (case_index = 0; case_index < vector_count; case_index = case_index + 1) begin
            fields_read = $fscanf(
                vector_file,
                "%s %d %h %d %h\n",
                vector_case_id,
                scanned_request_length,
                scanned_request,
                scanned_response_length,
                scanned_response
            );
            if (fields_read != 5) begin
                $fatal(1, "failed to read UART Frame vector %0d", case_index);
            end
            if (case_index == 0) begin
                ping_request_length = scanned_request_length;
                ping_request = scanned_request;
                ping_response_length = scanned_response_length;
                ping_response = scanned_response;
                if ((ping_request_length == 0) || (ping_response_length == 0)) begin
                    $fatal(1, "invalid PING pipeline vector");
                end
            end
            else begin
                token_request_length = scanned_request_length;
                token_request = scanned_request;
                token_response_length = scanned_response_length;
                token_response = scanned_response;
            end
        end
        $fclose(vector_file);

        combined_request = {(8*MAX_FRAME_BYTES){1'b0}};
        combined_request_length = ping_request_length + token_request_length;
        append_stream(combined_request, 0, ping_request, ping_request_length);
        append_stream(
            combined_request,
            ping_request_length,
            token_request,
            token_request_length
        );
        combined_response = {(8*MAX_FRAME_BYTES){1'b0}};
        combined_response_length = ping_response_length + token_response_length;
        append_stream(combined_response, 0, ping_response, ping_response_length);
        append_stream(
            combined_response,
            ping_response_length,
            token_response,
            token_response_length
        );

        apply_reset;

        fork
            send_stream(ping_request_length, ping_request);
            receive_and_compare(ping_response_length, ping_response);
        join
        assert_clean_counters;
        record_case("uart_frame_ping_pong");

        fork
            send_stream(token_request_length, token_request);
            receive_and_compare(token_response_length, token_response);
        join
        assert_clean_counters;
        record_case("uart_frame_token_result");

        fork
            send_stream(combined_request_length, combined_request);
            receive_and_compare(combined_response_length, combined_response);
        join
        assert_clean_counters;
        record_case("uart_frame_contiguous_order");

        framing_count_before = uart_framing_error_count;
        for (byte_index = 0; byte_index < 5; byte_index = byte_index + 1) begin
            send_uart_byte(token_request[(byte_index * 8) +: 8], 1'b1);
        end
        send_uart_byte(8'ha6, 1'b0);
        drive_level(1'b1, CLOCKS_PER_BIT);
        fork
            send_stream(ping_request_length, ping_request);
            receive_and_compare(ping_response_length, ping_response);
        join
        if (uart_framing_error_count != framing_count_before + 1) begin
            $display("FAIL UART framing error was not counted once");
            failure_count = failure_count + 1;
        end
        if (internal_overflow_count != 0) begin
            $display("FAIL UART framing recovery overflowed");
            failure_count = failure_count + 1;
        end
        record_case("uart_frame_framing_recovery");

        for (byte_index = 0; byte_index < 5; byte_index = byte_index + 1) begin
            send_uart_byte(token_request[(byte_index * 8) +: 8], 1'b1);
        end
        apply_reset;
        fork
            send_stream(ping_request_length, ping_request);
            receive_and_compare(ping_response_length, ping_response);
        join
        assert_clean_counters;
        record_case("uart_frame_reset_recovery");

        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "uart_frame_pipeline: %0d checks failed", failure_count);
        end
        if (result_count != CASE_COUNT) begin
            $fatal(1, "uart_frame_pipeline: unexpected case count %0d", result_count);
        end
        $display("uart_frame_pipeline: 5 cases passed");
        $finish;
    end
endmodule
