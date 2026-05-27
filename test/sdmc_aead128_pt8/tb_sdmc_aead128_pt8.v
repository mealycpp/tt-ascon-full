`timescale 1ns/1ps
`default_nettype none
`include "sdmc_stream_defs.vh"
module tb_sdmc_aead128_pt8;
reg clk = 1'b0;
reg rst_n = 1'b0;
reg clear = 1'b0;
reg start = 1'b0;
always #5 clk = ~clk;
reg [2:0] token_idx=0;
wire [`SDMC_TOKEN_W-1:0] token0={1'b0,`SDMC_TOK_KEY,4'd8,64'h0706_0504_0302_0100};
wire [`SDMC_TOKEN_W-1:0] token1={1'b1,`SDMC_TOK_KEY,4'd8,64'h0f0e_0d0c_0b0a_0908};
wire [`SDMC_TOKEN_W-1:0] token2={1'b0,`SDMC_TOK_NONCE,4'd8,64'h1716_1514_1312_1110};
wire [`SDMC_TOKEN_W-1:0] token3={1'b1,`SDMC_TOK_NONCE,4'd8,64'h1f1e_1d1c_1b1a_1918};
wire [`SDMC_TOKEN_W-1:0] token4={1'b1,`SDMC_TOK_MSG,4'd8,64'h2726252423222120};
wire [`SDMC_TOKEN_W-1:0] in_token=(token_idx==0)?token0:(token_idx==1)?token1:(token_idx==2)?token2:(token_idx==3)?token3:token4;
wire in_empty = (token_idx >= 5);
wire in_pop;
wire out_push;
wire busy;
wire done;
wire error;
wire auth_ok;
wire [`SDMC_TOKEN_W-1:0] out_token;
reg out_full = 1'b0;
reg [191:0] enc_out; reg [1:0] out_idx;
sdmc_aead128_core dut(.clk(clk),.rst_n(rst_n),.clear(clear),.start(start),.is_decrypt(1'b0),.ad_len(16'd0),.data_len(16'd8),.in_token(in_token),.in_empty(in_empty),.in_pop(in_pop),.out_token(out_token),.out_push(out_push),.out_full(out_full),.busy(busy),.done(done),.error(error),.auth_ok(auth_ok));
task tick; begin @(negedge clk); end endtask
always @(negedge clk) if(!rst_n||clear) token_idx<=0; else if(in_pop) token_idx<=token_idx+1;
wire [3:0] kind=out_token[71:68]; wire [3:0] bytes=out_token[67:64]; wire [63:0] data=out_token[63:0];
always @(posedge clk) if(!rst_n||clear) begin enc_out<=0; out_idx<=0; end else if(out_push) begin if(out_idx==0) begin if(kind!==`SDMC_TOK_OUT||bytes!==4'd8) begin $display("FAIL bad ct token"); $finish; end enc_out[63:0]<=data; end else if(out_idx==1) begin if(kind!==`SDMC_TOK_TAG) begin $display("FAIL bad tag0"); $finish; end enc_out[127:64]<=data; end else begin if(kind!==`SDMC_TOK_TAG) begin $display("FAIL bad tag1"); $finish; end enc_out[191:128]<=data; end out_idx<=out_idx+1; end
integer guard; initial begin $dumpfile("tb_sdmc_aead128_pt8.vcd"); $dumpvars(0,tb_sdmc_aead128_pt8); repeat(5) tick(); rst_n=1; repeat(2) tick(); start=1; tick(); start=0; guard=0; while(!done) begin tick(); guard=guard+1; if(guard>6000) begin $display("FAIL timeout"); $finish; end end tick(); if(error) begin $display("FAIL error"); $finish; end if(enc_out!==192'h273c379566ed91dda382b7336bef55e4eac56c24eedec3e8) begin $display("FAIL enc mismatch got=%h exp=%h",enc_out,192'h273c379566ed91dda382b7336bef55e4eac56c24eedec3e8); $finish; end $display("PASS sdmc_aead128_pt8"); $finish; end
endmodule
`default_nettype wire
