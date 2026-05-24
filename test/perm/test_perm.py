import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

VECTORS = [
    ("all_zeros_p12", 12,
     0x00000000000000000000000000000000000000000000000000000000000000000000000000000000,
     0x045d648e4def12c93fe53f36f2c1178c6937f83e03d11a509b9bfb8513b560f778ea7ae5cfebb108),
    ("all_zeros_p8", 8,
     0x00000000000000000000000000000000000000000000000000000000000000000000000000000000,
     0x0168260badf76a06f01fdabf8c8a82b4a01ef761bf8e1652a5425f1f8cb313881418f8af721aa830),
    ("hash256_iv_p12", 12,
     0x00000000000000000000000000000000000000000000000000000000000000000200cc0100080000,
     0x665c13d9648d86b48871f7d6d9e5cd88cc40dc8c3687dbee8b7e48cc62f6d2bccb97391be958107b),
    ("hash256_iv_p8", 8,
     0x00000000000000000000000000000000000000000000000000000000000000000200cc0100080000,
     0x0557f4ac104d6552dcc4ec45bf112860fe0c8e94445137c76cb2688c30fd9a4fc9aba640114c721d),
    ("rand_state_p12", 12,
     0x55556666777788881111222233334444deadbeefcafebabefedcba98765432100123456789abcdef,
     0x1d6a56c1dfecb63301df218adc637980afcb07c029b31a88436e5a68c17c1bd9f0719fc1fdb1114e),
    ("rand_state_p8", 8,
     0x55556666777788881111222233334444deadbeefcafebabefedcba98765432100123456789abcdef,
     0x4359ff48adcb94573589335b426c3575b157f02607e7c4a43babae9e0616fcb3f65e85f086b5638d),
]

async def reset(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.num_rounds.value = 0
    dut.state_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

async def run_perm(dut, num_rounds, state_in):
    dut.num_rounds.value = num_rounds
    dut.state_in.value = state_in
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    for _ in range(50):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            return int(dut.state_out.value)
    raise RuntimeError("done never asserted")

@cocotb.test()
async def test_all_vectors(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    fails = 0
    for name, rounds, s_in, expected in VECTORS:
        await reset(dut)
        got = await run_perm(dut, rounds, s_in)
        if got == expected:
            dut._log.info(f"PASS {name}")
        else:
            dut._log.error(f"FAIL {name}")
            dut._log.error(f"  expected: {expected:080x}")
            dut._log.error(f"  got:      {got:080x}")
            fails += 1

    assert fails == 0, f"{fails}/{len(VECTORS)} vectors failed"
