/** @note One registered stage permits one transfer per cycle without stalls. */
module repetition_stream #(
    parameter integer DATA_WIDTH = 8,
    parameter integer REPETITION_COUNT = 3
) (
    input  wire [0:0]                                   clk,
    input  wire [0:0]                                   reset,
    input  wire [0:0]                                   in_valid,
    output wire [0:0]                                   in_ready,
    input  wire [DATA_WIDTH-1:0]                        in_data,
    input  wire [0:0]                                   in_last,
    output wire [0:0]                                   out_valid,
    input  wire [0:0]                                   out_ready,
    output wire [(DATA_WIDTH*REPETITION_COUNT)-1:0]     out_data,
    output wire [0:0]                                   out_last
);
    wire [(DATA_WIDTH*REPETITION_COUNT)-1:0] encoded_input;
    reg  [(DATA_WIDTH*REPETITION_COUNT)-1:0] out_data_reg;
    reg                                          out_last_reg;
    reg                                          out_valid_reg;

    repetition_encoder #(
        .DATA_WIDTH(DATA_WIDTH),
        .REPETITION_COUNT(REPETITION_COUNT)
    ) encoder (
        .data(in_data),
        .encoded(encoded_input)
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
            out_data_reg <= {(DATA_WIDTH*REPETITION_COUNT){1'b0}};
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

/** @note Data, disagreement status, and last share one registered transfer. */
module repetition_decoder_stream #(
    parameter integer DATA_WIDTH = 8,
    parameter integer REPETITION_COUNT = 3
) (
    input  wire [0:0]                                   clk,
    input  wire [0:0]                                   reset,
    input  wire [0:0]                                   in_valid,
    output wire [0:0]                                   in_ready,
    input  wire [(DATA_WIDTH*REPETITION_COUNT)-1:0]     in_data,
    input  wire [0:0]                                   in_last,
    output wire [0:0]                                   out_valid,
    input  wire [0:0]                                   out_ready,
    output wire [DATA_WIDTH-1:0]                        out_data,
    output wire [DATA_WIDTH-1:0]                        out_group_disagreement,
    output wire [0:0]                                   out_last
);
    wire [DATA_WIDTH-1:0] decoded_input;
    wire [DATA_WIDTH-1:0] disagreement_input;
    reg  [DATA_WIDTH-1:0] out_data_reg;
    reg  [DATA_WIDTH-1:0] out_disagreement_reg;
    reg                   out_last_reg;
    reg                   out_valid_reg;

    majority_decoder #(
        .DATA_WIDTH(DATA_WIDTH),
        .REPETITION_COUNT(REPETITION_COUNT)
    ) decoder (
        .encoded(in_data),
        .data(decoded_input),
        .group_disagreement(disagreement_input)
    );

    // Decode status belongs to the same transfer as data and must remain
    // unchanged with it until downstream accepts the entire result.
    assign in_ready = !reset && (!out_valid_reg || out_ready);
    assign out_valid = out_valid_reg;
    assign out_data = out_data_reg;
    assign out_group_disagreement = out_disagreement_reg;
    assign out_last = out_last_reg;

    always @(posedge clk) begin
        if (reset) begin
            out_valid_reg <= 1'b0;
            out_data_reg <= {DATA_WIDTH{1'b0}};
            out_disagreement_reg <= {DATA_WIDTH{1'b0}};
            out_last_reg <= 1'b0;
        end
        else if (in_ready) begin
            out_valid_reg <= in_valid;
            if (in_valid) begin
                out_data_reg <= decoded_input;
                out_disagreement_reg <= disagreement_input;
                out_last_reg <= in_last;
            end
        end
    end
endmodule
