/** @note The wire mapping from bit zero is p1,p2,d0,p4,d1,d2,d3. */
module hamming74_encoder (
    input  wire [3:0] data,
    output wire [6:0] codeword
);
    assign codeword[0] = data[0] ^ data[1] ^ data[3];
    assign codeword[1] = data[0] ^ data[2] ^ data[3];
    assign codeword[2] = data[0];
    assign codeword[3] = data[1] ^ data[2] ^ data[3];
    assign codeword[4] = data[1];
    assign codeword[5] = data[2];
    assign codeword[6] = data[3];
endmodule
