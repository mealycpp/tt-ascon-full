/*
 * tt-ascon-full — ASCON Integrated Crypto Processor
 * Tiny Tapeout TTGF26a — GF180 PDK
 *
 * Top-level wiring (Phase 4 real top, no stub):
 *
 *   ui_in[0..2]  -> uart_bridge RX (UART0/1/2)
 *   ui_in[3]     -> ext_entropy_in (captured to register, unused until TRNG)
 *   uo_out[0..2] <- uart_bridge TX (UART0/1/2)
 *   uo_out[3]    <- mode_controller busy
 *   uo_out[4]    <- mode_controller done
 *   uo_out[5]    <- protocol_parser frame_error (sticky)
 *   uo_out[6]    <- bg_lag (tied 0 until Phase 5 scheduler)
 *   uo_out[7]    <- heartbeat (24-bit divider toggle)
 *   uio_*        unused, driven 0 with oe=0
 *
 * Internal composition (SDMC contract intact: ONE ascon_permutation):
 *
 *   uart_bridge   - 3x UART RX/TX, byte FIFOs, packers/unpackers,
 *                   exposes 3 packed RX streams + accepts 3 ready signals
 *                   (lane_router owns the mux now)
 *   protocol_parser
 *                 - decodes UART0 14-byte control frame, emits metadata
 *                   + start pulse
 *   lane_router   - 3:1 RX word mux + lane scheduling per active mode
 *   mode_controller
 *                 - SDMC dispatcher; instantiates the one shared
 *                   ascon_permutation and all crypto controllers
 *
 * No TRNG, DRBG, or scheduler yet. Those land in later phases.
 * No new architectural modules added in this step. Pure wiring.
 */
`default_nettype none

module tt_um_mealycpp_ascon_full (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // --------------------------------------------------------------
    // Pin breakout
    // --------------------------------------------------------------
    wire uart0_rx       = ui_in[0];
    wire uart1_rx       = ui_in[1];
    wire uart2_rx       = ui_in[2];
    wire ext_entropy_in = ui_in[3];

    wire uart0_tx;
    wire uart1_tx;
    wire uart2_tx;

    // Baud divider — 50 MHz / 230400 baud ≈ 217 cycles/bit.
    // Hardcoded for the silicon target; sims override by driving lower
    // through ui_in if we ever expose it (we don't here).
    wire [15:0] baud_div = 16'd217;

    // --------------------------------------------------------------
    // uart_bridge: 3x RX (FIFO+packer) + 3x TX (FIFO+unpacker share)
    // --------------------------------------------------------------
    wire [2:0]  flush_lanes;
    wire [2:0]  flush_ready_lanes;

    // UART0 parser byte tap
    wire [7:0]  uart0_byte_w;
    wire        uart0_byte_valid_w;
    wire        uart0_byte_ready_w;

    wire [63:0] pack_word_0, pack_word_1, pack_word_2;
    wire [3:0]  pack_bytes_0, pack_bytes_1, pack_bytes_2;
    wire        pack_valid_0, pack_valid_1, pack_valid_2;
    wire        pack_ready_0, pack_ready_1, pack_ready_2;

    wire [1:0]  tx_sel;
    wire [63:0] sdmc_out_block;
    wire [3:0]  sdmc_out_byte_count;
    wire        sdmc_out_valid;
    wire        sdmc_out_ready;
    wire        sdmc_out_last_unused;

    wire [2:0]  rx_fifo_empty;
    wire [2:0]  rx_fifo_full;
    wire [2:0]  tx_fifo_empty;
    wire [2:0]  tx_fifo_full;

    uart_bridge #(.FIFO_DEPTH(8), .FIFO_AW(3)) u_bridge (
        .clk(clk), .rst_n(rst_n),
        .baud_div(baud_div),
        .uart0_rx(uart0_rx), .uart1_rx(uart1_rx), .uart2_rx(uart2_rx),
        .uart0_tx(uart0_tx), .uart1_tx(uart1_tx), .uart2_tx(uart2_tx),
        .uart0_byte(uart0_byte_w),
        .uart0_byte_valid(uart0_byte_valid_w),
        .uart0_byte_ready(uart0_byte_ready_w),
        .flush(flush_lanes), .flush_ready(flush_ready_lanes),
        .pack_word_0(pack_word_0), .pack_bytes_0(pack_bytes_0),
        .pack_valid_0(pack_valid_0), .pack_ready_0(pack_ready_0),
        .pack_word_1(pack_word_1), .pack_bytes_1(pack_bytes_1),
        .pack_valid_1(pack_valid_1), .pack_ready_1(pack_ready_1),
        .pack_word_2(pack_word_2), .pack_bytes_2(pack_bytes_2),
        .pack_valid_2(pack_valid_2), .pack_ready_2(pack_ready_2),
        .tx_sel(tx_sel),
        .sdmc_out_block(sdmc_out_block),
        .sdmc_out_byte_count(sdmc_out_byte_count),
        .sdmc_out_valid(sdmc_out_valid),
        .sdmc_out_ready(sdmc_out_ready),
        .rx_fifo_empty(rx_fifo_empty), .rx_fifo_full(rx_fifo_full),
        .tx_fifo_empty(tx_fifo_empty), .tx_fifo_full(tx_fifo_full)
    );

    // --------------------------------------------------------------
    // protocol_parser: decode UART0 14-byte control frame.
    //
    // UART0 is byte-level control only. uart_bridge exposes a parser
    // byte stream from its UART0 FIFO, and protocol_parser consumes it
    // with ready/valid. UART0 is not used as a crypto payload lane.
    // --------------------------------------------------------------
    wire [2:0]  mode_sel_w;
    wire        is_decrypt_w;
    wire        chain_enable_w;
    wire        chain_debug_w;
    wire [15:0] ad_total_bytes_w;
    wire [15:0] data_total_bytes_w;
    wire [15:0] out_length_w;
    wire [15:0] chain_count_w;
    wire [15:0] cs_total_bits_w;
    wire        frame_valid_w;
    wire        frame_error_w;
    wire        start_pulse_w;


    protocol_parser u_parser (
        .clk(clk), .rst_n(rst_n),
        // UART0 byte tap from uart_bridge feeds the parser
        .in_byte(uart0_byte_w),
        .in_byte_valid(uart0_byte_valid_w),
        .in_byte_ready(uart0_byte_ready_w),
        .mode_sel(mode_sel_w),
        .is_decrypt(is_decrypt_w),
        .chain_enable(chain_enable_w),
        .chain_debug(chain_debug_w),
        .ad_total_bytes(ad_total_bytes_w),
        .data_total_bytes(data_total_bytes_w),
        .out_length(out_length_w),
        .chain_count(chain_count_w),
        .cs_total_bits(cs_total_bits_w),
        .frame_valid(frame_valid_w),
        .frame_error(frame_error_w),
        .start(start_pulse_w)
    );

    // --------------------------------------------------------------
    // lane_router: 3:1 mux + lane scheduling per mode
    // --------------------------------------------------------------
    wire [1:0]  phase_sel_w;
    wire [63:0] sdmc_in_word_w;
    wire [3:0]  sdmc_in_word_bytes_w;
    wire        sdmc_in_word_valid_w;
    wire        sdmc_in_word_ready_w;
    wire        sdmc_done_w;
    wire        router_busy_w;

    lane_router u_router (
        .clk(clk), .rst_n(rst_n),
        .mode(mode_sel_w),
        .is_decrypt(is_decrypt_w),
        .ad_total_bytes(ad_total_bytes_w),
        .data_total_bytes(data_total_bytes_w),
        .cs_total_bits(cs_total_bits_w),
        .start_pulse(start_pulse_w),
        .sdmc_done(sdmc_done_w),
        .sdmc_in_word_ready(sdmc_in_word_ready_w),
        .pack_word_0(pack_word_0), .pack_bytes_0(pack_bytes_0), .pack_valid_0(pack_valid_0),
        .pack_word_1(pack_word_1), .pack_bytes_1(pack_bytes_1), .pack_valid_1(pack_valid_1),
        .pack_word_2(pack_word_2), .pack_bytes_2(pack_bytes_2), .pack_valid_2(pack_valid_2),
        .phase_sel(phase_sel_w),
        .sdmc_in_word(sdmc_in_word_w),
        .sdmc_in_word_bytes(sdmc_in_word_bytes_w),
        .sdmc_in_word_valid(sdmc_in_word_valid_w),
        .router_busy(router_busy_w)
    );

    // Bridge pack_ready demux: only the selected lane gets ready.
    assign pack_ready_0 = 1'b0;
    assign pack_ready_1 = (phase_sel_w == 2'd1) && sdmc_in_word_ready_w;
    assign pack_ready_2 = (phase_sel_w == 2'd2) && sdmc_in_word_ready_w;

    // Flush lanes: tie off for now (parser doesn't drive flush yet).
    assign flush_lanes = 3'b000;

    // --------------------------------------------------------------
    // mode_controller: SDMC dispatcher with ONE shared ascon_permutation
    // --------------------------------------------------------------
    wire        mc_busy_w;
    wire        mc_auth_ok_w;

    mode_controller u_mc (
        .clk(clk), .rst_n(rst_n),
        .mode_sel(mode_sel_w),
        .start(start_pulse_w),
        .reset_engine(1'b0),
        .cs_total_bits(cs_total_bits_w),
        .msg_total_bytes(data_total_bytes_w),
        .out_length(out_length_w),
        .chain_enable(chain_enable_w),
        .chain_count(chain_count_w),
        .chain_debug(chain_debug_w),
        .is_decrypt(is_decrypt_w),
        .ad_total_bytes(ad_total_bytes_w),
        .data_total_bytes(data_total_bytes_w),
        .in_word(sdmc_in_word_w),
        .in_word_bytes(sdmc_in_word_bytes_w),
        .in_word_last(1'b0),               // unused by controllers (FSM-internal)
        .in_word_is_cs(phase_sel_w == 2'd1), // CS phase only when on UART1 for CXOF
        .in_word_valid(sdmc_in_word_valid_w),
        .in_word_ready(sdmc_in_word_ready_w),
        .out_block(sdmc_out_block),
        .out_valid(sdmc_out_valid),
        .out_last(sdmc_out_last_unused),                       // unused at top level
        .out_byte_count(sdmc_out_byte_count),
        .auth_ok(mc_auth_ok_w),
        .busy(mc_busy_w),
        .done(sdmc_done_w)
    );

    // mode_controller output flows into bridge unpacker (sdmc_out_ready
    // comes back; everything else already wired above).
    // TX always routes to UART2 by locked policy.
    assign tx_sel = 2'd2;

    // --------------------------------------------------------------
    // Status outputs
    // --------------------------------------------------------------

    // Sticky frame_error so a brief pulse is observable on the pin
    reg error_sticky;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) error_sticky <= 1'b0;
        else if (frame_error_w) error_sticky <= 1'b1;
        else if (start_pulse_w) error_sticky <= 1'b0;
    end

    // Heartbeat: ~50MHz / 2^24 ≈ 3 Hz toggle on bit 23
    reg [23:0] hb_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hb_cnt <= 24'd0;
        else        hb_cnt <= hb_cnt + 24'd1;
    end

    // Capture ext_entropy_in for future TRNG (currently unused but registered
    // so the synthesizer doesn't optimize the input away)
    reg ext_entropy_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ext_entropy_reg <= 1'b0;
        else        ext_entropy_reg <= ext_entropy_in;
    end

    assign uo_out[0] = uart0_tx;
    assign uo_out[1] = uart1_tx;
    assign uo_out[2] = uart2_tx;
    assign uo_out[3] = mc_busy_w;
    assign uo_out[4] = sdmc_done_w;
    assign uo_out[5] = error_sticky;
    assign uo_out[6] = 1'b0;             // bg_lag, tied until scheduler
    assign uo_out[7] = hb_cnt[23];

    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    // Prevent unused warnings
    wire _unused = &{ena, uio_in, ext_entropy_reg, mc_auth_ok_w,
                     router_busy_w, frame_valid_w,
                     rx_fifo_empty, rx_fifo_full, tx_fifo_empty, tx_fifo_full,
                     flush_ready_lanes, 1'b0};

endmodule
