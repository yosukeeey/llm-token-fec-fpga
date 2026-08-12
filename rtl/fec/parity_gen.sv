module parity_gen #(
    parameter integer DATA_WIDTH = 8
) (
    input  wire [DATA_WIDTH-1:0] data,
    output wire [0:0]            parity
);
    assign parity = ^data;
endmodule
