`default_nettype none

module tt_um_mealycpp_ascon_sdmc_uart (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire uart0_rx = ui_in[0];
    wire uart1_rx = ui_in[1];
    wire uart2_rx = ui_in[2];
    wire clear = !ena;

    wire [15:0] baud_div = 16'd217;

    wire [7:0] rx0_byte;
    wire [7:0] rx1_byte;
    wire [7:0] rx2_byte;
    wire rx0_valid;
    wire rx1_valid;
    wire rx2_valid;
    wire rx0_active;
    wire rx1_active;
    wire rx2_active;

    uart_rx u_rx0 (.clk(clk), .rst_n(rst_n), .baud_div(baud_div), .rx(uart0_rx), .byte_out(rx0_byte), .byte_valid(rx0_valid), .rx_active(rx0_active));
    uart_rx u_rx1 (.clk(clk), .rst_n(rst_n), .baud_div(baud_div), .rx(uart1_rx), .byte_out(rx1_byte), .byte_valid(rx1_valid), .rx_active(rx1_active));
    uart_rx u_rx2 (.clk(clk), .rst_n(rst_n), .baud_div(baud_div), .rx(uart2_rx), .byte_out(rx2_byte), .byte_valid(rx2_valid), .rx_active(rx2_active));

    wire [7:0] fifo0_dout;
    wire [7:0] fifo1_dout;
    wire [7:0] fifo2_dout;
    wire fifo0_empty;
    wire fifo1_empty;
    wire fifo2_empty;
    wire fifo0_full;
    wire fifo1_full;
    wire fifo2_full;
    wire [3:0] fifo0_count;
    wire [3:0] fifo1_count;
    wire [3:0] fifo2_count;

    wire parser_ready;
    wire fifo0_pop = parser_ready && !fifo0_empty;

    byte_fifo #(.DEPTH(8), .AW(3)) u_fifo0 (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx0_valid), .wr_data(rx0_byte), .full(fifo0_full),
        .rd_en(fifo0_pop), .rd_data(fifo0_dout), .empty(fifo0_empty),
        .count(fifo0_count)
    );

    wire fifo1_pop;
    wire fifo2_pop;

    byte_fifo #(.DEPTH(8), .AW(3)) u_fifo1 (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx1_valid), .wr_data(rx1_byte), .full(fifo1_full),
        .rd_en(fifo1_pop), .rd_data(fifo1_dout), .empty(fifo1_empty),
        .count(fifo1_count)
    );

    byte_fifo #(.DEPTH(8), .AW(3)) u_fifo2 (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx2_valid), .wr_data(rx2_byte), .full(fifo2_full),
        .rd_en(fifo2_pop), .rd_data(fifo2_dout), .empty(fifo2_empty),
        .count(fifo2_count)
    );

    wire [2:0]  mode_sel;
    wire        is_decrypt;
    wire        chain_enable;
    wire        chain_debug;
    wire [15:0] ad_total_bytes;
    wire [15:0] data_total_bytes;
    wire [15:0] out_length;
    wire [15:0] chain_count;
    wire [15:0] cs_total_bits;
    wire        frame_valid;
    wire        frame_error;
    wire        parser_start_unused;

    protocol_parser u_parser (
        .clk(clk),
        .rst_n(rst_n),
        .in_byte(fifo0_dout),
        .in_byte_valid(!fifo0_empty),
        .in_byte_ready(parser_ready),
        .mode_sel(mode_sel),
        .is_decrypt(is_decrypt),
        .chain_enable(chain_enable),
        .chain_debug(chain_debug),
        .ad_total_bytes(ad_total_bytes),
        .data_total_bytes(data_total_bytes),
        .out_length(out_length),
        .chain_count(chain_count),
        .cs_total_bits(cs_total_bits),
        .frame_valid(frame_valid),
        .frame_error(frame_error),
        .start(parser_start_unused)
    );

    wire cfg_wr_en;
    wire [3:0] cfg_wr_addr;
    wire [63:0] cfg_wr_data;
    wire sdmc_start;

    wire [7:0] sdmc_in_byte;
    wire [3:0] sdmc_in_kind;
    wire sdmc_in_last;
    wire sdmc_in_valid;
    wire sdmc_in_ready;

    wire [7:0] sdmc_out_byte;
    wire [3:0] sdmc_out_kind;
    wire sdmc_out_last;
    wire sdmc_out_valid;
    wire sdmc_out_ready;

    wire sdmc_busy;
    wire sdmc_done;
    wire sdmc_error;
    wire sdmc_auth_ok;
    wire [3:0] host_mode;
    wire [3:0] program_id;
    wire [15:0] in_count;
    wire [15:0] out_count;

    wire bridge_busy;
    wire bridge_error;

    sdmc_uart_token_bridge u_token_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .frame_valid(frame_valid),
        .mode_sel(mode_sel),
        .is_decrypt(is_decrypt),
        .ad_total_bytes(ad_total_bytes),
        .data_total_bytes(data_total_bytes),
        .out_length(out_length),
        .chain_count(chain_count),
        .cs_total_bits(cs_total_bits),

        .cfg_wr_en(cfg_wr_en),
        .cfg_wr_addr(cfg_wr_addr),
        .cfg_wr_data(cfg_wr_data),
        .sdmc_start(sdmc_start),

        .uart1_byte(fifo1_dout),
        .uart1_empty(fifo1_empty),
        .uart1_rd_en(fifo1_pop),

        .uart2_byte(fifo2_dout),
        .uart2_empty(fifo2_empty),
        .uart2_rd_en(fifo2_pop),

        .in_byte(sdmc_in_byte),
        .in_kind(sdmc_in_kind),
        .in_last(sdmc_in_last),
        .in_valid(sdmc_in_valid),
        .in_ready(sdmc_in_ready),

        .sdmc_done(sdmc_done),
        .sdmc_error(sdmc_error),

        .bridge_busy(bridge_busy),
        .bridge_error(bridge_error)
    );

    sdmc_crypto_top_hx #(.FIFO_DEPTH(8), .FIFO_AW(3)) u_sdmc (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .start(sdmc_start),

        .cfg_wr_en(cfg_wr_en),
        .cfg_wr_addr(cfg_wr_addr),
        .cfg_wr_data(cfg_wr_data),

        .in_byte(sdmc_in_byte),
        .in_kind(sdmc_in_kind),
        .in_last(sdmc_in_last),
        .in_valid(sdmc_in_valid),
        .in_ready(sdmc_in_ready),

        .out_byte(sdmc_out_byte),
        .out_kind(sdmc_out_kind),
        .out_last(sdmc_out_last),
        .out_valid(sdmc_out_valid),
        .out_ready(sdmc_out_ready),

        .busy(sdmc_busy),
        .done(sdmc_done),
        .error(sdmc_error),
        .auth_ok(sdmc_auth_ok),

        .host_mode(host_mode),
        .program_id(program_id),

        .in_count(in_count),
        .out_count(out_count)
    );

    wire [7:0] tx_fifo_dout;
    wire tx_fifo_empty;
    wire tx_fifo_full;
    wire [3:0] tx_fifo_count;
    wire tx_ready;
    wire tx_send = tx_ready && !tx_fifo_empty;

    assign sdmc_out_ready = !tx_fifo_full;

    byte_fifo #(.DEPTH(8), .AW(3)) u_tx_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(sdmc_out_valid && sdmc_out_ready),
        .wr_data(sdmc_out_byte),
        .full(tx_fifo_full),
        .rd_en(tx_send),
        .rd_data(tx_fifo_dout),
        .empty(tx_fifo_empty),
        .count(tx_fifo_count)
    );

    wire uart2_tx;

    uart_tx u_tx2 (
        .clk(clk),
        .rst_n(rst_n),
        .baud_div(baud_div),
        .byte_in(tx_fifo_dout),
        .send(tx_send),
        .ready(tx_ready),
        .tx(uart2_tx)
    );

    reg frame_error_sticky;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_error_sticky <= 1'b0;
        else if (frame_error || bridge_error || sdmc_error) frame_error_sticky <= 1'b1;
        else if (frame_valid) frame_error_sticky <= 1'b0;
    end

    reg [23:0] hb_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hb_cnt <= 24'd0;
        else hb_cnt <= hb_cnt + 24'd1;
    end

    assign uo_out[0] = 1'b1;
    assign uo_out[1] = 1'b1;
    assign uo_out[2] = uart2_tx;
    assign uo_out[3] = sdmc_busy | bridge_busy;
    assign uo_out[4] = sdmc_done;
    assign uo_out[5] = frame_error_sticky;
    assign uo_out[6] = sdmc_auth_ok;
    assign uo_out[7] = hb_cnt[23];

    assign uio_out = {sdmc_out_kind, host_mode};
    assign uio_oe  = 8'h00;

    wire _unused = &{
        uio_in,
        rx0_active, rx1_active, rx2_active,
        fifo0_full, fifo1_full, fifo2_full,
        fifo0_count, fifo1_count, fifo2_count,
        chain_enable, chain_debug, parser_start_unused,
        program_id, in_count, out_count,
        sdmc_out_last, tx_fifo_count,
        1'b0
    };

endmodule

`default_nettype wire
