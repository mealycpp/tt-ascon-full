"""ASCON-AEAD128 encrypt KAT — including multi-block."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

VECTORS = [
    ("empty_empty",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "", "", "", "4f9c278211bec9316bf68f46ee8b2ec6"),
    ("empty_abc",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "", "616263", "a9809f", "517628a40f729002c21309c296b25c17"),
    ("ad_abc_empty",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "616263", "", "", "3afda4749a03c3b929d9dda5a69fca9b"),
    ("ad_abc_msg_def",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "616263", "646566", "1204e6", "5fe13695f87a6148b60109fd448a9734"),
    ("ad_8b_msg_8b",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "4142434445464748", "5152535455565758",
     "4858e5aef2c30684", "ccfdffdb59b292ae00aa51f1f34fd939"),
    ("ad_16b_msg_16b",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "4142434445464748494a4b4c4d4e4f50", "5152535455565758595a5b5c5d5e5f60",
     "9d9c80156e869dc6b51f6358973aa8ed", "85f8a815f2e98b6f3875faee07d6326d"),
    ("ad_long_msg_long",
     "000102030405060708090a0b0c0d0e0f", "101112131415161718191a1b1c1d1e1f",
     "4142434445464748494a4b4c4d4e4f50515253",
     "5152535455565758595a5b5c5d5e5f6061626364",
     "5402705c1387b4c0da952add138c946842519560",
     "4d8a93f9568b111cf2cff7c0d073f472"),
]

def split_to_words(b):
    if len(b) == 0: return []
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

def bytes_to_word(b8):
    word = 0
    for j, x in enumerate(b8):
        word |= x << (8*j)
    return word

async def reset(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.reset_engine.value = 0
    dut.is_decrypt.value = 0
    dut.ad_total_bytes.value = 0
    dut.data_total_bytes.value = 0
    dut.in_word.value = 0
    dut.in_word_bytes.value = 0
    dut.in_word_last.value = 0
    dut.in_phase.value = 0
    dut.in_word_valid.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

async def feed_one_word(dut, word, nbytes, is_last, phase):
    while True:
        await RisingEdge(dut.clk)
        if dut.in_word_ready.value == 1:
            break
    dut.in_word.value = word
    dut.in_word_bytes.value = nbytes
    dut.in_word_last.value = 1 if is_last else 0
    dut.in_phase.value = phase
    dut.in_word_valid.value = 1
    await RisingEdge(dut.clk)
    dut.in_word_valid.value = 0
    dut.in_word_last.value = 0

async def feed_aead_inputs(dut, key, nonce, ad, msg):
    await feed_one_word(dut, bytes_to_word(key[0:8]), 8, False, 0)
    await feed_one_word(dut, bytes_to_word(key[8:16]), 8, False, 0)
    await feed_one_word(dut, bytes_to_word(nonce[0:8]), 8, False, 1)
    await feed_one_word(dut, bytes_to_word(nonce[8:16]), 8, False, 1)
    for word, nbytes, is_last in split_to_words(ad):
        await feed_one_word(dut, word, nbytes, is_last, 2)
    for word, nbytes, is_last in split_to_words(msg):
        await feed_one_word(dut, word, nbytes, is_last, 3)

async def collect_output(dut):
    out = bytearray()
    for _ in range(15000):
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

@cocotb.test()
async def test_aead_encrypt(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    fails = 0
    for name, k_hex, n_hex, ad_hex, msg_hex, ct_hex, tag_hex in VECTORS:
        await reset(dut)
        key = bytes.fromhex(k_hex)
        nonce = bytes.fromhex(n_hex)
        ad = bytes.fromhex(ad_hex)
        msg = bytes.fromhex(msg_hex)
        expected = bytes.fromhex(ct_hex) + bytes.fromhex(tag_hex)
        dut.is_decrypt.value = 0
        dut.ad_total_bytes.value = len(ad)
        dut.data_total_bytes.value = len(msg)
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_aead_inputs(dut, key, nonce, ad, msg))
        got = await collect_output(dut)
        if got == expected:
            dut._log.info(f"PASS {name} (ct+tag={len(got)} bytes)")
        else:
            dut._log.error(f"FAIL {name}")
            dut._log.error(f"  expected: {expected.hex()}")
            dut._log.error(f"  got:      {got.hex()}")
            fails += 1
    assert fails == 0, f"{fails} vectors failed"
