module parity_check #(
    parameter integer DATA_WIDTH = 8
) (
    input  wire [DATA_WIDTH-1:0] data,
    input  wire [0:0]            parity,
    output wire [0:0]            error
);
    assign error = ^{data, parity};
endmodule
