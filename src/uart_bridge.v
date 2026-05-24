/*
 * uart_bridge.v — area surgery version.
 *
 * RX:
 *   UART0 = parser byte stream only.
 *   UART1 = key/nonce/AD/CS stream -> packer.
 *   UART2 = message/data/tag stream -> packer.
 *
 * TX:
 *   Only UART2 TX is implemented for crypto result output.
 *   UART0 TX and UART1 TX are tied idle-high to save area.
 */
`default_nettype none

module uart_bridge #(
    parameter FIFO_DEPTH = 8,
    parameter FIFO_AW    = 3
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [15:0] baud_div,

    input  wire        uart0_rx,
    input  wire        uart1_rx,
    input  wire        uart2_rx,

    output wire        uart0_tx,
    output wire        uart1_tx,
    output wire        uart2_tx,

    input  wire [2:0]  flush,
    output wire [2:0]  flush_ready,

    output wire [7:0]  uart0_byte,
    output wire        uart0_byte_valid,
    input  wire        uart0_byte_ready,

    output wire [63:0] pack_word_0,
    output wire [3:0]  pack_bytes_0,
    output wire        pack_valid_0,
    input  wire        pack_ready_0,

    output wire [63:0] pack_word_1,
    output wire [3:0]  pack_bytes_1,
    output wire        pack_valid_1,
    input  wire        pack_ready_1,

    output wire [63:0] pack_word_2,
    output wire [3:0]  pack_bytes_2,
    output wire        pack_valid_2,
    input  wire        pack_ready_2,

    input  wire [1:0]  tx_sel,

    input  wire [63:0] sdmc_out_block,
    input  wire [3:0]  sdmc_out_byte_count,
    input  wire        sdmc_out_valid,
    output wire        sdmc_out_ready,

    output wire [2:0]  rx_fifo_empty,
    output wire [2:0]  rx_fifo_full,
    output wire [2:0]  tx_fifo_empty,
    output wire [2:0]  tx_fifo_full
);

    // ------------------------------------------------------------
    // UART RX
    // ------------------------------------------------------------
    wire [7:0] rx0_byte, rx1_byte, rx2_byte;
    wire       rx0_valid, rx1_valid, rx2_valid;
    wire       rx0_active, rx1_active, rx2_active;

    uart_rx u_rx0 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .rx(uart0_rx),
        .byte_out(rx0_byte), .byte_valid(rx0_valid),
        .rx_active(rx0_active)
    );

    uart_rx u_rx1 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .rx(uart1_rx),
        .byte_out(rx1_byte), .byte_valid(rx1_valid),
        .rx_active(rx1_active)
    );

    uart_rx u_rx2 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .rx(uart2_rx),
        .byte_out(rx2_byte), .byte_valid(rx2_valid),
        .rx_active(rx2_active)
    );

    wire _unused_rx = &{
        rx0_active, rx1_active, rx2_active,
        pack_ready_0, flush[0], tx_sel, 1'b0
    };

    // ------------------------------------------------------------
    // UART0 parser FIFO only
    // ------------------------------------------------------------
    wire uart0_fifo_empty;
    wire uart0_fifo_full;
    wire [FIFO_AW:0] uart0_fifo_count_unused;

    byte_fifo #(.DEPTH(FIFO_DEPTH), .AW(FIFO_AW)) u_uart0_parser_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx0_valid), .wr_data(rx0_byte), .full(uart0_fifo_full),
        .rd_en(uart0_byte_ready && !uart0_fifo_empty),
        .rd_data(uart0_byte), .empty(uart0_fifo_empty),
        .count(uart0_fifo_count_unused)
    );

    assign uart0_byte_valid = !uart0_fifo_empty;

    assign pack_word_0    = 64'd0;
    assign pack_bytes_0   = 4'd0;
    assign pack_valid_0   = 1'b0;
    assign flush_ready[0] = 1'b1;

    // ------------------------------------------------------------
    // UART1 RX FIFO -> packer
    // ------------------------------------------------------------
    wire [7:0] fifo1_rd_data;
    wire       fifo1_empty;
    wire       fifo1_full;
    wire [FIFO_AW:0] fifo1_count_unused;
    wire       pack1_in_ready;

    byte_fifo #(.DEPTH(FIFO_DEPTH), .AW(FIFO_AW)) u_rx1_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx1_valid), .wr_data(rx1_byte), .full(fifo1_full),
        .rd_en(pack1_in_ready && !fifo1_empty),
        .rd_data(fifo1_rd_data), .empty(fifo1_empty),
        .count(fifo1_count_unused)
    );

    byte_to_word_packer u_pack1 (
        .clk(clk), .rst_n(rst_n),
        .in_byte(fifo1_rd_data),
        .in_byte_valid(!fifo1_empty),
        .in_byte_ready(pack1_in_ready),
        .flush(flush[1]), .flush_ready(flush_ready[1]),
        .out_word(pack_word_1),
        .out_word_bytes(pack_bytes_1),
        .out_word_valid(pack_valid_1),
        .out_word_ready(pack_ready_1)
    );

    // ------------------------------------------------------------
    // UART2 RX FIFO -> packer
    // ------------------------------------------------------------
    wire [7:0] fifo2_rd_data;
    wire       fifo2_empty;
    wire       fifo2_full;
    wire [FIFO_AW:0] fifo2_count_unused;
    wire       pack2_in_ready;

    byte_fifo #(.DEPTH(FIFO_DEPTH), .AW(FIFO_AW)) u_rx2_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx2_valid), .wr_data(rx2_byte), .full(fifo2_full),
        .rd_en(pack2_in_ready && !fifo2_empty),
        .rd_data(fifo2_rd_data), .empty(fifo2_empty),
        .count(fifo2_count_unused)
    );

    byte_to_word_packer u_pack2 (
        .clk(clk), .rst_n(rst_n),
        .in_byte(fifo2_rd_data),
        .in_byte_valid(!fifo2_empty),
        .in_byte_ready(pack2_in_ready),
        .flush(flush[2]), .flush_ready(flush_ready[2]),
        .out_word(pack_word_2),
        .out_word_bytes(pack_bytes_2),
        .out_word_valid(pack_valid_2),
        .out_word_ready(pack_ready_2)
    );

    // ------------------------------------------------------------
    // TX path: only UART2 result output
    // ------------------------------------------------------------
    assign uart0_tx = 1'b1;
    assign uart1_tx = 1'b1;

    wire [7:0] unpk_byte;
    wire       unpk_byte_valid;
    wire       unpk_byte_ready;

    word_to_byte_unpacker u_unpk (
        .clk(clk), .rst_n(rst_n),
        .in_word(sdmc_out_block),
        .in_word_bytes(sdmc_out_byte_count),
        .in_word_valid(sdmc_out_valid),
        .in_word_ready(sdmc_out_ready),
        .out_byte(unpk_byte),
        .out_byte_valid(unpk_byte_valid),
        .out_byte_ready(unpk_byte_ready)
    );

    wire [7:0] tx2_fifo_rd_data;
    wire       tx2_fifo_empty;
    wire       tx2_fifo_full;
    wire [FIFO_AW:0] tx2_fifo_count_unused;

    assign unpk_byte_ready = !tx2_fifo_full;

    wire u_tx2_send_pulse;
    reg  u_tx2_send;
    wire u_tx2_ready;

    assign u_tx2_send_pulse = u_tx2_send;

    byte_fifo #(.DEPTH(FIFO_DEPTH), .AW(FIFO_AW)) u_tx2_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(unpk_byte_valid), .wr_data(unpk_byte), .full(tx2_fifo_full),
        .rd_en(u_tx2_send_pulse), .rd_data(tx2_fifo_rd_data),
        .empty(tx2_fifo_empty), .count(tx2_fifo_count_unused)
    );

    uart_tx u_tx2 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .byte_in(tx2_fifo_rd_data),
        .send(u_tx2_send),
        .ready(u_tx2_ready),
        .tx(uart2_tx)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            u_tx2_send <= 1'b0;
        end else begin
            u_tx2_send <= u_tx2_ready && !tx2_fifo_empty && !u_tx2_send;
        end
    end

    assign rx_fifo_empty = {fifo2_empty, fifo1_empty, uart0_fifo_empty};
    assign rx_fifo_full  = {fifo2_full,  fifo1_full,  uart0_fifo_full};

    assign tx_fifo_empty = {tx2_fifo_empty, 1'b1, 1'b1};
    assign tx_fifo_full  = {tx2_fifo_full,  1'b0, 1'b0};

endmodule
