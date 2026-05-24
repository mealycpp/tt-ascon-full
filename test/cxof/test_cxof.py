"""CXOF streaming I/O test — single + chain modes."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

SINGLE_VECS = [
    ("cxof_empty_empty",     b"", b"",      32,
     "4f50159ef70bb3dad8807e034eaebd44c4fa2cbbc8cf1f05511ab66cdcc52990"),
    ("cxof_empty_abc",       b"", b"abc",   32,
     "5713d780f6589bd7386271bab19d542bc2cd0f406e42fe73e5c5aad720c94892"),
    ("cxof_a_empty",         b"a", b"",     32,
     "e4a5cbfcd91bfa00832dd22cb67dff5937171bcb5398556f7d51b190a1843f7a"),
    ("cxof_a_abc",           b"a", b"abc",  32,
     "431a99ba25f98ad8cbebe252fbd4c6f94b119f59edad308b64801ce7215c8f02"),
    ("cxof_hello_world",     b"hello", b"world", 32,
     "6d652f6c40404fccbac7c603dabe24965bb2a984fae3dd2c0ce92ee19979b07c"),
    ("cxof_empty_abc_out16", b"", b"abc",   16,
     "5713d780f6589bd7386271bab19d542b"),
]

CHAIN_FINAL_VECS = [
    ("chain_abc_x2", b"", b"abc", 2,
     "b5445469a172c3b01e0df8132b51e24dcf7137c70fb5844cc526ac19f07655c2"),
    ("chain_abc_x3", b"", b"abc", 3,
     "5c163db48d48ed0ce77cab35b545905151e954932dde1ca2060371cece7f7fb5"),
    ("chain_a_empty_x2", b"a", b"", 2,
     "a9a5c88976ba24e5dd2c8d2ed46fba9d512e24409242a650e96c198695dd86c4"),
    ("chain_hello_world_x5", b"hello", b"world", 5,
     "81a9e1ef15ff86ff3510118e934e624c9125478a7131f3ffa5ef034dd61d564c"),
]

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

async def feed_cs_then_msg(dut, cs_bytes, msg_bytes):
    cs_words = split_to_words(cs_bytes)
    msg_words = split_to_words(msg_bytes)
    await feed_phase(dut, cs_words, is_cs=True)
    await feed_phase(dut, msg_words, is_cs=False)

async def feed_cs_only(dut, cs_bytes):
    """For chain iterations 2..N, only CS comes from upstream (msg from chain_fifo)."""
    cs_words = split_to_words(cs_bytes)
    await feed_phase(dut, cs_words, is_cs=True)

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

async def feed_chain_session(dut, cs, msg, n_iter):
    """First iter: feed CS + MSG. Iters 2..N: feed CS only."""
    cs_words = split_to_words(cs)
    msg_words = split_to_words(msg)
    # First iteration
    await feed_phase(dut, cs_words, is_cs=True)
    await feed_phase(dut, msg_words, is_cs=False)
    # Subsequent iterations: only CS
    for _ in range(n_iter - 1):
        await feed_phase(dut, cs_words, is_cs=True)

@cocotb.test()
async def test_cxof_all(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    fails = 0

    for name, cs, msg, outlen, exp_hex in SINGLE_VECS:
        await reset(dut)
        dut.cs_total_bits.value = len(cs) * 8
        dut.msg_total_bytes.value = len(msg)
        dut.out_length.value = outlen
        dut.chain_enable.value = 0
        dut.chain_count.value = 0
        dut.chain_debug.value = 0
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_cs_then_msg(dut, cs, msg))
        got = await collect_output(dut)
        expected = bytes.fromhex(exp_hex)
        if got == expected:
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}")
            dut._log.error(f"  expected: {exp_hex}")
            dut._log.error(f"  got:      {got.hex()}")
            fails += 1

    for name, cs, msg, n, exp_hex in CHAIN_FINAL_VECS:
        await reset(dut)
        dut.cs_total_bits.value = len(cs) * 8
        dut.msg_total_bytes.value = len(msg)
        dut.out_length.value = 32
        dut.chain_enable.value = 1
        dut.chain_count.value = n
        dut.chain_debug.value = 0
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_chain_session(dut, cs, msg, n))
        got = await collect_output(dut)
        expected = bytes.fromhex(exp_hex)
        if got == expected:
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}")
            dut._log.error(f"  expected: {exp_hex}")
            dut._log.error(f"  got:      {got.hex()}")
            fails += 1

    assert fails == 0, f"{fails} vectors failed"
