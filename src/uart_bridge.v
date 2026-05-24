/*
 * uart_bridge.v — Phase 2 of UART<->SDMC bridge.
 *
 * Connects three physical UART RX channels and three physical UART TX
 * channels to a single 64-bit streaming interface intended for
 * mode_controller. No byte-level scheduling: each RX lane is independent
 * with its own byte FIFO + packer. A single word-level 3:1 mux selects
 * which lane drives the SDMC input.
 *
 * Pin lineage (locked TT pinout):
 *   UART0 = control / status
 *   UART1 = AD / customization / status
 *   UART2 = data / result stream
 *
 * Driving controls (from protocol_parser in Phase 3, from testbench now):
 *   - phase_sel[1:0]: which RX lane (0/1/2) feeds mode_controller this turn
 *   - tx_sel[1:0]:    which TX lane consumes mode_controller output
 *   - flush[2:0]:     per-lane packer flush (caller holds until flush_ready)
 *
 * SDMC crypto core untouched. This module is pure wiring + small muxes.
 */
`default_nettype none

module uart_bridge #(
    parameter FIFO_DEPTH = 16,
    parameter FIFO_AW    = 4
) (
    input  wire        clk,
    input  wire        rst_n,

    // UART configuration
    input  wire [15:0] baud_div,

    // Physical RX pins (3)
    input  wire        uart0_rx,
    input  wire        uart1_rx,
    input  wire        uart2_rx,

    // Physical TX pins (3)
    output wire        uart0_tx,
    output wire        uart1_tx,
    output wire        uart2_tx,

    // Phase select for word-level 3:1 RX mux
    input  wire [1:0]  phase_sel,         // 0/1/2; 3 = none

    // Per-lane flush handshake (3 packers)
    input  wire [2:0]  flush,
    output wire [2:0]  flush_ready,

    // 64-bit streaming output to mode_controller (selected RX lane)
    output wire [63:0] sdmc_in_word,
    output wire [3:0]  sdmc_in_word_bytes,
    output wire        sdmc_in_word_valid,
    input  wire        sdmc_in_word_ready,

    // TX select: which UART lane consumes SDMC output
    input  wire [1:0]  tx_sel,            // 0/1/2

    // 64-bit streaming input from mode_controller (will become TX bytes)
    input  wire [63:0] sdmc_out_block,
    input  wire [3:0]  sdmc_out_byte_count,
    input  wire        sdmc_out_valid,
    output wire        sdmc_out_ready,    // bridge ready to accept word

    // Status (per-lane FIFO levels for protocol parser)
    output wire [2:0]  rx_fifo_empty,
    output wire [2:0]  rx_fifo_full,
    output wire [2:0]  tx_fifo_empty,
    output wire [2:0]  tx_fifo_full
);

    // ============================================================
    // RX LANES (3 independent: UART_RX -> byte_fifo -> packer)
    // ============================================================

    // Per-lane wires
    wire [7:0]  rx_byte    [0:2];
    wire        rx_byte_valid [0:2];
    wire        rx_byte_active [0:2];   // unused for now

    wire [7:0]  fifo_rd_data [0:2];
    wire        fifo_empty_w [0:2];
    wire        fifo_full_w  [0:2];
    wire [FIFO_AW:0] fifo_count [0:2];

    wire [63:0] pack_word    [0:2];
    wire [3:0]  pack_bytes   [0:2];
    wire        pack_valid   [0:2];
    wire        pack_in_ready [0:2];

    genvar i;

    // ---- UART0 RX ----
    uart_rx u_rx0 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .rx(uart0_rx),
        .byte_out(rx_byte[0]), .byte_valid(rx_byte_valid[0]),
        .rx_active(rx_byte_active[0])
    );
    byte_fifo #(.DEPTH(FIFO_DEPTH), .AW(FIFO_AW)) u_rx0_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx_byte_valid[0]), .wr_data(rx_byte[0]), .full(fifo_full_w[0]),
        .rd_en(pack_in_ready[0] && !fifo_empty_w[0]),
        .rd_data(fifo_rd_data[0]), .empty(fifo_empty_w[0]),
        .count(fifo_count[0])
    );
    byte_to_word_packer u_pack0 (
        .clk(clk), .rst_n(rst_n),
        .in_byte(fifo_rd_data[0]),
        .in_byte_valid(!fifo_empty_w[0]),
        .in_byte_ready(pack_in_ready[0]),
        .flush(flush[0]), .flush_ready(flush_ready[0]),
        .out_word(pack_word[0]), .out_word_bytes(pack_bytes[0]),
        .out_word_valid(pack_valid[0]),
        .out_word_ready((phase_sel == 2'd0) && sdmc_in_word_ready)
    );

    // ---- UART1 RX ----
    uart_rx u_rx1 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .rx(uart1_rx),
        .byte_out(rx_byte[1]), .byte_valid(rx_byte_valid[1]),
        .rx_active(rx_byte_active[1])
    );
    byte_fifo #(.DEPTH(FIFO_DEPTH), .AW(FIFO_AW)) u_rx1_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx_byte_valid[1]), .wr_data(rx_byte[1]), .full(fifo_full_w[1]),
        .rd_en(pack_in_ready[1] && !fifo_empty_w[1]),
        .rd_data(fifo_rd_data[1]), .empty(fifo_empty_w[1]),
        .count(fifo_count[1])
    );
    byte_to_word_packer u_pack1 (
        .clk(clk), .rst_n(rst_n),
        .in_byte(fifo_rd_data[1]),
        .in_byte_valid(!fifo_empty_w[1]),
        .in_byte_ready(pack_in_ready[1]),
        .flush(flush[1]), .flush_ready(flush_ready[1]),
        .out_word(pack_word[1]), .out_word_bytes(pack_bytes[1]),
        .out_word_valid(pack_valid[1]),
        .out_word_ready((phase_sel == 2'd1) && sdmc_in_word_ready)
    );

    // ---- UART2 RX ----
    uart_rx u_rx2 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .rx(uart2_rx),
        .byte_out(rx_byte[2]), .byte_valid(rx_byte_valid[2]),
        .rx_active(rx_byte_active[2])
    );
    byte_fifo #(.DEPTH(FIFO_DEPTH), .AW(FIFO_AW)) u_rx2_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx_byte_valid[2]), .wr_data(rx_byte[2]), .full(fifo_full_w[2]),
        .rd_en(pack_in_ready[2] && !fifo_empty_w[2]),
        .rd_data(fifo_rd_data[2]), .empty(fifo_empty_w[2]),
        .count(fifo_count[2])
    );
    byte_to_word_packer u_pack2 (
        .clk(clk), .rst_n(rst_n),
        .in_byte(fifo_rd_data[2]),
        .in_byte_valid(!fifo_empty_w[2]),
        .in_byte_ready(pack_in_ready[2]),
        .flush(flush[2]), .flush_ready(flush_ready[2]),
        .out_word(pack_word[2]), .out_word_bytes(pack_bytes[2]),
        .out_word_valid(pack_valid[2]),
        .out_word_ready((phase_sel == 2'd2) && sdmc_in_word_ready)
    );

    // ============================================================
    // WORD-LEVEL 3:1 MUX INTO SDMC
    // ============================================================
    assign sdmc_in_word       = (phase_sel == 2'd0) ? pack_word[0]
                              : (phase_sel == 2'd1) ? pack_word[1]
                              : (phase_sel == 2'd2) ? pack_word[2]
                              : 64'd0;
    assign sdmc_in_word_bytes = (phase_sel == 2'd0) ? pack_bytes[0]
                              : (phase_sel == 2'd1) ? pack_bytes[1]
                              : (phase_sel == 2'd2) ? pack_bytes[2]
                              : 4'd0;
    assign sdmc_in_word_valid = (phase_sel == 2'd0) ? pack_valid[0]
                              : (phase_sel == 2'd1) ? pack_valid[1]
                              : (phase_sel == 2'd2) ? pack_valid[2]
                              : 1'b0;

    // ============================================================
    // TX SIDE: unpacker -> selected TX FIFO -> uart_tx
    // ============================================================

    wire [7:0]  unpk_byte;
    wire        unpk_byte_valid;
    wire        unpk_byte_ready;  // = !tx_fifo_full[tx_sel]

    word_to_byte_unpacker u_unpk (
        .clk(clk), .rst_n(rst_n),
        .in_word(sdmc_out_block), .in_word_bytes(sdmc_out_byte_count),
        .in_word_valid(sdmc_out_valid), .in_word_ready(sdmc_out_ready),
        .out_byte(unpk_byte), .out_byte_valid(unpk_byte_valid),
        .out_byte_ready(unpk_byte_ready)
    );

    // Three TX FIFOs, only the selected one accepts the byte
    wire [7:0]  tx_fifo_rd_data [0:2];
    wire        tx_fifo_empty_w [0:2];
    wire        tx_fifo_full_w  [0:2];
    wire [FIFO_AW:0] tx_fifo_count [0:2];

    wire        tx_wr_en_0 = unpk_byte_valid && (tx_sel == 2'd0);
    wire        tx_wr_en_1 = unpk_byte_valid && (tx_sel == 2'd1);
    wire        tx_wr_en_2 = unpk_byte_valid && (tx_sel == 2'd2);

    assign unpk_byte_ready = (tx_sel == 2'd0) ? !tx_fifo_full_w[0]
                           : (tx_sel == 2'd1) ? !tx_fifo_full_w[1]
                           : (tx_sel == 2'd2) ? !tx_fifo_full_w[2]
                           : 1'b0;

    byte_fifo #(.DEPTH(FIFO_DEPTH), .AW(FIFO_AW)) u_tx0_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(tx_wr_en_0), .wr_data(unpk_byte), .full(tx_fifo_full_w[0]),
        .rd_en(u_tx0_send_pulse), .rd_data(tx_fifo_rd_data[0]),
        .empty(tx_fifo_empty_w[0]), .count(tx_fifo_count[0])
    );
    byte_fifo #(.DEPTH(FIFO_DEPTH), .AW(FIFO_AW)) u_tx1_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(tx_wr_en_1), .wr_data(unpk_byte), .full(tx_fifo_full_w[1]),
        .rd_en(u_tx1_send_pulse), .rd_data(tx_fifo_rd_data[1]),
        .empty(tx_fifo_empty_w[1]), .count(tx_fifo_count[1])
    );
    byte_fifo #(.DEPTH(FIFO_DEPTH), .AW(FIFO_AW)) u_tx2_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(tx_wr_en_2), .wr_data(unpk_byte), .full(tx_fifo_full_w[2]),
        .rd_en(u_tx2_send_pulse), .rd_data(tx_fifo_rd_data[2]),
        .empty(tx_fifo_empty_w[2]), .count(tx_fifo_count[2])
    );

    // UART TX: pull byte from FIFO when uart_tx is ready and FIFO non-empty
    wire        u_tx0_ready, u_tx1_ready, u_tx2_ready;
    reg         u_tx0_send,  u_tx1_send,  u_tx2_send;
    wire        u_tx0_send_pulse = u_tx0_send;
    wire        u_tx1_send_pulse = u_tx1_send;
    wire        u_tx2_send_pulse = u_tx2_send;

    uart_tx u_tx0 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .byte_in(tx_fifo_rd_data[0]), .send(u_tx0_send),
        .ready(u_tx0_ready), .tx(uart0_tx)
    );
    uart_tx u_tx1 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .byte_in(tx_fifo_rd_data[1]), .send(u_tx1_send),
        .ready(u_tx1_ready), .tx(uart1_tx)
    );
    uart_tx u_tx2 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .byte_in(tx_fifo_rd_data[2]), .send(u_tx2_send),
        .ready(u_tx2_ready), .tx(uart2_tx)
    );

    // send pulse logic: when uart_tx is ready AND FIFO has byte, pulse send
    // for 1 cycle (this also pops the FIFO via rd_en)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            u_tx0_send <= 1'b0;
            u_tx1_send <= 1'b0;
            u_tx2_send <= 1'b0;
        end else begin
            u_tx0_send <= u_tx0_ready && !tx_fifo_empty_w[0] && !u_tx0_send;
            u_tx1_send <= u_tx1_ready && !tx_fifo_empty_w[1] && !u_tx1_send;
            u_tx2_send <= u_tx2_ready && !tx_fifo_empty_w[2] && !u_tx2_send;
        end
    end

    // Status outputs
    assign rx_fifo_empty = {fifo_empty_w[2], fifo_empty_w[1], fifo_empty_w[0]};
    assign rx_fifo_full  = {fifo_full_w[2],  fifo_full_w[1],  fifo_full_w[0]};
    assign tx_fifo_empty = {tx_fifo_empty_w[2], tx_fifo_empty_w[1], tx_fifo_empty_w[0]};
    assign tx_fifo_full  = {tx_fifo_full_w[2],  tx_fifo_full_w[1],  tx_fifo_full_w[0]};

endmodule
