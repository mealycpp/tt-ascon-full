`default_nettype none

module sdmc_fifo #(
    parameter WIDTH = 64,
    parameter DEPTH = 4,
    parameter AW    = 2
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             clear,

    input  wire             push,
    input  wire [WIDTH-1:0] din,
    output wire             full,

    input  wire             pop,
    output wire [WIDTH-1:0] dout,
    output wire             empty,

    output reg  [AW:0]      count
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wr_ptr;
    reg [AW-1:0] rd_ptr;

    assign empty = (count == {AW+1{1'b0}});
    assign full  = (count == DEPTH[AW:0]);
    assign dout  = mem[rd_ptr];

    wire do_push = push && !full;
    wire do_pop  = pop  && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {AW{1'b0}};
            rd_ptr <= {AW{1'b0}};
            count  <= {AW+1{1'b0}};
        end else if (clear) begin
            wr_ptr <= {AW{1'b0}};
            rd_ptr <= {AW{1'b0}};
            count  <= {AW+1{1'b0}};
        end else begin
            if (do_push) begin
                mem[wr_ptr] <= din;
                wr_ptr <= wr_ptr + {{AW-1{1'b0}}, 1'b1};
            end

            if (do_pop) begin
                rd_ptr <= rd_ptr + {{AW-1{1'b0}}, 1'b1};
            end

            case ({do_push, do_pop})
                2'b10: count <= count + {{AW{1'b0}}, 1'b1};
                2'b01: count <= count - {{AW{1'b0}}, 1'b1};
                default: count <= count;
            endcase
        end
    end

endmodule

`default_nettype wire
