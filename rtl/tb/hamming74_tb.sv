module hamming74_tb;
    reg [3:0]  input_data;
    wire [6:0] encoded_codeword;
    reg [6:0]  received;
    wire [3:0] decoded;
    wire [2:0] syndrome;
    wire       corrected;

    integer vector_file;
    integer result_file;
    integer case_count;
    integer fields_read;
    integer expected_corrected;
    integer failure_count;
    integer case_index;
    reg [3:0] expected_decoded;
    reg [6:0] expected_encoded;
    reg [2:0] expected_syndrome;
    reg [8*128-1:0] case_id;
    reg [8*260-1:0] vector_path;
    reg [8*260-1:0] result_path;

    hamming74_encoder encoder (
        .data(input_data),
        .codeword(encoded_codeword)
    );

    hamming74_decoder decoder (
        .codeword(received),
        .data(decoded),
        .syndrome(syndrome),
        .corrected(corrected)
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
            $fatal(1, "failed to open Hamming vector or result file");
        end

        failure_count = 0;
        fields_read = $fscanf(vector_file, "%d\n", case_count);
        if (fields_read != 1) begin
            $fatal(1, "failed to read Hamming case count");
        end

        for (case_index = 0; case_index < case_count; case_index = case_index + 1) begin
            fields_read = $fscanf(
                vector_file,
                "%s %h %h %h %h %h %d\n",
                case_id,
                input_data,
                expected_encoded,
                received,
                expected_decoded,
                expected_syndrome,
                expected_corrected
            );
            if (fields_read != 7) begin
                $fatal(1, "failed to read Hamming case %0d", case_index);
            end
            #1;

            if (
                (encoded_codeword !== expected_encoded) ||
                (decoded !== expected_decoded) ||
                (syndrome !== expected_syndrome) ||
                (corrected !== expected_corrected[0])
            ) begin
                $display("FAIL %0s", case_id);
                failure_count = failure_count + 1;
            end

            if (corrected) begin
                $fwrite(
                    result_file,
                    "{\"case_id\":\"%0s\",\"implementation\":\"rtl\",\"output_hex\":\"%02x\",\"output_bit_length\":4,\"status\":[\"FEC_CORRECTED\"],\"schema_version\":0}\n",
                    case_id,
                    decoded
                );
            end
            else begin
                $fwrite(
                    result_file,
                    "{\"case_id\":\"%0s\",\"implementation\":\"rtl\",\"output_hex\":\"%02x\",\"output_bit_length\":4,\"status\":[],\"schema_version\":0}\n",
                    case_id,
                    decoded
                );
            end
        end

        received = 7'bxxxxxxx;
        #1;
        if ((decoded !== 4'bxxxx) || (syndrome !== 3'bxxx)) begin
            $fatal(1, "Hamming decoder treated unknown input as valid data");
        end

        $fclose(vector_file);
        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "hamming74: %0d cases failed", failure_count);
        end
        $display("hamming74: %0d cases passed", case_count);
        $finish;
    end
endmodule
