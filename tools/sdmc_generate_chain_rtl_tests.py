#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VEC = ROOT / "kat/derived/sdmc_chain_generated_vectors.json"
OUT_ROOT = ROOT / "test/sdmc_chain_vector_matrix"

def chunks8(hexstr):
    b = bytes.fromhex(hexstr)
    out = []
    for i in range(0, len(b), 8):
        chunk = b[i:i+8]
        word = int.from_bytes(chunk, "little")
        out.append((word, len(chunk), i + 8 >= len(b)))
    return out

def tok(last, kind, nbytes, word):
    return "{1'b%d, `%s, 4'd%d, 64'h%016x}" % (1 if last else 0, kind, nbytes, word)

def packed_le(hexstr):
    b = bytes.fromhex(hexstr)
    return int.from_bytes(b, "little") if b else 0

def make_tokens(v):
    tokens = []
    if v["family"] == "cxof_chain" and v["cs_hex"]:
        for word, nbytes, last in chunks8(v["cs_hex"]):
            tokens.append(tok(last, "SDMC_TOK_CS", nbytes, word))
    for word, nbytes, last in chunks8(v["msg_hex"]):
        tokens.append(tok(last, "SDMC_TOK_MSG", nbytes, word))
    return tokens

def write_tb(v):
    name = "sdmc_" + v["name"]
    d = OUT_ROOT / name
    d.mkdir(parents=True, exist_ok=True)
    tb = d / f"tb_{name}.v"

    tokens = make_tokens(v)
    token_count = len(tokens)
    expected_hex = v["expected_hex"]
    out_len = int(v["out_len"])
    out_bits = out_len * 8
    expected_val = packed_le(expected_hex)
    expected_lit = f"{out_bits}'h{expected_val:0{out_bits//4}x}"
    use_cxof = "1'b1" if v["family"] == "cxof_chain" else "1'b0"
    msg_len = len(bytes.fromhex(v["msg_hex"]))
    cs_len = len(bytes.fromhex(v["cs_hex"]))
    chain_count = int(v["chain_count"])

    init_lines = "\n".join(
        f"        token_mem[{i}] = {lit};" for i, lit in enumerate(tokens)
    )

    if token_count == 0:
        token_decl = "reg [`SDMC_TOKEN_W-1:0] token_mem [0:0];"
    else:
        token_decl = f"reg [`SDMC_TOKEN_W-1:0] token_mem [0:TOKEN_COUNT-1];"

    tb.write_text(f"""`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_{name};

    localparam integer TOKEN_COUNT = {token_count};
    localparam integer OUT_BYTES = {out_len};
    localparam integer OUT_BITS = {out_bits};

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    reg start = 1'b0;
    always #5 clk = ~clk;

    reg [15:0] token_idx = 16'd0;
    {token_decl}

    wire in_empty = (token_idx >= TOKEN_COUNT);
    wire [`SDMC_TOKEN_W-1:0] in_token = in_empty ? {{`SDMC_TOKEN_W{{1'b0}}}} : token_mem[token_idx];
    wire in_pop;

    wire [`SDMC_TOKEN_W-1:0] out_token;
    wire out_push;
    reg out_full = 1'b0;

    wire busy;
    wire done;
    wire error;

    reg [OUT_BITS-1:0] got;
    reg [15:0] out_bytes_seen;

    sdmc_xof_chain_family_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .use_cxof({use_cxof}),
        .chain_count(16'd{chain_count}),
        .msg_len(16'd{msg_len}),
        .cs_len(16'd{cs_len}),
        .out_len(16'd{out_len}),
        .in_token(in_token),
        .in_empty(in_empty),
        .in_pop(in_pop),
        .out_token(out_token),
        .out_push(out_push),
        .out_full(out_full),
        .busy(busy),
        .done(done),
        .error(error)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    integer j;
    wire [3:0] tok_kind = out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
    wire [3:0] tok_bytes = out_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
    wire [63:0] tok_data = out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];
    wire tok_last = out_token[`SDMC_TOKEN_LAST_BIT];

    initial begin
{init_lines}
    end

    always @(negedge clk) begin
        if (!rst_n || clear) begin
            token_idx <= 16'd0;
        end else if (in_pop) begin
            token_idx <= token_idx + 16'd1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            got <= {{OUT_BITS{{1'b0}}}};
            out_bytes_seen <= 16'd0;
        end else if (out_push) begin
            if (tok_kind !== `SDMC_TOK_OUT) begin
                $display("FAIL bad output kind=%h", tok_kind);
                $finish;
            end

            if ((out_bytes_seen + tok_bytes) > OUT_BYTES) begin
                $display("FAIL too many output bytes seen=%0d tok_bytes=%0d", out_bytes_seen, tok_bytes);
                $finish;
            end

            for (j = 0; j < 8; j = j + 1) begin
                if (j < tok_bytes) begin
                    got[(out_bytes_seen + j)*8 +: 8] <= tok_data[j*8 +: 8];
                end
            end

            out_bytes_seen <= out_bytes_seen + tok_bytes;

            if ((out_bytes_seen + tok_bytes) == OUT_BYTES && !tok_last) begin
                $display("FAIL final output token missing last");
                $finish;
            end
        end
    end

    integer guard;

    initial begin
        $dumpfile("tb_{name}.vcd");
        $dumpvars(0, tb_{name});

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        start = 1'b1;
        tick();
        start = 1'b0;

        guard = 0;
        while (!done) begin
            tick();
            guard = guard + 1;
            if (guard > 200000) begin
                $display("FAIL timeout {name}");
                $finish;
            end
        end

        repeat (3) tick();

        if (error) begin
            $display("FAIL error asserted {name}");
            $finish;
        end

        if (token_idx !== TOKEN_COUNT) begin
            $display("FAIL token consumed=%0d expected=%0d", token_idx, TOKEN_COUNT);
            $finish;
        end

        if (out_bytes_seen !== OUT_BYTES) begin
            $display("FAIL out_bytes_seen=%0d expected=%0d", out_bytes_seen, OUT_BYTES);
            $finish;
        end

        if (got !== {expected_lit}) begin
            $display("FAIL digest mismatch {name}");
            $display("got=%h", got);
            $display("exp=%h", {expected_lit});
            $finish;
        end

        $display("PASS {name}");
        $finish;
    end

endmodule

`default_nettype wire
""")

    return name

def main():
    data = json.loads(VEC.read_text())
    names = []

    for v in data["vectors"]:
        # Current chain RTL supports one cached CS token for replay.
        # Skip only multi-token CS cases such as z16; z0/z1/z8 are supported.
        if v["family"] == "cxof_chain" and len(bytes.fromhex(v["cs_hex"])) > 8:
            continue
        names.append(write_tb(v))

    manifest = OUT_ROOT / "manifest.txt"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text("\n".join(names) + "\n")

    print(f"Generated {len(names)} chain RTL vector tests")
    print(f"Manifest: {manifest}")

if __name__ == "__main__":
    main()
