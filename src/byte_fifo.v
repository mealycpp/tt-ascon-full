/*
 * byte_fifo.v — small synchronous byte FIFO for UART<->packer staging.
 *
 * Single clock, parameterizable depth (DEPTH must be a power of 2 for the
 * simple pointer-wrap implementation).
 *
 * Handshake:
 *   write side: assert wr_en with wr_data when !full
 *   read side:  assert rd_en when !empty; rd_data is valid on the same cycle
 *               (FWFT — first word fall-through)
 */
`default_nettype none

module byte_fifo #(
    parameter DEPTH = 16,
    parameter AW    = 4    // log2(DEPTH); for DEPTH=16, AW=4
) (
    input  wire        clk,
    input  wire        rst_n,

    // Write
    input  wire        wr_en,
    input  wire [7:0]  wr_data,
    output wire        full,

    // Read (FWFT: rd_data is the head whenever !empty)
    input  wire        rd_en,
    output wire [7:0]  rd_data,
    output wire        empty,

    // Status
    output wire [AW:0] count   // 0..DEPTH
);

    reg [7:0]   mem [0:DEPTH-1];
    reg [AW:0]  wr_ptr;
    reg [AW:0]  rd_ptr;

    wire [AW-1:0] wr_idx = wr_ptr[AW-1:0];
    wire [AW-1:0] rd_idx = rd_ptr[AW-1:0];

    assign empty = (wr_ptr == rd_ptr);
    assign full  = ((wr_ptr[AW] != rd_ptr[AW]) &&
                    (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]));
    assign count = wr_ptr - rd_ptr;
    assign rd_data = mem[rd_idx];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            for (i = 0; i < DEPTH; i = i + 1) mem[i] <= 8'd0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_idx] <= wr_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule
