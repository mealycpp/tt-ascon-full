#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KAT = ROOT / "kat/official/ascon-c/asconaead128_LWC_AEAD_KAT_128_128.txt"
OUT_ROOT = ROOT / "test/sdmc_aead128_official_matrix"

TARGET_PAIRS = [
    (0, 0),
    (1, 0), (7, 0), (8, 0), (9, 0), (15, 0), (16, 0), (17, 0), (31, 0), (32, 0),
    (0, 1), (0, 7), (0, 8), (0, 9), (0, 15), (0, 16), (0, 17), (0, 31), (0, 32),
    (1, 1), (7, 8), (8, 7), (8, 8), (15, 16), (16, 15), (16, 16), (17, 17), (31, 32), (32, 31),
]

def parse_cases(path):
    cases = []
    cur = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line:
            if cur:
                cases.append(cur)
                cur = {}
            continue
        if "=" in line:
            k, v = [x.strip() for x in line.split("=", 1)]
            cur[k] = v
    if cur:
        cases.append(cur)
    return cases

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

def add_key_nonce(tokens, key_hex, nonce_hex):
    key = bytes.fromhex(key_hex)
    nonce = bytes.fromhex(nonce_hex)
    tokens.append(tok(False, "SDMC_TOK_KEY",   8, int.from_bytes(key[:8], "little")))
    tokens.append(tok(True,  "SDMC_TOK_KEY",   8, int.from_bytes(key[8:16], "little")))
    tokens.append(tok(False, "SDMC_TOK_NONCE", 8, int.from_bytes(nonce[:8], "little")))
    tokens.append(tok(True,  "SDMC_TOK_NONCE", 8, int.from_bytes(nonce[8:16], "little")))

def add_stream(tokens, kind, hexstr):
    for word, nbytes, last in chunks8(hexstr):
        tokens.append(tok(last, kind, nbytes, word))

def packed_le(hexstr):
    b = bytes.fromhex(hexstr)
    return int.from_bytes(b, "little") if b else 0

def write_tb(name, case, mode):
    key = case["Key"]
    nonce = case["Nonce"]
    ad = case.get("AD", "")
    pt = case.get("PT", "")
    ct_tag = case["CT"]
    ct = ct_tag[:-32]
    tag = ct_tag[-32:]

    ad_len = len(bytes.fromhex(ad))
    pt_len = len(bytes.fromhex(pt))
    ct_len = len(bytes.fromhex(ct))

    is_dec = mode in ("dec_good", "dec_bad")
    is_bad = mode == "dec_bad"

    tokens = []
    add_key_nonce(tokens, key, nonce)
    add_stream(tokens, "SDMC_TOK_AD", ad)

    if is_dec:
        add_stream(tokens, "SDMC_TOK_MSG", ct)
        tag_bytes = bytearray.fromhex(tag)
        if is_bad:
            tag_bytes[-1] ^= 0x01
        add_stream(tokens, "SDMC_TOK_TAG", tag_bytes.hex())
        expected_hex = pt
        out_bytes = pt_len
        data_len = ct_len
        auth_expected = 0 if is_bad else 1
        dec_bit = "1'b1"
    else:
        add_stream(tokens, "SDMC_TOK_MSG", pt)
        expected_hex = ct_tag
        out_bytes = len(bytes.fromhex(ct_tag))
        data_len = pt_len
        auth_expected = 1
        dec_bit = "1'b0"

    out_bits = max(8, out_bytes * 8)
    expected_val = packed_le(expected_hex)
    expected_literal = f"{out_bits}'h{expected_val:0{out_bits//4}x}"

    d = OUT_ROOT / name
    d.mkdir(parents=True, exist_ok=True)
    tb = d / f"tb_{name}.v"

    init_lines = "\n".join(f"        token_mem[{i}] = {lit};" for i, lit in enumerate(tokens))
    enc_tag_check_enable = 1 if not is_dec else 0

    tb.write_text(f"""`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_{name};

    localparam integer TOKEN_COUNT = {len(tokens)};
    localparam integer OUT_BYTES = {out_bytes};
    localparam integer OUT_BITS = {out_bits};
    localparam integer PT_BYTES = {pt_len};

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    reg start = 1'b0;
    always #5 clk = ~clk;

    reg [7:0] token_idx = 8'd0;
    reg [`SDMC_TOKEN_W-1:0] token_mem [0:TOKEN_COUNT-1];

    wire in_empty = (token_idx >= TOKEN_COUNT);
    wire [`SDMC_TOKEN_W-1:0] in_token = in_empty ? {{`SDMC_TOKEN_W{{1'b0}}}} : token_mem[token_idx];
    wire in_pop;

    wire [`SDMC_TOKEN_W-1:0] out_token;
    wire out_push;
    reg out_full = 1'b0;

    wire busy;
    wire done;
    wire error;
    wire auth_ok;

    reg [OUT_BITS-1:0] got;
    reg [15:0] out_bytes_seen;

    sdmc_aead128_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .start(start),
        .is_decrypt({dec_bit}),
        .ad_len(16'd{ad_len}),
        .data_len(16'd{data_len}),
        .in_token(in_token),
        .in_empty(in_empty),
        .in_pop(in_pop),
        .out_token(out_token),
        .out_push(out_push),
        .out_full(out_full),
        .busy(busy),
        .done(done),
        .error(error),
        .auth_ok(auth_ok)
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

    initial begin
{init_lines}
    end

    always @(negedge clk) begin
        if (!rst_n || clear) begin
            token_idx <= 8'd0;
        end else if (in_pop) begin
            token_idx <= token_idx + 8'd1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            got <= {{OUT_BITS{{1'b0}}}};
            out_bytes_seen <= 16'd0;
        end else if (out_push) begin
            if ((out_bytes_seen + tok_bytes) > OUT_BYTES) begin
                $display("FAIL too many output bytes seen=%0d tok_bytes=%0d out_bytes=%0d", out_bytes_seen, tok_bytes, OUT_BYTES);
                $finish;
            end

            if (out_bytes_seen < PT_BYTES) begin
                if (tok_kind !== `SDMC_TOK_OUT) begin
                    $display("FAIL expected OUT token kind=%h seen=%0d", tok_kind, out_bytes_seen);
                    $finish;
                end
            end else begin
                if ({enc_tag_check_enable} && tok_kind !== `SDMC_TOK_TAG) begin
                    $display("FAIL expected TAG token kind=%h seen=%0d", tok_kind, out_bytes_seen);
                    $finish;
                end
            end

            for (j = 0; j < 8; j = j + 1) begin
                if (j < tok_bytes) begin
                    got[(out_bytes_seen + j)*8 +: 8] <= tok_data[j*8 +: 8];
                end
            end

            out_bytes_seen <= out_bytes_seen + tok_bytes;
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
            if (guard > 50000) begin
                $display("FAIL timeout Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len}");
                $finish;
            end
        end

        repeat (3) tick();

        if (error) begin
            $display("FAIL error asserted Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len}");
            $finish;
        end

        if (token_idx !== TOKEN_COUNT) begin
            $display("FAIL tokens consumed=%0d expected=%0d Count={case['Count']} mode={mode}", token_idx, TOKEN_COUNT);
            $finish;
        end

        if (out_bytes_seen !== OUT_BYTES) begin
            $display("FAIL output bytes=%0d expected=%0d Count={case['Count']} mode={mode}", out_bytes_seen, OUT_BYTES);
            $finish;
        end

        if (got !== {expected_literal}) begin
            $display("FAIL output mismatch Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len}");
            $display("got=%h", got);
            $display("exp=%h", {expected_literal});
            $finish;
        end

        if (auth_ok !== 1'b{auth_expected}) begin
            $display("FAIL auth mismatch got=%b exp={auth_expected} Count={case['Count']} mode={mode}", auth_ok);
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
    cases = parse_cases(KAT)
    by_pair = {}
    for c in cases:
        ad_len = len(bytes.fromhex(c.get("AD", "")))
        pt_len = len(bytes.fromhex(c.get("PT", "")))
        by_pair.setdefault((ad_len, pt_len), c)

    generated = []

    for ad_len, pt_len in TARGET_PAIRS:
        c = by_pair.get((ad_len, pt_len))
        if not c:
            print(f"WARN missing official case AD={ad_len} PT={pt_len}")
            continue

        count = int(c["Count"])
        base = f"sdmc_aead128_kat_c{count:03d}_ad{ad_len}_pt{pt_len}"

        generated.append(write_tb(base + "_enc", c, "enc"))
        generated.append(write_tb(base + "_dec", c, "dec_good"))
        generated.append(write_tb(base + "_badtag", c, "dec_bad"))

    manifest = OUT_ROOT / "manifest.txt"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text("\\n".join(generated) + "\\n")

    print(f"Generated {len(generated)} AEAD official matrix tests")
    print(f"Manifest: {manifest}")

if __name__ == "__main__":
    main()
