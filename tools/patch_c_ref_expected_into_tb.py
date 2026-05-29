#!/usr/bin/env python3
from pathlib import Path
import subprocess
import re
import sys

OUT = Path("test/sdmc_top_uart_c_ref_crazy")
CLI = Path("tools/ascon_aead128_ref_cli")
MANIFEST = OUT / "manifest.txt"

def data_bytes(start, n):
    return bytes(((start + i) & 0xff) for i in range(n))

def normalize_send_key_nonce_ad(s, name):
    new_task = """    task automatic send_key_nonce_ad;
        integer j;
        begin
            for (j = 0; j < 16; j = j + 1) begin
                uart_send_byte(0, j[7:0]);
            end
            for (j = 0; j < 16; j = j + 1) begin
                uart_send_byte(0, 8'h10 + j[7:0]);
            end
            for (j = 0; j < AD_LEN; j = j + 1) begin
                uart_send_byte(0, 8'h40 + j[7:0]);
            end
        end
    endtask
"""

    s2, n = re.subn(
        r"    task\s+automatic\s+send_key_nonce_ad\s*;.*?    endtask\s*",
        new_task,
        s,
        count=1,
        flags=re.S,
    )

    if n != 1:
        raise SystemExit(f"{name}: could not replace send_key_nonce_ad task")

    return s2

def patch_one(name):
    tb = OUT / f"tb_{name}.v"
    s = tb.read_text()

    ad_len = int(re.search(r"localparam integer AD_LEN = ([0-9]+);", s).group(1))
    pt_len = int(re.search(r"localparam integer PT_LEN = ([0-9]+);", s).group(1))
    enc_len = pt_len + 16

    # Force the generated processor-side stream to match the C reference.
    s = normalize_send_key_nonce_ad(s, name)

    key = bytes(range(0x00, 0x10))
    nonce = bytes(range(0x10, 0x20))
    ad = data_bytes(0x40, ad_len)
    pt = data_bytes(0x20, pt_len)

    exp_hex = subprocess.check_output(
        [str(CLI), "enc", key.hex(), nonce.hex(), ad.hex(), pt.hex()],
        text=True
    ).strip()

    exp = bytes.fromhex(exp_hex)
    if len(exp) != enc_len:
        raise SystemExit(f"{name}: expected length mismatch {len(exp)} != {enc_len}")

    if "localparam TEST_NAME" not in s:
        s = re.sub(
            r"(localparam integer PT_LEN = [0-9]+;)",
            r'\1\n    localparam TEST_NAME = "' + name + r'";',
            s,
            count=1,
        )

    if "reg [7:0] exp_enc" not in s:
        decl = """    // Official C-reference expected ciphertext||tag.
    reg [7:0] exp_enc [0:ENC_OUT_LEN-1];
    integer cref_i;

"""
        idx = s.find("    task automatic")
        if idx < 0:
            raise SystemExit(f"{name}: could not find declaration insertion point")
        s = s[:idx] + decl + s[idx:]

    init_lines = ["    initial begin"]
    for i, b in enumerate(exp):
        init_lines.append(f"        exp_enc[{i}] = 8'h{b:02x};")
    init_lines.append("    end")
    init_block = "\n".join(init_lines) + "\n"

    check_block = """
    initial begin
        wait (enc_rx_count == ENC_OUT_LEN);
        #1;
        for (cref_i = 0; cref_i < ENC_OUT_LEN; cref_i = cref_i + 1) begin
            if (enc[cref_i] !== exp_enc[cref_i]) begin
                $display("FAIL C_REF_ENC name=%s idx=%0d got=%02x exp=%02x AD=%0d PT=%0d",
                    TEST_NAME, cref_i, enc[cref_i], exp_enc[cref_i], AD_LEN, PT_LEN);
                $finish;
            end
        end
        $display("PASS C_REF_ENC name=%s AD=%0d PT=%0d enc_rx=%0d/%0d",
            TEST_NAME, AD_LEN, PT_LEN, enc_rx_count, ENC_OUT_LEN);
        $fflush;
    end

"""

    if "PASS C_REF_ENC" not in s:
        s = s.replace("\nendmodule\n", "\n" + init_block + check_block + "endmodule\n")

    tb.write_text(s)
    print(f"{name}: forced KEY=00..0f NONCE=10..1f AD=40+i PT=20+i")

def main():
    if not CLI.exists():
        raise SystemExit("missing tools/ascon_aead128_ref_cli")
    if not MANIFEST.exists():
        raise SystemExit(f"missing manifest: {MANIFEST}")

    names = [x.strip() for x in MANIFEST.read_text().splitlines() if x.strip()]
    if not names:
        raise SystemExit("empty manifest")

    for name in names:
        patch_one(name)

    print(f"Patched {len(names)} C-reference crazy testbenches")

if __name__ == "__main__":
    main()
