/*
 * Sequential ASCON round engine.
 *
 * One ASCON round is split into 4 short registered phases:
 *
 *   PH_A: pC + first S-box XOR layer
 *   PH_T: nonlinear AND terms
 *   PH_S: final S-box XOR layer
 *   PH_L: linear diffusion and output register
 *
 * No memories.
 * No FIFOs.
 * No arrays.
 * No wide dynamic muxes.
 * No variable barrel shifters.
 */

`default_nettype none

module ascon_round (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         start,
    input  wire [319:0] state_in,
    input  wire [7:0]   round_const,

    output wire [319:0] state_out,
    output reg          busy,
    output reg          done
);

    reg [319:0] state_out_r;
    assign state_out = state_out_r;

    wire [63:0] x0_in;
    wire [63:0] x1_in;
    wire [63:0] x2_in;
    wire [63:0] x3_in;
    wire [63:0] x4_in;

    assign x0_in = state_in[63:0];
    assign x1_in = state_in[127:64];
    assign x2_in = state_in[191:128];
    assign x3_in = state_in[255:192];
    assign x4_in = state_in[319:256];

    wire [63:0] x2_pc;
    assign x2_pc = {x2_in[63:8], x2_in[7:0] ^ round_const};

    reg [63:0] a0_r;
    reg [63:0] a1_r;
    reg [63:0] a2_r;
    reg [63:0] a3_r;
    reg [63:0] a4_r;

    reg [63:0] t0_r;
    reg [63:0] t1_r;
    reg [63:0] t2_r;
    reg [63:0] t3_r;
    reg [63:0] t4_r;

    reg [63:0] s0_r;
    reg [63:0] s1_r;
    reg [63:0] s2_r;
    reg [63:0] s3_r;
    reg [63:0] s4_r;

    wire [63:0] x0_l;
    wire [63:0] x1_l;
    wire [63:0] x2_l;
    wire [63:0] x3_l;
    wire [63:0] x4_l;

    assign x0_l = s0_r ^ {s0_r[18:0], s0_r[63:19]}
                       ^ {s0_r[27:0], s0_r[63:28]};

    assign x1_l = s1_r ^ {s1_r[60:0], s1_r[63:61]}
                       ^ {s1_r[38:0], s1_r[63:39]};

    assign x2_l = s2_r ^ {s2_r[0],    s2_r[63:1]}
                       ^ {s2_r[5:0],  s2_r[63:6]};

    assign x3_l = s3_r ^ {s3_r[9:0],  s3_r[63:10]}
                       ^ {s3_r[16:0], s3_r[63:17]};

    assign x4_l = s4_r ^ {s4_r[6:0],  s4_r[63:7]}
                       ^ {s4_r[40:0], s4_r[63:41]};

    localparam PH_IDLE = 3'd0;
    localparam PH_T    = 3'd1;
    localparam PH_S    = 3'd2;
    localparam PH_L    = 3'd3;

    reg [2:0] phase;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase       <= PH_IDLE;

            a0_r        <= 64'd0;
            a1_r        <= 64'd0;
            a2_r        <= 64'd0;
            a3_r        <= 64'd0;
            a4_r        <= 64'd0;

            t0_r        <= 64'd0;
            t1_r        <= 64'd0;
            t2_r        <= 64'd0;
            t3_r        <= 64'd0;
            t4_r        <= 64'd0;

            s0_r        <= 64'd0;
            s1_r        <= 64'd0;
            s2_r        <= 64'd0;
            s3_r        <= 64'd0;
            s4_r        <= 64'd0;

            state_out_r <= 320'd0;
            busy        <= 1'b0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;

            case (phase)

                PH_IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        a0_r  <= x0_in ^ x4_in;
                        a1_r  <= x1_in;
                        a2_r  <= x2_pc ^ x1_in;
                        a3_r  <= x3_in;
                        a4_r  <= x4_in ^ x3_in;

                        busy  <= 1'b1;
                        phase <= PH_T;
                    end
                end

                PH_T: begin
                    t0_r  <= (~a0_r) & a1_r;
                    t1_r  <= (~a1_r) & a2_r;
                    t2_r  <= (~a2_r) & a3_r;
                    t3_r  <= (~a3_r) & a4_r;
                    t4_r  <= (~a4_r) & a0_r;

                    phase <= PH_S;
                end

                PH_S: begin
                    s0_r <= (a0_r ^ t1_r) ^ (a4_r ^ t0_r);
                    s1_r <= (a1_r ^ t2_r) ^ (a0_r ^ t1_r);
                    s2_r <= ~(a2_r ^ t3_r);
                    s3_r <= (a3_r ^ t4_r) ^ (a2_r ^ t3_r);
                    s4_r <= (a4_r ^ t0_r);

                    phase <= PH_L;
                end

                PH_L: begin
                    state_out_r <= {x4_l, x3_l, x2_l, x1_l, x0_l};

                    busy        <= 1'b0;
                    done        <= 1'b1;
                    phase       <= PH_IDLE;
                end

                default: begin
                    phase <= PH_IDLE;
                    busy  <= 1'b0;
                    done  <= 1'b0;
                end

            endcase
        end
    end

endmodule

`default_nettype wire
