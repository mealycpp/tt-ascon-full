#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KAT = ROOT / "kat/official/ascon-c/asconaead128_LWC_AEAD_KAT_128_128.txt"
OUT_ROOT = ROOT / "test/sdmc_thin_frontend_aead_matrix"

TARGET_PAIRS = [
    (0, 0),
    (1, 0), (7, 0), (8, 0), (9, 0), (15, 0), (16, 0), (17, 0), (31, 0), (32, 0),
    (0, 1), (0, 7), (0, 8), (0, 9), (0, 15), (0, 16), (0, 17), (0, 31), (0, 32),
    (1, 1), (7, 8), (8, 7), (8, 8), (15, 16), (16, 15), (16, 16), (17, 17),
    (31, 32), (32, 31),
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

def v_send_seq(task, hexstr):
    b = bytes.fromhex(hexstr)
    return "\n".join(f"        {task}(8'h{x:02x});" for x in b)

def expected_array_lines(hexstr):
    b = bytes.fromhex(hexstr)
    if not b:
        return "        // no expected output bytes"
    return "\n".join(f"        expected[{i}] = 8'h{x:02x};" for i, x in enumerate(b))

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

    if is_dec:
        msg_hex = ct
        tag_bytes = bytearray.fromhex(tag)
        if is_bad:
            tag_bytes[-1] ^= 0x01
        tag_hex = tag_bytes.hex()
        expected_hex = pt
        out_bytes = pt_len
        data_len = ct_len
        mode_byte = 6
        auth_expected = 0 if is_bad else 1
    else:
        msg_hex = pt
        tag_hex = ""
        expected_hex = ct_tag
        out_bytes = len(bytes.fromhex(ct_tag))
        data_len = pt_len
        mode_byte = 5
        auth_expected = 1

    d = OUT_ROOT / name
    d.mkdir(parents=True, exist_ok=True)
    tb = d / f"tb_{name}.v"

    tb.write_text(f"""`timescale 1ns/1ps
`default_nettype none

`include "sdmc_stream_defs.vh"

module tb_{name};

    localparam integer OUT_BYTES = {out_bytes};

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg [7:0] rx0_byte = 8'd0;
    reg       rx0_valid = 1'b0;
    reg [7:0] rx1_byte = 8'd0;
    reg       rx1_valid = 1'b0;
    reg [7:0] rx2_byte = 8'd0;
    reg       rx2_valid = 1'b0;

    wire        aead_start;
    wire        aead_is_decrypt;
    wire [15:0] aead_ad_len;
    wire [15:0] aead_data_len;
    wire [`SDMC_TOKEN_W-1:0] aead_in_token;
    wire        aead_in_empty;
    wire        aead_in_pop;
    wire        front_busy;
    wire        front_error;
    wire [3:0]  front_phase;

    wire [`SDMC_TOKEN_W-1:0] aead_out_token;
    wire        aead_out_push;
    reg         aead_out_full = 1'b0;
    wire        aead_busy;
    wire        aead_done;
    wire        aead_error;
    wire        aead_auth_ok;

    sdmc_aead_uart_frontend u_front (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .rx0_byte(rx0_byte), .rx0_valid(rx0_valid),
        .rx1_byte(rx1_byte), .rx1_valid(rx1_valid),
        .rx2_byte(rx2_byte), .rx2_valid(rx2_valid),
        .aead_start(aead_start),
        .aead_is_decrypt(aead_is_decrypt),
        .aead_ad_len(aead_ad_len),
        .aead_data_len(aead_data_len),
        .aead_in_token(aead_in_token),
        .aead_in_empty(aead_in_empty),
        .aead_in_pop(aead_in_pop),
        .busy(front_busy),
        .error(front_error),
        .phase_dbg(front_phase)
    );

    sdmc_aead128_core u_aead (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .start(aead_start),
        .is_decrypt(aead_is_decrypt),
        .ad_len(aead_ad_len),
        .data_len(aead_data_len),
        .in_token(aead_in_token),
        .in_empty(aead_in_empty),
        .in_pop(aead_in_pop),
        .out_token(aead_out_token),
        .out_push(aead_out_push),
        .out_full(aead_out_full),
        .busy(aead_busy),
        .done(aead_done),
        .error(aead_error),
        .auth_ok(aead_auth_ok)
    );

    reg [7:0] expected [0:(OUT_BYTES > 0 ? OUT_BYTES-1 : 0)];
    reg [7:0] got      [0:(OUT_BYTES > 0 ? OUT_BYTES-1 : 0)];
    integer out_idx;
    integer byte_cursor;

    initial begin
{expected_array_lines(expected_hex)}
    end

    task automatic tick;
        begin
            @(negedge clk);
        end
    endtask

    task automatic idle_gap;
        integer ii;
        begin
            // Emulate UART pacing. Keeps one-token frontend from dropping bytes.
            for (ii = 0; ii < 260; ii = ii + 1) tick();
        end
    endtask

    task automatic send0;
        input [7:0] b;
        begin
            rx0_byte = b; rx0_valid = 1'b1; tick();
            rx0_valid = 1'b0; rx0_byte = 8'd0; tick();
        end
    endtask

    task automatic send1;
        input [7:0] b;
        begin
            rx1_byte = b; rx1_valid = 1'b1; tick();
            rx1_valid = 1'b0; rx1_byte = 8'd0; idle_gap();
        end
    endtask

    task automatic send2;
        input [7:0] b;
        begin
            rx2_byte = b; rx2_valid = 1'b1; tick();
            rx2_valid = 1'b0; rx2_byte = 8'd0; idle_gap();
        end
    endtask

    task automatic capture_token_bytes;
        input [`SDMC_TOKEN_W-1:0] tok;
        integer j;
        reg [3:0] nbytes;
        reg [63:0] data;
        reg [7:0] b;
        begin
            nbytes = tok[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
            data   = tok[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];

            for (j = 0; j < 8; j = j + 1) begin
                if ((j < nbytes) && (byte_cursor < OUT_BYTES)) begin
                    case (j[2:0])
                        3'd0: b = data[7:0];
                        3'd1: b = data[15:8];
                        3'd2: b = data[23:16];
                        3'd3: b = data[31:24];
                        3'd4: b = data[39:32];
                        3'd5: b = data[47:40];
                        3'd6: b = data[55:48];
                        3'd7: b = data[63:56];
                        default: b = 8'd0;
                    endcase
                    got[byte_cursor] = b;
                    byte_cursor = byte_cursor + 1;
                end
            end
            out_idx = byte_cursor;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            out_idx <= 0;
            byte_cursor <= 0;
        end else if (aead_out_push && !aead_out_full) begin
            capture_token_bytes(aead_out_token);
        end
    end

    integer k;
    integer guard;

    initial begin
        $dumpfile("tb_{name}.vcd");
        $dumpvars(0, tb_{name});

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (5) tick();

        // UART0 command frame: AEAD mode and lengths.
        send0(8'hA5);
        send0(8'd{mode_byte});
        send0(8'h00);
        send0(8'h{ad_len & 0xff:02x});
        send0(8'h{(ad_len >> 8) & 0xff:02x});
        send0(8'h{data_len & 0xff:02x});
        send0(8'h{(data_len >> 8) & 0xff:02x});
        send0(8'h00);
        send0(8'h00);
        send0(8'h01);
        send0(8'h00);
        send0(8'h00);
        send0(8'h00);
        send0(8'h5A);

        // UART1: key, nonce, AD.
{v_send_seq("send1", key)}
{v_send_seq("send1", nonce)}
{v_send_seq("send1", ad)}

        // UART2: plaintext/ciphertext, then tag for decrypt.
{v_send_seq("send2", msg_hex)}
{v_send_seq("send2", tag_hex)}

        guard = 0;
        while (out_idx < OUT_BYTES && guard < 200000) begin
            tick();
            guard = guard + 1;
        end

        // Allow final auth state to settle.
        repeat (100) tick();

        if (front_error || aead_error) begin
            $display("FAIL error Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len} front=%b aead=%b",
                front_error, aead_error);
            $finish;
        end

        if (out_idx !== OUT_BYTES) begin
            $display("FAIL output bytes=%0d expected=%0d Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len} phase=%0d busy=%b done=%b auth=%b",
                out_idx, OUT_BYTES, front_phase, aead_busy, aead_done, aead_auth_ok);
            $finish;
        end

        for (k = 0; k < OUT_BYTES; k = k + 1) begin
            if (got[k] !== expected[k]) begin
                $display("FAIL byte mismatch idx=%0d got=%02x exp=%02x Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len}",
                    k, got[k], expected[k]);
                $finish;
            end
        end

        if (aead_auth_ok !== 1'b{auth_expected}) begin
            $display("FAIL auth_ok=%b expected={auth_expected} Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len}",
                aead_auth_ok);
            $finish;
        end

        $display("PASS {name}");
        $finish;
    end

endmodule

`default_nettype wire
""")

def main():
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    cases = parse_cases(KAT)

    selected = []
    for ad_len, pt_len in TARGET_PAIRS:
        match = None
        for c in cases:
            ad = c.get("AD", "")
            pt = c.get("PT", "")
            if len(bytes.fromhex(ad)) == ad_len and len(bytes.fromhex(pt)) == pt_len:
                match = c
                break
        if match is None:
            raise SystemExit(f"missing case AD={ad_len} PT={pt_len}")
        selected.append(match)

    names = []
    for c in selected:
        ad_len = len(bytes.fromhex(c.get("AD", "")))
        pt_len = len(bytes.fromhex(c.get("PT", "")))
        base = f"sdmc_thin_front_kat_c{int(c['Count']):03d}_ad{ad_len}_pt{pt_len}"
        for suffix, mode in [("enc", "enc"), ("dec", "dec_good"), ("badtag", "dec_bad")]:
            name = f"{base}_{suffix}"
            write_tb(name, c, mode)
            names.append(name)

    (OUT_ROOT / "manifest.txt").write_text("\n".join(names) + "\n")
    print(f"Generated {len(names)} thin frontend AEAD matrix tests")
    print(f"Manifest: {OUT_ROOT / 'manifest.txt'}")

if __name__ == "__main__":
    main()
