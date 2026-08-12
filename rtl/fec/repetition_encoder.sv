/** @note The wire contract supports R=1/R=3 and puts adjacent copies LSB-first. */
module repetition_encoder #(
    parameter integer DATA_WIDTH = 8,
    parameter integer REPETITION_COUNT = 3
) (
    input  wire [DATA_WIDTH-1:0]                    data,
    output wire [(DATA_WIDTH*REPETITION_COUNT)-1:0] encoded
);
    genvar bit_index;
    genvar copy_index;
    generate
        for (bit_index = 0; bit_index < DATA_WIDTH; bit_index = bit_index + 1) begin : gen_bit
            for (
                copy_index = 0;
                copy_index < REPETITION_COUNT;
                copy_index = copy_index + 1
            ) begin : gen_copy
                assign encoded[(bit_index * REPETITION_COUNT) + copy_index] =
                    data[bit_index];
            end
        end
    endgenerate
endmodule
