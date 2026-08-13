module stream_assertions #(
    parameter integer DATA_WIDTH = 8,
    parameter integer SIDEBAND_WIDTH = 1
) (
    input wire [0:0]                  clk,
    input wire [0:0]                  reset,
    input wire [0:0]                  valid,
    input wire [0:0]                  ready,
    input wire [DATA_WIDTH-1:0]       data,
    input wire [SIDEBAND_WIDTH-1:0]   sideband
);
    reg                              stalled;
    reg [DATA_WIDTH-1:0]             stalled_data;
    reg [SIDEBAND_WIDTH-1:0]         stalled_sideband;

    always @(posedge clk) begin
        if (reset) begin
            stalled <= 1'b0;
        end
        else begin
            // A producer must retain the entire transfer until ready accepts it.
            if (stalled) begin
                if (valid !== 1'b1) begin
                    $fatal(1, "stream valid dropped during backpressure");
                end
                if (data !== stalled_data) begin
                    $fatal(1, "stream data changed during backpressure");
                end
                if (sideband !== stalled_sideband) begin
                    $fatal(1, "stream sideband changed during backpressure");
                end
            end

            stalled <= valid && !ready;
            if (valid && !ready) begin
                stalled_data <= data;
                stalled_sideband <= sideband;
            end
        end
    end
endmodule
