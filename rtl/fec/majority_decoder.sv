/** @note A group disagreement cannot distinguish one-bit from two-bit corruption. */
module majority_decoder #(
    parameter integer DATA_WIDTH = 8,
    parameter integer REPETITION_COUNT = 3
) (
    input  wire [(DATA_WIDTH*REPETITION_COUNT)-1:0] encoded,
    output wire [DATA_WIDTH-1:0]                    data,
    output wire [DATA_WIDTH-1:0]                    group_disagreement
);
    genvar bit_index;
    generate
        if (REPETITION_COUNT == 1) begin : gen_r1
            assign data = encoded;
            assign group_disagreement = {DATA_WIDTH{1'b0}};
        end
        else begin : gen_r3
            for (bit_index = 0; bit_index < DATA_WIDTH; bit_index = bit_index + 1) begin : gen_bit
                assign data[bit_index] =
                    (encoded[(bit_index * 3)] & encoded[(bit_index * 3) + 1]) |
                    (encoded[(bit_index * 3)] & encoded[(bit_index * 3) + 2]) |
                    (encoded[(bit_index * 3) + 1] & encoded[(bit_index * 3) + 2]);
                assign group_disagreement[bit_index] =
                    (encoded[(bit_index * 3)] != encoded[(bit_index * 3) + 1]) |
                    (encoded[(bit_index * 3)] != encoded[(bit_index * 3) + 2]);
            end
        end
    endgenerate
endmodule
