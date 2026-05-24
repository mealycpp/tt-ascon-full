"""Hash256 test with streaming 64-bit input handshake (test acts as stub packer)."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

VECTORS = [
    ("empty", b"",
     "0b3be5850f2f6b98caf29f8fdea89b64a1fa70aa249b8f839bd53baa304d92b2"),
    ("1byte_a", b"a",
     "d6943d8cddc8c3565cfbcfe27bf05cba039f0808d86ac3ac1289ce2261840e05"),
    ("abc", b"abc",
     "45aa03431c3c829b3b066f33e844b0cc4d20a45af92d3dcfdf34f40fc20935cf"),
    ("16bytes", b"0123456789abcdef",
     None),  # generate later if needed
    ("24bytes", b"The quick brown fox jump",
     None),
]

def split_to_words(msg_bytes):
    """Split message into list of (word_int, byte_count, is_last) tuples."""
    if len(msg_bytes) == 0:
        return []
    words = []
    i = 0
    while i < len(msg_bytes):
        chunk = msg_bytes[i:i+8]
        word = 0
        for j, b in enumerate(chunk):
            word |= b << (8*j)
        is_last = (i + 8 >= len(msg_bytes))
        words.append((word, len(chunk), is_last))
        i += 8
    return words

async def reset(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.reset_engine.value = 0
    dut.msg_total_bytes.value = 0
    dut.in_word.value = 0
    dut.in_word_bytes.value = 0
    dut.in_word_last.value = 0
    dut.in_word_valid.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

async def feed_words(dut, words):
    """Feed words via handshake: wait for ready, present word, wait one cycle."""
    for word, nbytes, is_last in words:
        # Wait until controller is ready
        while True:
            await RisingEdge(dut.clk)
            if dut.in_word_ready.value == 1:
                break
        # Present word
        dut.in_word.value = word
        dut.in_word_bytes.value = nbytes
        dut.in_word_last.value = 1 if is_last else 0
        dut.in_word_valid.value = 1
        await RisingEdge(dut.clk)
        dut.in_word_valid.value = 0
        dut.in_word_last.value = 0

async def collect_output(dut):
    out = bytearray()
    for _ in range(2000):
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
async def test_hash_streaming(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    fails = 0

    for name, msg, exp_hex in VECTORS:
        if exp_hex is None:
            continue  # skip placeholders
        await reset(dut)
        words = split_to_words(msg)
        # Start controller
        dut.msg_total_bytes.value = len(msg)
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        # Feed words in parallel with controller running
        await cocotb.start(feed_words(dut, words))
        got = await collect_output(dut)
        expected = bytes.fromhex(exp_hex)
        if got == expected:
            dut._log.info(f"PASS {name} ({len(got)} bytes)")
        else:
            dut._log.error(f"FAIL {name}")
            dut._log.error(f"  expected: {expected.hex()}")
            dut._log.error(f"  got:      {got.hex()}")
            fails += 1

    assert fails == 0, f"{fails} vectors failed"
