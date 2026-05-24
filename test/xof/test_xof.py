"""XOF128 streaming I/O + chain mode test."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

SINGLE_VECS = [
    ("empty_32", b"", 32,
     "473d5e6164f58b39dfd84aacdb8ae42ec2d91fed33388ee0d960d9b3993295c6"),
    ("1byte_a_32", b"a", 32,
     "ede10034ee08f138cb188a4ad59bb091b9732cce23cb94fe7ef04bb0d5b0ab11"),
    ("abc_32", b"abc", 32,
     "b87198613d724232505baa68187f925708c009fe6ec13d19ce3c7aa6b20b2f0b"),
    ("empty_16", b"", 16,
     "473d5e6164f58b39dfd84aacdb8ae42e"),
    ("abc_64", b"abc", 64,
     "b87198613d724232505baa68187f925708c009fe6ec13d19ce3c7aa6b20b2f0b23b7aa1a12d7d7b2f5b4ab654b142711ba3acfddc02bc9f5d467c6c5a7745462"),
]

CHAIN_VECS = [
    ("xof_chain_abc_x2",       b"abc",   2, 32,
     "664521c1f7842bd04cef57a1abb413e1814be0c92ed98c35909e87563395b26d"),
    ("xof_chain_abc_x3",       b"abc",   3, 32,
     "e23d29d8cdf02c164e6848d7974c85bbc8a331d41614fe2773fdebaab27adcb1"),
    ("xof_chain_empty_x2",     b"",      2, 32,
     "518d323ca6150d7ac70631f901760f92b941b05d2eb83583ce3d3cd1a6856a72"),
    ("xof_chain_hello_x4",     b"hello", 4, 32,
     "9be95629d7dc7e44ac33bfcf1cd830258238d61360f3d7628cad090b9af79bf0"),
    ("xof_chain_abc_x2_out16", b"abc",   2, 16,
     "664521c1f7842bd04cef57a1abb413e1"),
    ("xof_chain_abc_x3_out64", b"abc",   3, 64,
     "e23d29d8cdf02c164e6848d7974c85bbc8a331d41614fe2773fdebaab27adcb195b8da5e20d5443d0b639e425f8b6167ace3c5e5c839a2dfa3d2617993c617be"),
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
    dut.msg_total_bytes.value = 0
    dut.out_length.value = 0
    dut.chain_enable.value = 0
    dut.chain_count.value = 0
    dut.chain_debug.value = 0
    dut.in_word.value = 0
    dut.in_word_bytes.value = 0
    dut.in_word_last.value = 0
    dut.in_word_valid.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

async def feed_words(dut, words):
    for word, nbytes, is_last in words:
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

@cocotb.test()
async def test_xof_all(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    fails = 0

    # Single-pass
    for name, msg, out_len, exp_hex in SINGLE_VECS:
        await reset(dut)
        dut.msg_total_bytes.value = len(msg)
        dut.out_length.value = out_len
        dut.chain_enable.value = 0
        dut.chain_count.value = 0
        dut.chain_debug.value = 0
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_words(dut, split_to_words(msg)))
        got = await collect_output(dut)
        if got == bytes.fromhex(exp_hex):
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}: got={got.hex()} exp={exp_hex}")
            fails += 1

    # Chain
    for name, msg, n_iter, out_len, exp_hex in CHAIN_VECS:
        await reset(dut)
        dut.msg_total_bytes.value = len(msg)
        dut.out_length.value = out_len
        dut.chain_enable.value = 1
        dut.chain_count.value = n_iter
        dut.chain_debug.value = 0
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        cocotb.start_soon(feed_words(dut, split_to_words(msg)))
        got = await collect_output(dut)
        if got == bytes.fromhex(exp_hex):
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}: got={got.hex()} exp={exp_hex}")
            fails += 1

    assert fails == 0, f"{fails} vectors failed"
