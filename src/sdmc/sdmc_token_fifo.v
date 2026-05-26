`default_nettype none

`include "sdmc_stream_defs.vh"

module sdmc_token_fifo #(
    parameter DEPTH = 4,
    parameter AW    = 2
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      clear,

    input  wire                      push,
    input  wire [`SDMC_TOKEN_W-1:0]  din,
    output wire                      full,

    input  wire                      pop,
    output wire [`SDMC_TOKEN_W-1:0]  dout,
    output wire                      empty,

    output reg  [AW:0]               count
);

    reg [`SDMC_TOKEN_W-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wr_ptr;
    reg [AW-1:0] rd_ptr;

    wire do_push = push && !full;
    wire do_pop  = pop  && !empty;

    assign full  = (count == DEPTH[AW:0]);
    assign empty = (count == {AW+1{1'b0}});

    // Small fall-through head read. Keep DEPTH shallow at IO boundaries.
    assign dout = empty ? {`SDMC_TOKEN_W{1'b0}} : mem[rd_ptr];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {AW{1'b0}};
            rd_ptr <= {AW{1'b0}};
            count  <= {AW+1{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= {`SDMC_TOKEN_W{1'b0}};
            end
        end else if (clear) begin
            wr_ptr <= {AW{1'b0}};
            rd_ptr <= {AW{1'b0}};
            count  <= {AW+1{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= {`SDMC_TOKEN_W{1'b0}};
            end
        end else begin
            if (do_push) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= wr_ptr + {{AW-1{1'b0}}, 1'b1};
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
