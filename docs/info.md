# Resource-Shared 4×4 INT4 MAC Accelerator

## How it works

This design processes a four-feature/four-weight workload using four reusable signed INT4 processing elements instead of sixteen simultaneously instantiated PEs. For each feature row `r`, the chain computes:

`output[r] = feature[r] * (weight[0] + weight[1] + weight[2] + weight[3])`.

The controller selects one feature, clears the chain, runs four compute-enabled cycles, captures the result, and repeats for the remaining three features. Signed 10-bit output registers are used because the largest positive result is `(-8) * (-32) = +256`, which cannot be represented in signed 9-bit two's complement.

This is a resource-shared MAC demonstrator for a 4×4 workload, not a fully parallel 16-PE array or general matrix-multiplication/CNN convolution engine.

## How to test

1. Assert reset, then enable the design.
2. Load eight INT4 values using `uio_in[1:0] = 2'b01` (`LOAD`), placing each two's-complement nibble on `ui_in[3:0]`.
3. Load in this order: `feature_0`, `feature_1`, `feature_2`, `feature_3`, `weight_0`, `weight_1`, `weight_2`, `weight_3`.
4. Insert an `IDLE` command (`00`) cycle between commands.
5. Issue `START` (`10`). Wait for `uio_out[3]` (`output_valid`) and allow the wrapper to enter the output state.
6. Read eight bytes using `READ` (`11`), with an `IDLE` cycle between reads. Each output is sent low byte first, then high byte.

The `busy` signal is `uio_out[2]`. Outputs are signed 10-bit values sign-extended to 16 bits for the byte interface.

## External hardware

For physical operation, use a compatible Tiny Tapeout demo board or an external controller capable of providing the Tiny Tapeout clock, reset, enable, input, and command signals and sampling the output/status pins. Follow the electrical and board-specific requirements of the selected Tiny Tapeout platform.

## Current verification notes

The repository's GitHub Actions workflows run Cocotb testing, LibreLane GDS generation, gate-level testing, precheck, and viewer publication. See the main README and workflow runs for the current status. The latest recorded metrics had no setup/hold, max-slew (under the configured 1.5 ns constraint), max-capacitance, DRC, LVS-difference, or antenna violations; one root clock-buffer max-fanout warning remains under review. These are EDA flow results, not measurements from fabricated silicon.
