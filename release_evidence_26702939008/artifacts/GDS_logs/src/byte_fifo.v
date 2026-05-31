/*
 * byte_fifo.v — small synchronous byte FIFO.
 *
 * Area/fanout surgery:
 *   - Do NOT reset FIFO memory bits.
 *   - Only reset pointers.
 *   - This reduces rst_n fanout and reset routing pressure.
 */
`default_nettype none

module byte_fifo #(
    parameter DEPTH = 8,
    parameter AW    = 3
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        wr_en,
    input  wire [7:0]  wr_data,
    output wire        full,

    input  wire        rd_en,
    output wire [7:0]  rd_data,
    output wire        empty,

    output wire [AW:0] count
);

    reg [7:0]  mem [0:DEPTH-1];
    reg [AW:0] wr_ptr;
    reg [AW:0] rd_ptr;

    wire [AW-1:0] wr_idx = wr_ptr[AW-1:0];
    wire [AW-1:0] rd_idx = rd_ptr[AW-1:0];

    assign empty = (wr_ptr == rd_ptr);
    assign full  = ((wr_ptr[AW] != rd_ptr[AW]) &&
                    (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]));
    assign count = wr_ptr - rd_ptr;

    // First-word fall-through read.
    assign rd_data = mem[rd_idx];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {AW+1{1'b0}};
            rd_ptr <= {AW+1{1'b0}};
        end else begin
            if (wr_en && !full) begin
                mem[wr_idx] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end

            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule
