`default_nettype none

`include "src/sdmc/sdmc_stream_defs.vh"

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

    uart_rx u_rx0 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .rx(uart0_rx), .byte_out(rx0_byte),
        .byte_valid(rx0_valid), .rx_active(rx0_active)
    );

    uart_rx u_rx1 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .rx(uart1_rx), .byte_out(rx1_byte),
        .byte_valid(rx1_valid), .rx_active(rx1_active)
    );

    uart_rx u_rx2 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .rx(uart2_rx), .byte_out(rx2_byte),
        .byte_valid(rx2_valid), .rx_active(rx2_active)
    );

    wire                     aead_start;
    wire                     aead_is_decrypt;
    wire [15:0]              aead_ad_len;
    wire [15:0]              aead_data_len;
    wire [`SDMC_TOKEN_W-1:0] aead_in_token;
    wire                     aead_in_empty;
    wire                     aead_in_pop;
    wire                     front_busy;
    wire                     front_error;
    wire [3:0]               front_phase;

    sdmc_aead_uart_frontend u_front (
        .clk             (clk),
        .rst_n           (rst_n),
        .clear           (clear),

        .rx0_byte        (rx0_byte),
        .rx0_valid       (rx0_valid),
        .rx1_byte        (rx1_byte),
        .rx1_valid       (rx1_valid),
        .rx2_byte        (rx2_byte),
        .rx2_valid       (rx2_valid),

        .aead_start      (aead_start),
        .aead_is_decrypt (aead_is_decrypt),
        .aead_ad_len     (aead_ad_len),
        .aead_data_len   (aead_data_len),

        .aead_in_token   (aead_in_token),
        .aead_in_empty   (aead_in_empty),
        .aead_in_pop     (aead_in_pop),

        .busy            (front_busy),
        .error           (front_error),
        .phase_dbg       (front_phase)
    );

    wire [`SDMC_TOKEN_W-1:0] aead_out_token;
    wire                     aead_out_push;
    wire                     aead_out_full;
    wire                     aead_busy;
    wire                     aead_done;
    wire                     aead_error;
    wire                     aead_auth_ok;

    sdmc_aead128_core u_aead (
        .clk        (clk),
        .rst_n      (rst_n),
        .clear      (clear),

        .start      (aead_start),
        .is_decrypt (aead_is_decrypt),
        .ad_len     (aead_ad_len),
        .data_len   (aead_data_len),

        .in_token   (aead_in_token),
        .in_empty   (aead_in_empty),
        .in_pop     (aead_in_pop),

        .out_token  (aead_out_token),
        .out_push   (aead_out_push),
        .out_full   (aead_out_full),

        .busy       (aead_busy),
        .done       (aead_done),
        .error      (aead_error),
        .auth_ok    (aead_auth_ok)
    );

    // Tiny output serializer: AEAD output tokens -> UART2 bytes.
    // No SRAM/deep FIFO. Uses one active token plus five pending token registers.
    // Capacity covers max tested AEAD burst up to 32-byte data:
    // ceil(32/8) data tokens + 2 tag tokens = 6 total tokens.
    reg [63:0] ser_data_q;
    reg [3:0]  ser_count_q;
    reg [3:0]  ser_idx_q;
    reg [3:0]  ser_kind_q;
    reg        ser_valid_q;

    reg [63:0] pend0_data_q;
    reg [3:0]  pend0_count_q;
    reg [3:0]  pend0_kind_q;
    reg        pend0_valid_q;

    reg [63:0] pend1_data_q;
    reg [3:0]  pend1_count_q;
    reg [3:0]  pend1_kind_q;
    reg        pend1_valid_q;

    reg [63:0] pend2_data_q;
    reg [3:0]  pend2_count_q;
    reg [3:0]  pend2_kind_q;
    reg        pend2_valid_q;

    reg [63:0] pend3_data_q;
    reg [3:0]  pend3_count_q;
    reg [3:0]  pend3_kind_q;
    reg        pend3_valid_q;

    reg [63:0] pend4_data_q;
    reg [3:0]  pend4_count_q;
    reg [3:0]  pend4_kind_q;
    reg        pend4_valid_q;

    wire [3:0] out_kind = ser_kind_q;

    assign aead_out_full = ser_valid_q &&
                           pend0_valid_q && pend1_valid_q && pend2_valid_q &&
                           pend3_valid_q && pend4_valid_q;

    wire tx_ready;
    wire tx_send = ser_valid_q && tx_ready;
    wire ser_last_byte = tx_send && ((ser_idx_q + 4'd1) >= ser_count_q);

    reg [7:0] tx_byte;

    always @* begin
        case (ser_idx_q[2:0])
            3'd0: tx_byte = ser_data_q[7:0];
            3'd1: tx_byte = ser_data_q[15:8];
            3'd2: tx_byte = ser_data_q[23:16];
            3'd3: tx_byte = ser_data_q[31:24];
            3'd4: tx_byte = ser_data_q[39:32];
            3'd5: tx_byte = ser_data_q[47:40];
            3'd6: tx_byte = ser_data_q[55:48];
            3'd7: tx_byte = ser_data_q[63:56];
            default: tx_byte = 8'd0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ser_data_q <= 64'd0; ser_count_q <= 4'd0; ser_idx_q <= 4'd0; ser_kind_q <= 4'd0; ser_valid_q <= 1'b0;

            pend0_data_q <= 64'd0; pend0_count_q <= 4'd0; pend0_kind_q <= 4'd0; pend0_valid_q <= 1'b0;
            pend1_data_q <= 64'd0; pend1_count_q <= 4'd0; pend1_kind_q <= 4'd0; pend1_valid_q <= 1'b0;
            pend2_data_q <= 64'd0; pend2_count_q <= 4'd0; pend2_kind_q <= 4'd0; pend2_valid_q <= 1'b0;
            pend3_data_q <= 64'd0; pend3_count_q <= 4'd0; pend3_kind_q <= 4'd0; pend3_valid_q <= 1'b0;
            pend4_data_q <= 64'd0; pend4_count_q <= 4'd0; pend4_kind_q <= 4'd0; pend4_valid_q <= 1'b0;
        end else if (clear) begin
            ser_data_q <= 64'd0; ser_count_q <= 4'd0; ser_idx_q <= 4'd0; ser_kind_q <= 4'd0; ser_valid_q <= 1'b0;

            pend0_valid_q <= 1'b0;
            pend1_valid_q <= 1'b0;
            pend2_valid_q <= 1'b0;
            pend3_valid_q <= 1'b0;
            pend4_valid_q <= 1'b0;
        end else begin
            // Accept AEAD output token.
            if (aead_out_push && !aead_out_full) begin
                if (!ser_valid_q) begin
                    ser_data_q  <= aead_out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];
                    ser_count_q <= aead_out_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
                    ser_idx_q   <= 4'd0;
                    ser_kind_q  <= aead_out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
                    ser_valid_q <= 1'b1;
                end else if (!pend0_valid_q) begin
                    pend0_data_q  <= aead_out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];
                    pend0_count_q <= aead_out_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
                    pend0_kind_q  <= aead_out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
                    pend0_valid_q <= 1'b1;
                end else if (!pend1_valid_q) begin
                    pend1_data_q  <= aead_out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];
                    pend1_count_q <= aead_out_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
                    pend1_kind_q  <= aead_out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
                    pend1_valid_q <= 1'b1;
                end else if (!pend2_valid_q) begin
                    pend2_data_q  <= aead_out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];
                    pend2_count_q <= aead_out_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
                    pend2_kind_q  <= aead_out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
                    pend2_valid_q <= 1'b1;
                end else if (!pend3_valid_q) begin
                    pend3_data_q  <= aead_out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];
                    pend3_count_q <= aead_out_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
                    pend3_kind_q  <= aead_out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
                    pend3_valid_q <= 1'b1;
                end else if (!pend4_valid_q) begin
                    pend4_data_q  <= aead_out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];
                    pend4_count_q <= aead_out_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
                    pend4_kind_q  <= aead_out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
                    pend4_valid_q <= 1'b1;
                end
            end

            // Serialize active token.
            if (tx_send) begin
                if (ser_last_byte) begin
                    if (pend0_valid_q) begin
                        // Promote pend0 into active.
                        ser_data_q  <= pend0_data_q;
                        ser_count_q <= pend0_count_q;
                        ser_idx_q   <= 4'd0;
                        ser_kind_q  <= pend0_kind_q;
                        ser_valid_q <= 1'b1;

                        // Shift pending queue down.
                        pend0_data_q  <= pend1_data_q; pend0_count_q <= pend1_count_q; pend0_kind_q <= pend1_kind_q; pend0_valid_q <= pend1_valid_q;
                        pend1_data_q  <= pend2_data_q; pend1_count_q <= pend2_count_q; pend1_kind_q <= pend2_kind_q; pend1_valid_q <= pend2_valid_q;
                        pend2_data_q  <= pend3_data_q; pend2_count_q <= pend3_count_q; pend2_kind_q <= pend3_kind_q; pend2_valid_q <= pend3_valid_q;
                        pend3_data_q  <= pend4_data_q; pend3_count_q <= pend4_count_q; pend3_kind_q <= pend4_kind_q; pend3_valid_q <= pend4_valid_q;
                        pend4_valid_q <= 1'b0;
                    end else begin
                        ser_valid_q <= 1'b0;
                        ser_idx_q   <= 4'd0;
                    end
                end else begin
                    ser_idx_q <= ser_idx_q + 4'd1;
                end
            end
        end
    end

    wire uart2_tx;

    uart_tx u_tx2 (
        .clk      (clk),
        .rst_n    (rst_n),
        .baud_div (baud_div),
        .byte_in  (tx_byte),
        .send     (tx_send),
        .ready    (tx_ready),
        .tx       (uart2_tx)
    );

    reg error_sticky;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) error_sticky <= 1'b0;
        else if (clear) error_sticky <= 1'b0;
        else if (front_error || aead_error) error_sticky <= 1'b1;
        else if (aead_start) error_sticky <= 1'b0;
    end

    reg [23:0] hb_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hb_cnt <= 24'd0;
        else hb_cnt <= hb_cnt + 24'd1;
    end

    assign uo_out[0] = 1'b1;
    assign uo_out[1] = 1'b1;
    assign uo_out[2] = uart2_tx;
    assign uo_out[3] = front_busy | aead_busy;
    assign uo_out[4] = aead_done;
    assign uo_out[5] = error_sticky;
    assign uo_out[6] = aead_auth_ok;
    assign uo_out[7] = hb_cnt[23];

    // Debug: high nibble = output token kind, low nibble = frontend phase.
    assign uio_out = {out_kind, front_phase};
    assign uio_oe  = 8'h00;

    wire _unused = &{
        uio_in,
        rx0_active, rx1_active, rx2_active,
        aead_done,
        1'b0
    };

endmodule

`default_nettype wire
