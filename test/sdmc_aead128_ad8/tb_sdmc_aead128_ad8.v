`timescale 1ns/1ps
`default_nettype none
`include "sdmc_stream_defs.vh"
module tb_sdmc_aead128_ad8;
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
wire [`SDMC_TOKEN_W-1:0] token4={1'b1,`SDMC_TOK_AD,4'd8,64'h3736353433323130};
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
reg [127:0] tag; reg [1:0] tag_idx;
sdmc_aead128_core dut(.clk(clk),.rst_n(rst_n),.clear(clear),.start(start),.is_decrypt(1'b0),.ad_len(16'd8),.data_len(16'd0),.in_token(in_token),.in_empty(in_empty),.in_pop(in_pop),.out_token(out_token),.out_push(out_push),.out_full(out_full),.busy(busy),.done(done),.error(error),.auth_ok(auth_ok));
task tick; begin @(negedge clk); end endtask
always @(negedge clk) if(!rst_n||clear) token_idx<=0; else if(in_pop) token_idx<=token_idx+1;
wire [3:0] kind=out_token[71:68]; wire [63:0] data=out_token[63:0];
always @(posedge clk) if(!rst_n||clear) begin tag<=0; tag_idx<=0; end else if(out_push) begin if(kind!==`SDMC_TOK_TAG) begin $display("FAIL bad tag kind"); $finish; end if(tag_idx==0) tag[63:0]<=data; else tag[127:64]<=data; tag_idx<=tag_idx+1; end
integer guard; initial begin $dumpfile("tb_sdmc_aead128_ad8.vcd"); $dumpvars(0,tb_sdmc_aead128_ad8); repeat(5) tick(); rst_n=1; repeat(2) tick(); start=1; tick(); start=0; guard=0; while(!done) begin tick(); guard=guard+1; if(guard>6000) begin $display("FAIL timeout"); $finish; end end tick(); if(error) begin $display("FAIL error"); $finish; end if(tag!==128'h9e93b4cc84631d2ceeeda99340595c86) begin $display("FAIL tag mismatch got=%h exp=%h",tag,128'h9e93b4cc84631d2ceeeda99340595c86); $finish; end $display("PASS sdmc_aead128_ad8"); $finish; end
endmodule
`default_nettype wire
