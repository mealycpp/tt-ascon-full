`default_nettype none

`include "sdmc_stream_defs.vh"

module sdmc_xof_chain_family_core (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    input  wire                     start,
    input  wire                     use_cxof,
    input  wire [15:0]              chain_count,
    input  wire [15:0]              msg_len,
    input  wire [15:0]              cs_len,
    input  wire [15:0]              out_len,

    input  wire [`SDMC_TOKEN_W-1:0] in_token,
    input  wire                     in_empty,
    output wire                     in_pop,

    output wire [`SDMC_TOKEN_W-1:0] out_token,
    output wire                     out_push,
    input  wire                     out_full,

    output reg                      busy,
    output reg                      done,
    output reg                      error
);

    localparam S_IDLE       = 3'd0;
    localparam S_START_PASS = 3'd1;
    localparam S_RUN_PASS   = 3'd2;
    localparam S_NEXT_PASS  = 3'd3;
    localparam S_DONE       = 3'd4;
    localparam S_ERR        = 3'd5;

    reg [2:0] state;

    reg [15:0] passes_left;
    reg        pass0_q;

    reg [63:0] digest0;
    reg [63:0] digest1;
    reg [63:0] digest2;
    reg [63:0] digest3;

    reg [1:0] capture_idx;
    reg [2:0] feed_idx;

    reg [`SDMC_TOKEN_W-1:0] cs_token_q;
    reg                     cs_token_seen;
    reg                     cs_feed_done;

    reg inner_start;

    wire inner_done;
    wire inner_busy;
    wire inner_error;

    wire [`SDMC_TOKEN_W-1:0] inner_in_token;
    wire inner_in_empty;
    wire inner_in_pop;

    wire [`SDMC_TOKEN_W-1:0] inner_out_token;
    wire inner_out_push;
    wire inner_out_full;

    wire final_pass = (passes_left == 16'd1);

    wire [63:0] feed_word =
        (feed_idx[1:0] == 2'd0) ? digest0 :
        (feed_idx[1:0] == 2'd1) ? digest1 :
        (feed_idx[1:0] == 2'd2) ? digest2 :
                                  digest3;

    wire [`SDMC_TOKEN_W-1:0] internal_msg_token =
        { (feed_idx == 3'd3), `SDMC_TOK_MSG, 4'd8, feed_word };

    wire feeding_cached_cs = (!pass0_q) && use_cxof && (cs_len != 16'd0) && (!cs_feed_done);

    assign inner_in_token = pass0_q ? in_token :
                            (feeding_cached_cs ? cs_token_q : internal_msg_token);

    assign inner_in_empty = pass0_q ? in_empty :
                            (feeding_cached_cs ? (!cs_token_seen) : (feed_idx >= 3'd4));

    assign in_pop = pass0_q ? inner_in_pop : 1'b0;

    assign inner_out_full = final_pass ? out_full : 1'b0;
    assign out_token      = final_pass ? inner_out_token : {`SDMC_TOKEN_W{1'b0}};
    assign out_push       = final_pass ? inner_out_push  : 1'b0;

    sdmc_xof_family_core u_single (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear       (clear),

        .start       (inner_start),
        .use_cxof    (use_cxof),
        .chain_count (16'd1),
        .cs_len      (cs_len),
        .out_len     (final_pass ? out_len : 16'd32),
        .msg_len     (pass0_q ? msg_len : 16'd32),

        .in_token    (inner_in_token),
        .in_empty    (inner_in_empty),
        .in_pop      (inner_in_pop),

        .out_token   (inner_out_token),
        .out_push    (inner_out_push),
        .out_full    (inner_out_full),

        .busy        (inner_busy),
        .done        (inner_done),
        .error       (inner_error)
    );

    wire _unused = &{use_cxof, cs_len[0], inner_busy, 1'b0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            passes_left <= 16'd0;
            pass0_q     <= 1'b1;
            digest0     <= 64'd0;
            digest1     <= 64'd0;
            digest2     <= 64'd0;
            digest3     <= 64'd0;
            capture_idx <= 2'd0;
            feed_idx    <= 3'd0;
            cs_token_q    <= {`SDMC_TOKEN_W{1'b0}};
            cs_token_seen <= 1'b0;
            cs_feed_done  <= 1'b0;
            inner_start    <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
            error       <= 1'b0;
        end else if (clear) begin
            state       <= S_IDLE;
            passes_left <= 16'd0;
            pass0_q     <= 1'b1;
            digest0     <= 64'd0;
            digest1     <= 64'd0;
            digest2     <= 64'd0;
            digest3     <= 64'd0;
            capture_idx <= 2'd0;
            feed_idx    <= 3'd0;
            cs_token_q    <= {`SDMC_TOKEN_W{1'b0}};
            cs_token_seen <= 1'b0;
            cs_feed_done  <= 1'b0;
            inner_start    <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
            error       <= 1'b0;
        end else begin
            inner_start <= 1'b0;
            done        <= 1'b0;

            if (pass0_q && inner_in_pop && (in_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB] == `SDMC_TOK_CS)) begin
                cs_token_q    <= in_token;
                cs_token_seen <= 1'b1;
            end

            if ((!pass0_q) && inner_in_pop) begin
                if (feeding_cached_cs) begin
                    cs_feed_done <= 1'b1;
                end else begin
                    feed_idx <= feed_idx + 3'd1;
                end
            end

            if ((!final_pass) && inner_out_push) begin
                case (capture_idx)
                    2'd0: digest0 <= inner_out_token[63:0];
                    2'd1: digest1 <= inner_out_token[63:0];
                    2'd2: digest2 <= inner_out_token[63:0];
                    2'd3: digest3 <= inner_out_token[63:0];
                    default: ;
                endcase
                capture_idx <= capture_idx + 2'd1;
            end

            case (state)
                S_IDLE: begin
                    busy  <= 1'b0;
                    error <= 1'b0;

                    if (start) begin
                        if (out_len == 16'd0) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            busy        <= 1'b1;
                            pass0_q     <= 1'b1;
                            passes_left <= (chain_count == 16'd0) ? 16'd1 : chain_count;
                            capture_idx   <= 2'd0;
                            feed_idx      <= 3'd0;
                            cs_token_q    <= {`SDMC_TOKEN_W{1'b0}};
                            cs_token_seen <= (cs_len == 16'd0);
                            cs_feed_done  <= (cs_len == 16'd0);
                            state         <= S_START_PASS;
                        end
                    end
                end

                S_START_PASS: begin
                    inner_start <= 1'b1;
                    state       <= S_RUN_PASS;
                end

                S_RUN_PASS: begin
                    if (inner_done) begin
                        if (inner_error) begin
                            error <= 1'b1;
                            state <= S_ERR;
                        end else if (passes_left == 16'd1) begin
                            state <= S_DONE;
                        end else begin
                            state <= S_NEXT_PASS;
                        end
                    end
                end

                S_NEXT_PASS: begin
                    passes_left <= passes_left - 16'd1;
                    pass0_q     <= 1'b0;
                    feed_idx     <= 3'd0;
                    capture_idx  <= 2'd0;
                    cs_feed_done <= (cs_len == 16'd0);
                    state        <= S_START_PASS;
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                S_ERR: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    busy  <= 1'b0;
                    error <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
