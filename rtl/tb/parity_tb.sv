module parity_tb;
    reg [7:0] data;
    wire      parity;
    wire      parity_error;
    wire      inverted_parity_error;

    integer vector_file;
    integer result_file;
    integer case_count;
    integer fields_read;
    integer bit_length;
    integer expected_parity;
    integer failure_count;
    integer case_index;
    reg [8*128-1:0] case_id;
    reg [8*260-1:0] vector_path;
    reg [8*260-1:0] result_path;

    parity_gen #(.DATA_WIDTH(8)) generator (
        .data(data),
        .parity(parity)
    );

    parity_check #(.DATA_WIDTH(8)) parity_checker (
        .data(data),
        .parity(parity),
        .error(parity_error)
    );

    parity_check #(.DATA_WIDTH(8)) inverted_parity_checker (
        .data(data),
        .parity(~parity),
        .error(inverted_parity_error)
    );

    initial begin
        if (!$value$plusargs("VECTOR_FILE=%s", vector_path)) begin
            $fatal(1, "VECTOR_FILE plusarg is required");
        end
        if (!$value$plusargs("RESULT_FILE=%s", result_path)) begin
            $fatal(1, "RESULT_FILE plusarg is required");
        end

        vector_file = $fopen(vector_path, "r");
        result_file = $fopen(result_path, "w");
        if ((vector_file == 0) || (result_file == 0)) begin
            $fatal(1, "failed to open parity vector or result file");
        end

        failure_count = 0;
        fields_read = $fscanf(vector_file, "%d\n", case_count);
        if (fields_read != 1) begin
            $fatal(1, "failed to read parity case count");
        end

        for (case_index = 0; case_index < case_count; case_index = case_index + 1) begin
            fields_read = $fscanf(
                vector_file,
                "%s %d %h %h\n",
                case_id,
                bit_length,
                data,
                expected_parity
            );
            if (fields_read != 4) begin
                $fatal(1, "failed to read parity case %0d", case_index);
            end

            // Unused high bits are masked so the width-8 RTL also covers short vectors.
            if (bit_length == 0) begin
                data = 8'h00;
            end
            else if (bit_length < 8) begin
                data = data & ((1 << bit_length) - 1);
            end
            #1;

            if (
                (parity !== expected_parity[0]) ||
                (parity_error !== 1'b0) ||
                (inverted_parity_error !== 1'b1)
            ) begin
                $display("FAIL %0s", case_id);
                failure_count = failure_count + 1;
            end

            $fwrite(
                result_file,
                "{\"case_id\":\"%0s\",\"implementation\":\"rtl\",\"output_hex\":\"%02x\",\"output_bit_length\":1,\"status\":[],\"schema_version\":0}\n",
                case_id,
                parity
            );
        end

        data = 8'bxxxxxxxx;
        #1;
        if (parity !== 1'bx) begin
            $fatal(1, "parity did not propagate unknown input");
        end

        $fclose(vector_file);
        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "parity: %0d cases failed", failure_count);
        end
        $display("parity: %0d cases passed", case_count);
        $finish;
    end
endmodule
