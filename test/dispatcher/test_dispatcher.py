"""SDMC dispatcher full integration test.

All 5 modes (Hash, XOF single, XOF chain, CXOF single, CXOF chain) through
ONE shared ascon_permutation via streaming 64-bit I/O."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

M_HASH256    = 1
M_XOF128     = 2
M_CXOF128    = 3
M_CXOF_CHAIN = 4
M_AEAD_ENC   = 5
M_AEAD_DEC   = 6
M_XOF_CHAIN  = 7

HASH_VECS = [
    ("hash_empty", b"",
     "0b3be5850f2f6b98caf29f8fdea89b64a1fa70aa249b8f839bd53baa304d92b2"),
    ("hash_abc", b"abc",
     "45aa03431c3c829b3b066f33e844b0cc4d20a45af92d3dcfdf34f40fc20935cf"),
]

XOF_VECS = [
    ("xof_empty_32", b"", 32,
     "473d5e6164f58b39dfd84aacdb8ae42ec2d91fed33388ee0d960d9b3993295c6"),
    ("xof_abc_32", b"abc", 32,
     "b87198613d724232505baa68187f925708c009fe6ec13d19ce3c7aa6b20b2f0b"),
    ("xof_abc_64", b"abc", 64,
     "b87198613d724232505baa68187f925708c009fe6ec13d19ce3c7aa6b20b2f0b23b7aa1a12d7d7b2f5b4ab654b142711ba3acfddc02bc9f5d467c6c5a7745462"),
]

XOF_CHAIN_VECS = [
    ("xof_chain_abc_x2", b"abc", 2, 32,
     "664521c1f7842bd04cef57a1abb413e1814be0c92ed98c35909e87563395b26d"),
    ("xof_chain_hello_x4", b"hello", 4, 32,
     "9be95629d7dc7e44ac33bfcf1cd830258238d61360f3d7628cad090b9af79bf0"),
]

CXOF_SINGLE_VECS = [
    ("cxof_empty_abc", b"", b"abc", 32,
     "5713d780f6589bd7386271bab19d542bc2cd0f406e42fe73e5c5aad720c94892"),
    ("cxof_a_abc", b"a", b"abc", 32,
     "431a99ba25f98ad8cbebe252fbd4c6f94b119f59edad308b64801ce7215c8f02"),
    ("cxof_hello_world", b"hello", b"world", 32,
     "6d652f6c40404fccbac7c603dabe24965bb2a984fae3dd2c0ce92ee19979b07c"),
]

CXOF_CHAIN_VECS = [
    ("chain_abc_x2", b"", b"abc", 2,
     "b5445469a172c3b01e0df8132b51e24dcf7137c70fb5844cc526ac19f07655c2"),
    ("chain_hello_world_x5", b"hello", b"world", 5,
     "81a9e1ef15ff86ff3510118e934e624c9125478a7131f3ffa5ef034dd61d564c"),
]

AEAD_ENC_VECS = [
    ("aead_enc_empty",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "", "", "4f9c278211bec9316bf68f46ee8b2ec6"),
    ("aead_enc_abc",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "", "616263", "a9809f517628a40f729002c21309c296b25c17"),
    ("aead_enc_8b_8b",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "4142434445464748", "5152535455565758",
     "4858e5aef2c30684ccfdffdb59b292ae00aa51f1f34fd939"),
    ("aead_enc_16b_16b",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "4142434445464748494a4b4c4d4e4f50", "5152535455565758595a5b5c5d5e5f60",
     "9d9c80156e869dc6b51f6358973aa8ed85f8a815f2e98b6f3875faee07d6326d"),
]

AEAD_DEC_VECS = [
    ("aead_dec_empty",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "", "", "4f9c278211bec9316bf68f46ee8b2ec6", "", 1),
    ("aead_dec_abc",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "", "a9809f", "517628a40f729002c21309c296b25c17", "616263", 1),
    ("aead_dec_16b_16b",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "4142434445464748494a4b4c4d4e4f50", "9d9c80156e869dc6b51f6358973aa8ed",
     "85f8a815f2e98b6f3875faee07d6326d", "5152535455565758595a5b5c5d5e5f60", 1),
    ("aead_dec_bad_tag",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "", "a9809f", "517628a40f729002c21309c296b25c00", "616263", 0),
]

def bytes_to_word(b8):
    word = 0
    for j, x in enumerate(b8):
        word |= x << (8*j)
    return word

def split_to_words(b):
    if len(b) == 0:
        return []
    words = []
    i = 0
    while i < len(b):
        chunk = b[i:i+8]
        word = 0
        for j, x in enumerate(chunk):
            word |= x << (8*j)
        is_last = (i + 8 >= len(b))
        words.append((word, len(chunk), is_last))
        i += 8
    return words

async def reset(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.reset_engine.value = 0
    dut.mode_sel.value = 0
    dut.cs_total_bits.value = 0
    dut.msg_total_bytes.value = 0
    dut.out_length.value = 0
    dut.chain_enable.value = 0
    dut.chain_count.value = 0
    dut.chain_debug.value = 0
    dut.in_word.value = 0
    dut.in_word_bytes.value = 0
    dut.in_word_last.value = 0
    dut.in_word_is_cs.value = 0
    dut.in_word_valid.value = 0
    dut.is_decrypt.value = 0
    dut.ad_total_bytes.value = 0
    dut.data_total_bytes.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

async def feed_phase(dut, words, is_cs):
    for word, nbytes, is_last in words:
        while True:
            await RisingEdge(dut.clk)
            if dut.in_word_ready.value == 1:
                break
        dut.in_word.value = word
        dut.in_word_bytes.value = nbytes
        dut.in_word_last.value = 1 if is_last else 0
        dut.in_word_is_cs.value = 1 if is_cs else 0
        dut.in_word_valid.value = 1
        await RisingEdge(dut.clk)
        dut.in_word_valid.value = 0
        dut.in_word_last.value = 0

async def collect_output(dut):
    out = bytearray()
    for _ in range(30000):
        await RisingEdge(dut.clk)
        if dut.out_valid.value == 1:
            block_int = int(dut.out_block.value)
            byte_count = int(dut.out_byte_count.value)
            if byte_count == 0:
                byte_count = 8
            for i in range(byte_count):
                out.append((block_int >> (8*i)) & 0xff)
        if dut.done.value == 1:
            return bytes(out)
    raise RuntimeError("done never asserted")

async def feed_msg_only(dut, msg):
    await feed_phase(dut, split_to_words(msg), is_cs=False)

async def feed_cs_then_msg(dut, cs, msg):
    await feed_phase(dut, split_to_words(cs), is_cs=True)
    await feed_phase(dut, split_to_words(msg), is_cs=False)

async def feed_cxof_chain_session(dut, cs, msg, n_iter):
    cs_words = split_to_words(cs)
    msg_words = split_to_words(msg)
    await feed_phase(dut, cs_words, is_cs=True)
    await feed_phase(dut, msg_words, is_cs=False)
    for _ in range(n_iter - 1):
        await feed_phase(dut, cs_words, is_cs=True)

async def feed_one_word(dut, word, nbytes, is_last):
    while True:
        await RisingEdge(dut.clk)
        if dut.in_word_ready.value == 1:
            break
    dut.in_word.value = word
    dut.in_word_bytes.value = nbytes
    dut.in_word_last.value = 1 if is_last else 0
    dut.in_word_valid.value = 1
    await RisingEdge(dut.clk)
    dut.in_word_valid.value = 0
    dut.in_word_last.value = 0

async def feed_aead_encrypt(dut, key, nonce, ad, msg):
    await feed_one_word(dut, bytes_to_word(key[0:8]), 8, False)
    await feed_one_word(dut, bytes_to_word(key[8:16]), 8, False)
    await feed_one_word(dut, bytes_to_word(nonce[0:8]), 8, False)
    await feed_one_word(dut, bytes_to_word(nonce[8:16]), 8, False)
    for w, n, last in split_to_words(ad):
        await feed_one_word(dut, w, n, last)
    for w, n, last in split_to_words(msg):
        await feed_one_word(dut, w, n, last)

async def feed_aead_decrypt(dut, key, nonce, ad, ct, tag):
    await feed_one_word(dut, bytes_to_word(key[0:8]), 8, False)
    await feed_one_word(dut, bytes_to_word(key[8:16]), 8, False)
    await feed_one_word(dut, bytes_to_word(nonce[0:8]), 8, False)
    await feed_one_word(dut, bytes_to_word(nonce[8:16]), 8, False)
    for w, n, last in split_to_words(ad):
        await feed_one_word(dut, w, n, last)
    for w, n, last in split_to_words(ct):
        await feed_one_word(dut, w, n, last)
    await feed_one_word(dut, bytes_to_word(tag[0:8]), 8, False)
    await feed_one_word(dut, bytes_to_word(tag[8:16]), 8, True)

async def collect_with_auth(dut):
    out = bytearray()
    auth = None
    for _ in range(30000):
        await RisingEdge(dut.clk)
        if dut.out_valid.value == 1:
            block_int = int(dut.out_block.value)
            byte_count = int(dut.out_byte_count.value)
            if byte_count == 0:
                byte_count = 8
            for i in range(byte_count):
                out.append((block_int >> (8*i)) & 0xff)
        if dut.done.value == 1:
            auth = int(dut.auth_ok.value)
            return bytes(out), auth
    raise RuntimeError("done never asserted")

@cocotb.test()
async def test_sdmc_all(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    fails = 0

    # Hash256
    for name, msg, exp_hex in HASH_VECS:
        await reset(dut)
        dut.mode_sel.value = M_HASH256
        dut.msg_total_bytes.value = len(msg)
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_msg_only(dut, msg))
        got = await collect_output(dut)
        if got == bytes.fromhex(exp_hex):
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}: got={got.hex()} exp={exp_hex}")
            fails += 1

    # XOF128 single
    for name, msg, out_len, exp_hex in XOF_VECS:
        await reset(dut)
        dut.mode_sel.value = M_XOF128
        dut.msg_total_bytes.value = len(msg)
        dut.out_length.value = out_len
        dut.chain_enable.value = 0
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_msg_only(dut, msg))
        got = await collect_output(dut)
        if got == bytes.fromhex(exp_hex):
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}: got={got.hex()} exp={exp_hex}")
            fails += 1

    # XOF128 chain
    for name, msg, n_iter, out_len, exp_hex in XOF_CHAIN_VECS:
        await reset(dut)
        dut.mode_sel.value = M_XOF_CHAIN
        dut.msg_total_bytes.value = len(msg)
        dut.out_length.value = out_len
        dut.chain_enable.value = 1
        dut.chain_count.value = n_iter
        dut.chain_debug.value = 0
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_msg_only(dut, msg))
        got = await collect_output(dut)
        if got == bytes.fromhex(exp_hex):
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}: got={got.hex()} exp={exp_hex}")
            fails += 1

    # CXOF128 single
    for name, cs, msg, out_len, exp_hex in CXOF_SINGLE_VECS:
        await reset(dut)
        dut.mode_sel.value = M_CXOF128
        dut.cs_total_bits.value = len(cs) * 8
        dut.msg_total_bytes.value = len(msg)
        dut.out_length.value = out_len
        dut.chain_enable.value = 0
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_cs_then_msg(dut, cs, msg))
        got = await collect_output(dut)
        if got == bytes.fromhex(exp_hex):
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}: got={got.hex()} exp={exp_hex}")
            fails += 1

    # CXOF128 chain
    for name, cs, msg, n_iter, exp_hex in CXOF_CHAIN_VECS:
        await reset(dut)
        dut.mode_sel.value = M_CXOF_CHAIN
        dut.cs_total_bits.value = len(cs) * 8
        dut.msg_total_bytes.value = len(msg)
        dut.out_length.value = 32
        dut.chain_enable.value = 1
        dut.chain_count.value = n_iter
        dut.chain_debug.value = 0
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_cxof_chain_session(dut, cs, msg, n_iter))
        got = await collect_output(dut)
        if got == bytes.fromhex(exp_hex):
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}: got={got.hex()} exp={exp_hex}")
            fails += 1

    # AEAD encrypt
    for name, k_hex, n_hex, ad_hex, msg_hex, exp_hex in AEAD_ENC_VECS:
        await reset(dut)
        dut.mode_sel.value = M_AEAD_ENC
        dut.is_decrypt.value = 0
        dut.ad_total_bytes.value = len(bytes.fromhex(ad_hex))
        dut.data_total_bytes.value = len(bytes.fromhex(msg_hex))
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_aead_encrypt(dut, bytes.fromhex(k_hex), bytes.fromhex(n_hex),
                                            bytes.fromhex(ad_hex), bytes.fromhex(msg_hex)))
        got, _ = await collect_with_auth(dut)
        if got == bytes.fromhex(exp_hex):
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}: got={got.hex()} exp={exp_hex}")
            fails += 1

    # AEAD decrypt
    for name, k_hex, n_hex, ad_hex, ct_hex, tag_hex, pt_hex, exp_auth in AEAD_DEC_VECS:
        await reset(dut)
        dut.mode_sel.value = M_AEAD_DEC
        dut.is_decrypt.value = 1
        dut.ad_total_bytes.value = len(bytes.fromhex(ad_hex))
        dut.data_total_bytes.value = len(bytes.fromhex(ct_hex))
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_aead_decrypt(dut, bytes.fromhex(k_hex), bytes.fromhex(n_hex),
                                            bytes.fromhex(ad_hex), bytes.fromhex(ct_hex), bytes.fromhex(tag_hex)))
        got_pt, got_auth = await collect_with_auth(dut)
        if exp_auth == 1:
            if got_pt == bytes.fromhex(pt_hex) and got_auth == 1:
                dut._log.info(f"PASS {name} (pt={got_pt.hex()} auth=1)")
            else:
                dut._log.error(f"FAIL {name}: pt={got_pt.hex()} exp_pt={pt_hex} auth={got_auth}")
                fails += 1
        else:
            if got_auth == 0:
                dut._log.info(f"PASS {name} (auth=0)")
            else:
                dut._log.error(f"FAIL {name}: auth={got_auth}, expected 0")
                fails += 1

    assert fails == 0, f"{fails} vectors failed"
