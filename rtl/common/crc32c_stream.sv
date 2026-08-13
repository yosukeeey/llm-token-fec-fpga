/**
 * @note One accepted byte per cycle; the result appears one cycle after last.
 * @note An empty packet is one accepted start/last beat with input_empty set.
 */
module crc32c_stream (
    input  wire [0:0]  clk,
    input  wire [0:0]  reset,
    input  wire [0:0]  input_valid,
    output wire [0:0]  input_ready,
    input  wire [7:0]  input_data,
    input  wire [0:0]  input_start,
    input  wire [0:0]  input_last,
    input  wire [0:0]  input_empty,
    output wire [0:0]  output_valid,
    input  wire [0:0]  output_ready,
    output wire [31:0] output_crc
);
    localparam [31:0] CRC_POLYNOMIAL = protocol_pkg::CRC32C_REFLECTED_POLYNOMIAL;
    localparam [31:0] CRC_INITIAL = protocol_pkg::CRC32C_INITIAL;
    localparam [31:0] CRC_XOR_OUT = protocol_pkg::CRC32C_XOR_OUT;

    reg [31:0] crc_state;
    reg [31:0] output_crc_reg;
    reg        output_valid_reg;

    wire        input_accepted;
    wire [31:0] packet_crc;
    wire [31:0] next_crc;

    function [31:0] crc32c_byte;
        input [31:0] crc;
        input [7:0] data;
        integer bit_index;
        reg [31:0] value;
        begin
            value = crc ^ {24'h000000, data};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (value[0]) begin
                    value = (value >> 1) ^ CRC_POLYNOMIAL;
                end
                else begin
                    value = value >> 1;
                end
            end
            crc32c_byte = value;
        end
    endfunction

    // The pending result owns the single output slot until it is accepted.
    assign input_ready = !reset && (~output_valid_reg | output_ready);
    assign input_accepted = input_valid & input_ready;
    assign packet_crc = input_start ? CRC_INITIAL : crc_state;
    assign next_crc = input_empty ? packet_crc : crc32c_byte(packet_crc, input_data);
    assign output_valid = output_valid_reg;
    assign output_crc = output_crc_reg;

    always @(posedge clk) begin
        if (reset) begin
            crc_state <= CRC_INITIAL;
            output_crc_reg <= 32'h00000000;
            output_valid_reg <= 1'b0;
        end
        else begin
            if (output_valid_reg && output_ready) begin
                output_valid_reg <= 1'b0;
            end

            // input_empty is valid only with input_start and input_last; its data is ignored.
            if (input_accepted) begin
                crc_state <= next_crc;
                if (input_last) begin
                    output_crc_reg <= next_crc ^ CRC_XOR_OUT;
                    output_valid_reg <= 1'b1;
                end
            end
        end
    end
endmodule
