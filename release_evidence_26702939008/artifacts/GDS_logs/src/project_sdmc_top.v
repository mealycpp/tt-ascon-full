`default_nettype none

`include "sdmc/sdmc_modes.vh"
`include "sdmc/sdmc_stream_defs.vh"

module tt_um_mealycpp_ascon_sdmc (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire clear = !ena;

    // Minimal SDMC bring-up wrapper.
    // ui_in[0]   = start pulse
    // ui_in[1]   = cfg_wr_en
    // ui_in[2]   = in_valid byte push
    // ui_in[6:3] = cfg address
    // ui_in[7]   = in_last
    // uio_in     = cfg/in byte data
    //
    // This wrapper is for SDMC GDS-visible smoke integration.
    // A UART/protocol bridge can replace this pin shim later.

    wire        start      = ui_in[0];
    wire        cfg_wr_en  = ui_in[1];
    wire        in_valid   = ui_in[2];
    wire [3:0]  addr       = ui_in[6:3];
    wire        in_last    = ui_in[7];

    wire [63:0] data64 = {8{uio_in}};

    wire        busy;
    wire        done;
    wire        error;
    wire        auth_ok;

    wire [3:0]  host_mode;
    wire [3:0]  program_id;

    wire        in_ready;
    wire [7:0]  out_byte;
    wire [3:0]  out_kind;
    wire        out_last;
    wire        out_valid;

    wire [15:0] in_count;
    wire [15:0] out_count;

    // Simple default ingress kind for smoke. Full host protocol should drive
    // explicit token kinds. This wrapper keeps the SDMC top buildable and
    // observable without committing to the UART command protocol yet.
    wire [3:0] in_kind =
        (host_mode == `SDMC_HOST_AEAD_ENC || host_mode == `SDMC_HOST_AEAD_DEC) ? `SDMC_TOK_KEY :
        (host_mode == `SDMC_HOST_CXOF || host_mode == `SDMC_HOST_CXOF_CHAIN) ? `SDMC_TOK_CS :
        `SDMC_TOK_MSG;

    sdmc_crypto_top #(
        .FIFO_DEPTH(4),
        .FIFO_AW(2)
    ) u_sdmc (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),

        .start(start),

        .cfg_wr_en(cfg_wr_en),
        .cfg_wr_addr(addr),
        .cfg_wr_data(data64),

        .in_byte(uio_in),
        .in_kind(in_kind),
        .in_last(in_last),
        .in_valid(in_valid),
        .in_ready(in_ready),

        .out_byte(out_byte),
        .out_kind(out_kind),
        .out_last(out_last),
        .out_valid(out_valid),
        .out_ready(1'b1),

        .busy(busy),
        .done(done),
        .error(error),
        .auth_ok(auth_ok),

        .host_mode(host_mode),
        .program_id(program_id),

        .in_count(in_count),
        .out_count(out_count)
    );

    assign uo_out[0] = busy;
    assign uo_out[1] = done;
    assign uo_out[2] = error;
    assign uo_out[3] = auth_ok;
    assign uo_out[4] = in_ready;
    assign uo_out[5] = out_valid;
    assign uo_out[6] = out_last;
    assign uo_out[7] = ^out_byte ^ ^out_kind ^ ^in_count ^ ^out_count;

    assign uio_out = out_byte;
    assign uio_oe  = {8{out_valid}};

    wire _unused = &{program_id, 1'b0};

endmodule

`default_nettype wire
