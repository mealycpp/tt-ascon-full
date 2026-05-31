`default_nettype none

module sdmc_uop_sequencer64 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       clear,

    input  wire       start,
    input  wire [1:0] program_id,

    output reg        cmd_valid,
    input  wire       cmd_ready,
    output wire [3:0] cmd_op,
    output wire [3:0] cmd_dst,
    output wire [3:0] cmd_src_a,
    output wire [3:0] cmd_src_b,
    output wire [3:0] cmd_n,
    output wire       cmd_writeback,

    input  wire       exec_done,

    output reg        busy,
    output reg        done
);

    localparam OP_ZERO     = 4'd0;
    localparam OP_PASS_A   = 4'd1;
    localparam OP_XOR      = 4'd2;
    localparam OP_MASK_N   = 4'd3;
    localparam OP_LOAD_PAD = 4'd5;
    localparam OP_DEC_KEEP = 4'd6;
    localparam OP_XOR_KEEP = 4'd7;

    localparam S_IDLE  = 3'd0;
    localparam S_ISSUE = 3'd1;
    localparam S_WAIT  = 3'd2;
    localparam S_DONE  = 3'd3;

    reg [2:0] state;
    reg [1:0] program_id_r;
    reg [3:0] pc;
    reg       last_r;

    reg [21:0] instr_r;

    assign cmd_n         = instr_r[3:0];
    assign cmd_src_b     = instr_r[7:4];
    assign cmd_src_a     = instr_r[11:8];
    assign cmd_dst       = instr_r[15:12];
    assign cmd_op        = instr_r[19:16];
    assign cmd_writeback = instr_r[20];

    function [21:0] make_instr;
        input       last;
        input       wb;
        input [3:0] op;
        input [3:0] dst;
        input [3:0] src_a;
        input [3:0] src_b;
        input [3:0] n;
        begin
            make_instr = {last, wb, op, dst, src_a, src_b, n};
        end
    endfunction

    function [21:0] rom_instr;
        input [1:0] pid;
        input [3:0] addr;
        begin
            case (pid)
                2'd0: begin
                    case (addr)
                        4'd0: rom_instr = make_instr(1'b0, 1'b1, OP_XOR,      4'd3, 4'd1, 4'd2, 4'd0);
                        4'd1: rom_instr = make_instr(1'b0, 1'b1, OP_MASK_N,   4'd4, 4'd3, 4'd0, 4'd3);
                        4'd2: rom_instr = make_instr(1'b1, 1'b1, OP_DEC_KEEP, 4'd0, 4'd1, 4'd0, 4'd3);
                        default: rom_instr = make_instr(1'b1, 1'b0, OP_ZERO, 4'd0, 4'd0, 4'd0, 4'd0);
                    endcase
                end

                2'd1: begin
                    case (addr)
                        4'd0: rom_instr = make_instr(1'b0, 1'b1, OP_LOAD_PAD, 4'd3, 4'd1, 4'd0, 4'd3);
                        4'd1: rom_instr = make_instr(1'b0, 1'b1, OP_XOR_KEEP, 4'd4, 4'd3, 4'd2, 4'd0);
                        4'd2: rom_instr = make_instr(1'b1, 1'b1, OP_PASS_A,   4'd0, 4'd4, 4'd0, 4'd0);
                        default: rom_instr = make_instr(1'b1, 1'b0, OP_ZERO, 4'd0, 4'd0, 4'd0, 4'd0);
                    endcase
                end

                default: begin
                    rom_instr = make_instr(1'b1, 1'b0, OP_ZERO, 4'd0, 4'd0, 4'd0, 4'd0);
                end
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            program_id_r <= 2'd0;
            pc           <= 4'd0;
            instr_r      <= 22'd0;
            last_r       <= 1'b0;
            cmd_valid    <= 1'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
        end else if (clear) begin
            state        <= S_IDLE;
            program_id_r <= 2'd0;
            pc           <= 4'd0;
            instr_r      <= 22'd0;
            last_r       <= 1'b0;
            cmd_valid    <= 1'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    cmd_valid <= 1'b0;
                    busy      <= 1'b0;
                    if (start) begin
                        program_id_r <= program_id;
                        pc           <= 4'd0;
                        instr_r      <= rom_instr(program_id, 4'd0);
                        last_r       <= 1'b0;
                        busy         <= 1'b1;
                        state        <= S_ISSUE;
                    end
                end

                S_ISSUE: begin
                    cmd_valid <= 1'b1;
                    if (cmd_ready) begin
                        state <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    cmd_valid <= 1'b0;
                    if (exec_done) begin
                        if (instr_r[21]) begin
                            state <= S_DONE;
                        end else begin
                            pc      <= pc + 4'd1;
                            instr_r <= rom_instr(program_id_r, pc + 4'd1);
                            last_r  <= 1'b0;
                            state   <= S_ISSUE;
                        end
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state     <= S_IDLE;
                    busy      <= 1'b0;
                    cmd_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
