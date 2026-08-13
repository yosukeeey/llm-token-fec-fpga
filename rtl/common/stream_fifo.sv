/**
 * @note DEPTH may be non-power-of-two but must be at least two.
 * @note Output appears after storage and supports one push plus one pop per cycle.
 */
module stream_fifo #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH = 4
) (
    input  wire [0:0]            clk,
    input  wire [0:0]            reset,
    input  wire [0:0]            input_valid,
    output wire [0:0]            input_ready,
    input  wire [DATA_WIDTH-1:0] input_data,
    output wire [0:0]            output_valid,
    input  wire [0:0]            output_ready,
    output wire [DATA_WIDTH-1:0] output_data,
    output wire [0:0]            overflow_attempt,
    output wire [0:0]            underflow_attempt
);
    localparam integer POINTER_WIDTH = $clog2(DEPTH);
    localparam integer COUNT_WIDTH = $clog2(DEPTH + 1);

    reg [DATA_WIDTH-1:0] storage [0:DEPTH-1];
    reg [POINTER_WIDTH-1:0] write_pointer;
    reg [POINTER_WIDTH-1:0] read_pointer;
    reg [COUNT_WIDTH-1:0] item_count;

    wire push_accepted;
    wire pop_accepted;

    assign output_valid = !reset && (item_count != 0);

    // A simultaneous pop frees the full slot in time for the accepted push.
    assign input_ready = !reset && (
        (item_count < DEPTH) || (output_valid && output_ready)
    );

    // Invalid output is masked so reset cannot expose stale storage contents.
    assign output_data = output_valid ? storage[read_pointer] : {DATA_WIDTH{1'b0}};
    assign overflow_attempt = !reset && input_valid && !input_ready;
    assign underflow_attempt = !reset && output_ready && !output_valid;
    assign push_accepted = input_valid && input_ready;
    assign pop_accepted = output_valid && output_ready;

    initial begin
        // Smaller parameter values invalidate the pointer and storage invariants.
        if (DATA_WIDTH < 1) begin
            $fatal(1, "stream_fifo DATA_WIDTH must be at least 1");
        end
        if (DEPTH < 2) begin
            $fatal(1, "stream_fifo DEPTH must be at least 2");
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            write_pointer <= {POINTER_WIDTH{1'b0}};
            read_pointer <= {POINTER_WIDTH{1'b0}};
            item_count <= {COUNT_WIDTH{1'b0}};
        end
        else begin
            if (push_accepted) begin
                storage[write_pointer] <= input_data;
                if (write_pointer == DEPTH - 1) begin
                    write_pointer <= {POINTER_WIDTH{1'b0}};
                end
                else begin
                    write_pointer <= write_pointer + 1'b1;
                end
            end

            if (pop_accepted) begin
                if (read_pointer == DEPTH - 1) begin
                    read_pointer <= {POINTER_WIDTH{1'b0}};
                end
                else begin
                    read_pointer <= read_pointer + 1'b1;
                end
            end

            case ({push_accepted, pop_accepted})
                2'b10: item_count <= item_count + 1'b1;
                2'b01: item_count <= item_count - 1'b1;
                default: item_count <= item_count;
            endcase
        end
    end
endmodule
