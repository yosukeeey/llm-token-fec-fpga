/** @note Hamming(7,4) is SEC, not DED; corrected does not prove error weight. */
module hamming74_decoder (
    input  wire [6:0] codeword,
    output wire [3:0] data,
    output wire [2:0] syndrome,
    output wire [0:0] corrected
);
    wire [6:0] corrected_codeword;

    assign syndrome[0] = codeword[0] ^ codeword[2] ^ codeword[4] ^ codeword[6];
    assign syndrome[1] = codeword[1] ^ codeword[2] ^ codeword[5] ^ codeword[6];
    assign syndrome[2] = codeword[3] ^ codeword[4] ^ codeword[5] ^ codeword[6];
    assign corrected = |syndrome;

    assign corrected_codeword = corrected
        ? codeword ^ (7'b0000001 << (syndrome - 3'd1))
        : codeword;

    assign data = {
        corrected_codeword[6],
        corrected_codeword[5],
        corrected_codeword[4],
        corrected_codeword[2]
    };
endmodule
