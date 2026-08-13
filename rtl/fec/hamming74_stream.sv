/** @note One registered stage permits one transfer per cycle without stalls. */
module hamming74_stream (
    input  wire [0:0] clk,
    input  wire [0:0] reset,
    input  wire [0:0] in_valid,
    output wire [0:0] in_ready,
    input  wire [3:0] in_data,
    input  wire [0:0] in_last,
    output wire [0:0] out_valid,
    input  wire [0:0] out_ready,
    output wire [6:0] out_data,
    output wire [0:0] out_last
);
    wire [6:0] encoded_input;
    reg  [6:0] out_data_reg;
    reg        out_last_reg;
    reg        out_valid_reg;

    hamming74_encoder encoder (
        .data(in_data),
        .codeword(encoded_input)
    );

    // The output register is replaceable only when empty or consumed, which
    // keeps payload and packet boundary stable for the full backpressure stall.
    assign in_ready = !reset && (!out_valid_reg || out_ready);
    assign out_valid = out_valid_reg;
    assign out_data = out_data_reg;
    assign out_last = out_last_reg;

    always @(posedge clk) begin
        if (reset) begin
            out_valid_reg <= 1'b0;
            out_data_reg <= 7'b0000000;
            out_last_reg <= 1'b0;
        end
        else if (in_ready) begin
            out_valid_reg <= in_valid;
            if (in_valid) begin
                out_data_reg <= encoded_input;
                out_last_reg <= in_last;
            end
        end
    end
endmodule

/** @note Data, syndrome, corrected, and last share one registered transfer. */
module hamming74_decoder_stream (
    input  wire [0:0] clk,
    input  wire [0:0] reset,
    input  wire [0:0] in_valid,
    output wire [0:0] in_ready,
    input  wire [6:0] in_data,
    input  wire [0:0] in_last,
    output wire [0:0] out_valid,
    input  wire [0:0] out_ready,
    output wire [3:0] out_data,
    output wire [2:0] out_syndrome,
    output wire [0:0] out_corrected,
    output wire [0:0] out_last
);
    wire [3:0] decoded_input;
    wire [2:0] syndrome_input;
    wire [0:0] corrected_input;
    reg  [3:0] out_data_reg;
    reg  [2:0] out_syndrome_reg;
    reg        out_corrected_reg;
    reg        out_last_reg;
    reg        out_valid_reg;

    hamming74_decoder decoder (
        .codeword(in_data),
        .data(decoded_input),
        .syndrome(syndrome_input),
        .corrected(corrected_input)
    );

    // Syndrome and correction status describe the buffered data transfer and
    // therefore cannot be recomputed from a changing input during a stall.
    assign in_ready = !reset && (!out_valid_reg || out_ready);
    assign out_valid = out_valid_reg;
    assign out_data = out_data_reg;
    assign out_syndrome = out_syndrome_reg;
    assign out_corrected = out_corrected_reg;
    assign out_last = out_last_reg;

    always @(posedge clk) begin
        if (reset) begin
            out_valid_reg <= 1'b0;
            out_data_reg <= 4'b0000;
            out_syndrome_reg <= 3'b000;
            out_corrected_reg <= 1'b0;
            out_last_reg <= 1'b0;
        end
        else if (in_ready) begin
            out_valid_reg <= in_valid;
            if (in_valid) begin
                out_data_reg <= decoded_input;
                out_syndrome_reg <= syndrome_input;
                out_corrected_reg <= corrected_input[0];
                out_last_reg <= in_last;
            end
        end
    end
endmodule
