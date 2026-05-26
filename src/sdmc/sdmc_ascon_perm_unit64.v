`default_nettype none

module sdmc_ascon_perm_unit64 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire        host_wr_en,
    input  wire [2:0]  host_wr_lane,
    input  wire [63:0] host_wr_data,

    input  wire        host_rd_en,
    input  wire [2:0]  host_rd_lane,
    output reg  [63:0] host_rd_data,
    output reg         host_rd_valid,

    input  wire        start,
    input  wire [3:0]  rounds,

    output wire        host_ready,
    output reg         busy,
    output reg         done,

    output wire [63:0] x0,
    output wire [63:0] x1,
    output wire [63:0] x2,
    output wire [63:0] x3,
    output wire [63:0] x4
);

    reg [63:0] x0_r;
    reg [63:0] x1_r;
    reg [63:0] x2_r;
    reg [63:0] x3_r;
    reg [63:0] x4_r;

    assign x0 = x0_r;
    assign x1 = x1_r;
    assign x2 = x2_r;
    assign x3 = x3_r;
    assign x4 = x4_r;

    assign host_ready = !busy;

    reg          perm_start;
    reg  [3:0]   perm_rounds;
    reg  [319:0] perm_state_in;
    wire [319:0] perm_state_out;
    wire         perm_busy;
    wire         perm_done;

    ascon_permutation u_perm (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (perm_start),
        .num_rounds (perm_rounds),
        .state_in   (perm_state_in),
        .state_out  (perm_state_out),
        .busy       (perm_busy),
        .done       (perm_done)
    );

    wire _unused = &{perm_busy, 1'b0};

    function [63:0] select_lane;
        input [2:0] lane;
        begin
            case (lane)
                3'd0: select_lane = x0_r;
                3'd1: select_lane = x1_r;
                3'd2: select_lane = x2_r;
                3'd3: select_lane = x3_r;
                3'd4: select_lane = x4_r;
                default: select_lane = 64'd0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x0_r          <= 64'd0;
            x1_r          <= 64'd0;
            x2_r          <= 64'd0;
            x3_r          <= 64'd0;
            x4_r          <= 64'd0;
            host_rd_data  <= 64'd0;
            host_rd_valid <= 1'b0;
            perm_start    <= 1'b0;
            perm_rounds   <= 4'd12;
            perm_state_in <= 320'd0;
            busy          <= 1'b0;
            done          <= 1'b0;
        end else if (clear) begin
            x0_r          <= 64'd0;
            x1_r          <= 64'd0;
            x2_r          <= 64'd0;
            x3_r          <= 64'd0;
            x4_r          <= 64'd0;
            host_rd_data  <= 64'd0;
            host_rd_valid <= 1'b0;
            perm_start    <= 1'b0;
            perm_rounds   <= 4'd12;
            perm_state_in <= 320'd0;
            busy          <= 1'b0;
            done          <= 1'b0;
        end else begin
            done          <= 1'b0;
            host_rd_valid <= 1'b0;
            perm_start    <= 1'b0;

            if (!busy) begin
                if (host_wr_en) begin
                    case (host_wr_lane)
                        3'd0: x0_r <= host_wr_data;
                        3'd1: x1_r <= host_wr_data;
                        3'd2: x2_r <= host_wr_data;
                        3'd3: x3_r <= host_wr_data;
                        3'd4: x4_r <= host_wr_data;
                        default: ;
                    endcase
                end

                if (host_rd_en) begin
                    host_rd_data  <= select_lane(host_rd_lane);
                    host_rd_valid <= 1'b1;
                end

                if (start) begin
                    perm_state_in <= {x4_r, x3_r, x2_r, x1_r, x0_r};
                    perm_rounds   <= (rounds == 4'd0) ? 4'd12 : rounds;
                    perm_start    <= 1'b1;
                    busy          <= 1'b1;
                end
            end else begin
                if (perm_done) begin
                    x0_r <= perm_state_out[63:0];
                    x1_r <= perm_state_out[127:64];
                    x2_r <= perm_state_out[191:128];
                    x3_r <= perm_state_out[255:192];
                    x4_r <= perm_state_out[319:256];

                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
