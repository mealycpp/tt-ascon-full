"""Packer tests: backpressure, flush handshake, partial, exact, consecutive."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

async def reset(dut):
    dut.rst_n.value = 0
    dut.in_byte.value = 0
    dut.in_byte_valid.value = 0
    dut.flush.value = 0
    dut.out_word_ready.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

async def feed_byte(dut, b, slow_consumer=False):
    """Push one byte through the packer's input handshake."""
    while True:
        await RisingEdge(dut.clk)
        if int(dut.in_byte_ready.value) == 1:
            break
    dut.in_byte.value = b
    dut.in_byte_valid.value = 1
    await RisingEdge(dut.clk)
    dut.in_byte_valid.value = 0

async def consume_word(dut, settle_cycles=0):
    """Wait for out_word_valid, sample, ack."""
    while True:
        await RisingEdge(dut.clk)
        if int(dut.out_word_valid.value) == 1:
            break
    # Optionally stall to test backpressure
    for _ in range(settle_cycles):
        await RisingEdge(dut.clk)
        assert int(dut.out_word_valid.value) == 1, "valid must hold while ready=0"
    word = int(dut.out_word.value)
    nbytes = int(dut.out_word_bytes.value)
    dut.out_word_ready.value = 1
    await RisingEdge(dut.clk)
    dut.out_word_ready.value = 0
    return word, nbytes

@cocotb.test()
async def test_exact_8(dut):
    """Push exactly 8 bytes -> get one full word, byte0 in LSB."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.out_word_ready.value = 1  # always ready
    bytes_in = [0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef]
    async def feeder():
        for b in bytes_in:
            await feed_byte(dut, b)
    cocotb.start_soon(feeder())
    word, nbytes = await consume_word(dut)
    expected = 0
    for i, b in enumerate(bytes_in):
        expected |= b << (8 * i)
    assert word == expected, f"word=0x{word:016x} expected=0x{expected:016x}"
    assert nbytes == 8
    dut._log.info(f"PASS exact_8: word=0x{word:016x}")

@cocotb.test()
async def test_two_consecutive(dut):
    """Push 16 bytes -> get two full words back to back."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.out_word_ready.value = 1
    bytes_in = list(range(0x10, 0x20))  # 16 bytes
    async def feeder():
        for b in bytes_in:
            await feed_byte(dut, b)
    cocotb.start_soon(feeder())
    w0, n0 = await consume_word(dut)
    w1, n1 = await consume_word(dut)
    exp0 = sum(bytes_in[i] << (8*i) for i in range(8))
    exp1 = sum(bytes_in[i+8] << (8*i) for i in range(8))
    assert w0 == exp0 and n0 == 8
    assert w1 == exp1 and n1 == 8
    dut._log.info(f"PASS two_consecutive: w0=0x{w0:016x} w1=0x{w1:016x}")

@cocotb.test()
async def test_partial_flush(dut):
    """Push 3 bytes then flush -> get one partial word with bytes=3."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.out_word_ready.value = 1
    async def feeder():
        for b in [0xaa, 0xbb, 0xcc]:
            await feed_byte(dut, b)
        # Hold flush until flush_ready observed
        await RisingEdge(dut.clk)
        dut.flush.value = 1
        # Wait for flush_ready
        while True:
            await RisingEdge(dut.clk)
            if int(dut.flush_ready.value) == 1:
                break
        dut.flush.value = 0
    cocotb.start_soon(feeder())
    word, nbytes = await consume_word(dut)
    expected = 0xaa | (0xbb << 8) | (0xcc << 16)
    assert word == expected, f"partial: word=0x{word:016x} expected=0x{expected:016x}"
    assert nbytes == 3, f"partial: nbytes={nbytes}, expected 3"
    dut._log.info(f"PASS partial_flush: 3 bytes, word=0x{word:016x}")

@cocotb.test()
async def test_partial_all_sizes(dut):
    """Test partial flushes with 1..7 bytes."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for n in range(1, 8):
        await reset(dut)
        dut.out_word_ready.value = 1
        bytes_in = [0x10 + i for i in range(n)]
        async def feeder():
            for b in bytes_in:
                await feed_byte(dut, b)
            await RisingEdge(dut.clk)
            dut.flush.value = 1
            while True:
                await RisingEdge(dut.clk)
                if int(dut.flush_ready.value) == 1:
                    break
            dut.flush.value = 0
        cocotb.start_soon(feeder())
        word, nbytes = await consume_word(dut)
        expected = sum(bytes_in[i] << (8*i) for i in range(n))
        assert nbytes == n, f"size {n}: got nbytes={nbytes}"
        assert (word & ((1 << (8*n)) - 1)) == expected, \
            f"size {n}: word=0x{word:016x} expected=0x{expected:016x}"
    dut._log.info("PASS partial_all_sizes (1..7)")

@cocotb.test()
async def test_backpressure(dut):
    """Push 8 bytes; consumer holds off; verify valid holds, data stable."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    # Consumer not ready initially
    dut.out_word_ready.value = 0
    bytes_in = list(range(0x80, 0x88))
    async def feeder():
        for b in bytes_in:
            await feed_byte(dut, b)
    cocotb.start_soon(feeder())
    # Wait until out_word_valid asserts
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.out_word_valid.value) == 1:
            break
    assert int(dut.out_word_valid.value) == 1
    word_held = int(dut.out_word.value)
    # Stall for 10 cycles, verify data + valid hold
    for _ in range(10):
        await RisingEdge(dut.clk)
        assert int(dut.out_word_valid.value) == 1, "valid dropped under backpressure"
        assert int(dut.out_word.value) == word_held, "data changed under backpressure"
    # Now consume
    dut.out_word_ready.value = 1
    await RisingEdge(dut.clk)
    dut.out_word_ready.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.out_word_valid.value) == 0, "valid should drop after consume"
    expected = sum(bytes_in[i] << (8*i) for i in range(8))
    assert word_held == expected
    dut._log.info(f"PASS backpressure: held word=0x{word_held:016x} stable for 10 cycles")
