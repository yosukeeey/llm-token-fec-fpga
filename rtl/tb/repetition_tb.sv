module repetition_tb;
    reg [7:0]   input_data;
    wire [7:0]  encoded_r1;
    wire [23:0] encoded_r3;
    wire [7:0]  decoded_r1;
    wire [7:0]  decoded_r3;
    wire [7:0]  disagreement_r1;
    wire [7:0]  disagreement_r3;
    reg [7:0]   received_r1;
    reg [23:0]  received_r3;

    integer vector_file;
    integer result_file;
    integer case_count;
    integer fields_read;
    integer repetition_count;
    integer expected_corrected;
    integer actual_corrected;
    integer failure_count;
    integer case_index;
    reg [7:0] expected_decoded;
    reg [23:0] expected_encoded;
    reg [23:0] received;
    reg [8*128-1:0] case_id;
    reg [8*260-1:0] vector_path;
    reg [8*260-1:0] result_path;

    repetition_encoder #(.DATA_WIDTH(8), .REPETITION_COUNT(1)) encoder_r1 (
        .data(input_data),
        .encoded(encoded_r1)
    );

    repetition_encoder #(.DATA_WIDTH(8), .REPETITION_COUNT(3)) encoder_r3 (
        .data(input_data),
        .encoded(encoded_r3)
    );

    majority_decoder #(.DATA_WIDTH(8), .REPETITION_COUNT(1)) decoder_r1 (
        .encoded(received_r1),
        .data(decoded_r1),
        .group_disagreement(disagreement_r1)
    );

    majority_decoder #(.DATA_WIDTH(8), .REPETITION_COUNT(3)) decoder_r3 (
        .encoded(received_r3),
        .data(decoded_r3),
        .group_disagreement(disagreement_r3)
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
            $fatal(1, "failed to open repetition vector or result file");
        end

        failure_count = 0;
        received_r1 = '0;
        received_r3 = '0;
        fields_read = $fscanf(vector_file, "%d\n", case_count);
        if (fields_read != 1) begin
            $fatal(1, "failed to read repetition case count");
        end

        for (case_index = 0; case_index < case_count; case_index = case_index + 1) begin
            fields_read = $fscanf(
                vector_file,
                "%s %d %h %h %h %h %d\n",
                case_id,
                repetition_count,
                input_data,
                expected_encoded,
                received,
                expected_decoded,
                expected_corrected
            );
            if (fields_read != 7) begin
                $fatal(1, "failed to read repetition case %0d", case_index);
            end

            received_r1 = received[7:0];
            received_r3 = received;
            #1;

            if (repetition_count == 1) begin
                actual_corrected = |disagreement_r1;
                if (
                    (encoded_r1 !== expected_encoded[7:0]) ||
                    (decoded_r1 !== expected_decoded) ||
                    (actual_corrected != expected_corrected)
                ) begin
                    $display("FAIL %0s", case_id);
                    failure_count = failure_count + 1;
                end
                $fwrite(
                    result_file,
                    "{\"case_id\":\"%0s\",\"implementation\":\"rtl\",\"output_hex\":\"%02x\",\"output_bit_length\":8,\"status\":[],\"schema_version\":0}\n",
                    case_id,
                    decoded_r1
                );
            end
            else begin
                actual_corrected = |disagreement_r3;
                if (
                    (encoded_r3 !== expected_encoded) ||
                    (decoded_r3 !== expected_decoded) ||
                    (actual_corrected != expected_corrected)
                ) begin
                    $display(
                        "FAIL %0s encoded=%06x expected=%06x decoded=%02x expected=%02x corrected=%0d expected=%0d",
                        case_id,
                        encoded_r3,
                        expected_encoded,
                        decoded_r3,
                        expected_decoded,
                        actual_corrected,
                        expected_corrected
                    );
                    failure_count = failure_count + 1;
                end
                if (actual_corrected != 0) begin
                    $fwrite(
                        result_file,
                        "{\"case_id\":\"%0s\",\"implementation\":\"rtl\",\"output_hex\":\"%02x\",\"output_bit_length\":8,\"status\":[\"FEC_CORRECTED\"],\"schema_version\":0}\n",
                        case_id,
                        decoded_r3
                    );
                end
                else begin
                    $fwrite(
                        result_file,
                        "{\"case_id\":\"%0s\",\"implementation\":\"rtl\",\"output_hex\":\"%02x\",\"output_bit_length\":8,\"status\":[],\"schema_version\":0}\n",
                        case_id,
                        decoded_r3
                    );
                end
            end
        end

        received_r3 = 24'bxxxxxxxxxxxxxxxxxxxxxxxx;
        #1;
        if (decoded_r3 !== 8'bxxxxxxxx) begin
            $fatal(1, "repetition decoder treated unknown input as valid data");
        end

        $fclose(vector_file);
        $fclose(result_file);
        if (failure_count != 0) begin
            $fatal(1, "repetition: %0d cases failed", failure_count);
        end
        $display("repetition: %0d cases passed", case_count);
        $finish;
    end
endmodule
