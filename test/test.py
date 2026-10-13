import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Tiny Tapeout command encoding (uio_in[1:0])
CMD_IDLE = 0b00
CMD_LOAD = 0b01
CMD_START = 0b10
CMD_READ = 0b11


async def tick(dut):
    """Wait for one rising edge and allow nonblocking assignments to settle."""
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")


def encode_int4(value):
    """Return the two's-complement low nibble for a signed INT4 value."""
    assert -8 <= value <= 7, f"{value} is outside the signed INT4 range [-8, 7]"
    return value & 0x0F


def signed16(value):
    """Interpret a 16-bit value as signed two's-complement."""
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


async def idle_cycle(dut):
    dut.ui_in.value = 0
    dut.uio_in.value = CMD_IDLE
    await tick(dut)


async def send_command(dut, command, data=0):
    """Issue one command cycle, then one idle cycle."""
    dut.ui_in.value = data & 0xFF
    dut.uio_in.value = command & 0x03
    await tick(dut)
    await idle_cycle(dut)


async def load_inputs(dut, features, weights):
    """Load features 0..3, followed by weights 0..3."""
    assert len(features) == 4
    assert len(weights) == 4

    for value in list(features) + list(weights):
        await send_command(dut, CMD_LOAD, encode_int4(value))


async def wait_for_output(dut, timeout_cycles=60):
    """Wait for output_valid, then let wrapper enter its output state."""
    for _ in range(timeout_cycles):
        await tick(dut)
        status = int(dut.uio_out.value)

        # Wrapper maps output_valid to uio_out[3].
        if status & 0x08:
            # The wrapper observes done and transitions to ST_OUTPUT
            # on the following clock edge.
            await tick(dut)
            return

    raise AssertionError(
        f"Timed out waiting for output_valid after {timeout_cycles} cycles"
    )


async def read_byte(dut):
    """Capture the current byte and advance the wrapper with CMD_READ."""
    value = int(dut.uo_out.value)
    await send_command(dut, CMD_READ)
    return value


async def run_case(dut, test_id, features, weights):
    """Run one 4x4 INT4 case and compare all four 16-bit results."""
    weight_sum = sum(weights)
    expected = [feature * weight_sum for feature in features]

    dut._log.info(
        "Test %d: features=%s, weights=%s, weight_sum=%d",
        test_id, features, weights, weight_sum
    )
    dut._log.info("Expected outputs: %s", expected)

    await load_inputs(dut, features, weights)
    await send_command(dut, CMD_START)
    await wait_for_output(dut)

    # Read order: output_0 low/high, ..., output_3 low/high.
    data = [await read_byte(dut) for _ in range(8)]
    actual = [
        signed16(data[0] | (data[1] << 8)),
