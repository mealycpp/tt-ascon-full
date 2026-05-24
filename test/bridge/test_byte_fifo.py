import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

async def reset(dut):
    dut.rst_n.value = 0
    dut.wr_en.value = 0
    dut.rd_en.value = 0
    dut.wr_data.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

async def push(dut, b):
    await RisingEdge(dut.clk)
    dut.wr_data.value = b
    dut.wr_en.value = 1
    await RisingEdge(dut.clk)
    dut.wr_en.value = 0

async def pop(dut):
    # Sync to clock edge so combinational rd_data is stable
    await RisingEdge(dut.clk)
    val = int(dut.rd_data.value)
    dut.rd_en.value = 1
    await RisingEdge(dut.clk)
    dut.rd_en.value = 0
    return val

@cocotb.test()
async def test_fifo_basic(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    assert int(dut.empty.value) == 1
    assert int(dut.full.value) == 0
    for i in range(16):
        await push(dut, i + 0x10)
    await ClockCycles(dut.clk, 1)
    assert int(dut.full.value) == 1
    assert int(dut.empty.value) == 0
    got = []
    for _ in range(16):
        got.append(await pop(dut))
    assert got == [i + 0x10 for i in range(16)], f"FIFO order wrong: {got}"
    await ClockCycles(dut.clk, 1)
    assert int(dut.empty.value) == 1
    dut._log.info("PASS fifo_basic")

@cocotb.test()
async def test_fifo_interleaved(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    for i in range(8):
        await push(dut, i)
    for i in range(4):
        v = await pop(dut)
        assert v == i, f"interleave: expected {i} got {v}"
    for i in range(8, 12):
        await push(dut, i)
    for i in range(4, 12):
        v = await pop(dut)
        assert v == i, f"interleave: expected {i} got {v}"
    dut._log.info("PASS fifo_interleaved")

@cocotb.test()
async def test_fifo_full_backpressure(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    # Fill to 16
    for i in range(16):
        await push(dut, i)
    await ClockCycles(dut.clk, 1)  # settle
    assert int(dut.full.value) == 1
    # Try to push when full — should not accept (wr_en gated by !full inside FIFO)
    await push(dut, 0xFF)  # FIFO ignores this
    # Pop one, then we should have room again
    v = await pop(dut)
    await ClockCycles(dut.clk, 1)  # settle for combinational full to drop
    assert v == 0
    assert int(dut.full.value) == 0
    # Push should now succeed
    await push(dut, 0xAA)
    # Drain the rest: 15 original (1..15) + 1 new (0xAA) = 16 items
    rest = []
    for _ in range(16):
        rest.append(await pop(dut))
    expected = list(range(1, 16)) + [0xAA]
    assert rest == expected, f"backpressure drain wrong: {rest}"
    dut._log.info("PASS fifo_full_backpressure")
