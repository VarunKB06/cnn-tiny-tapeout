# Verification and Physical-Design Notes

## Functional reference equation

The datapath computes:

`y[r] = x[r] * (w[0] + w[1] + w[2] + w[3])`.

Features and weights are signed INT4 values in the range -8 through +7. The output and accumulator are signed 10-bit values.

## Directed arithmetic vectors

The directed Cocotb arithmetic regression exercises positive and negative values, boundary values, and zero weights.

| Case | Features | Weights | Expected outputs |
|---:|---|---|---|
| 1 | `[1, 2, 3, 4]` | `[1, 2, -1, 1]` | `[3, 6, 9, 12]` |
| 2 | `[2, -3, 7, -8]` | `[4, -2, 1, -1]` | `[4, -6, 14, -16]` |
| 3 | `[7, -8, 0, -1]` | `[7, 7, 7, 7]` | `[196, -224, 0, -28]` |
| 4 | `[-8, 7, -5, 3]` | `[-8, -8, -8, -8]` | `[256, -224, 160, -96]` |
| 5 | `[-8, -1, 1, 7]` | `[-8, 7, -8, 7]` | `[16, 2, -2, -14]` |
| 6 | `[-8, -1, 0, 7]` | `[0, 0, 0, 0]` | `[0, 0, 0, 0]` |
| 7 | `[-7, 5, -2, 6]` | `[-3, 2, 4, -1]` | `[-14, 10, -4, 12]` |

## Cocotb regression

The latest supplied GitHub Actions result reported **6 tests passed, 0 failed**. The suite includes the seven directed arithmetic vectors and the following control/recovery tests:

| Cocotb test | Result | Coverage |
|---|---|---|
| `test_int4_systolic_accelerator_4x4` | PASS | Seven directed signed-INT4 arithmetic vectors. |
| `test_ena_low_during_completion` | PASS | Completion/result-valid retention when `ena` is low, plus result checking. |
| `test_status_signals` | PASS | `busy`, result-valid, output-enable, reserved status bits, and output-byte protocol. |
| `test_reset_during_compute_and_recovery` | PASS | Reset during an active transaction followed by a fresh transaction. |
| `test_repeated_transactions_without_reset` | PASS | Two complete transactions without intervening reset. |
| `test_deterministic_randomized_vectors` | PASS | 20 reproducible signed-INT4 vectors using seed `0xC0C07B`. |
| **Total** | **6 passed, 0 failed** | Latest supplied regression result. |

References:
- [Test workflow history](https://github.com/VarunKB06/cnn-tiny-tapeout/actions/workflows/test.yaml)
- [Tested commit `98a19b3`](https://github.com/VarunKB06/cnn-tiny-tapeout/commit/98a19b3)

The test suite uses a 20 ns clock period (50 MHz), matching `info.yaml` and `src/config.json`. Functional simulation is not a substitute for static timing analysis or physical-design sign-off.

## ENA / completion handshake

The wrapper retains the completion event independently of `ena`. Result-valid remains asserted until all eight result bytes have been read. The corresponding regression checks completion retention when the wrapper is disabled around completion, then verifies the four signed results.

## Latest recorded physical-design snapshot

The metrics below are from [GDS workflow run 38365315668](https://github.com/VarunKB06/cnn-tiny-tapeout/actions/runs/38365315668), commit [`162f691`](https://github.com/VarunKB06/cnn-tiny-tapeout/commit/162f691557bef0d33352218c2a7ba2ffdda59a8d). The GDS archive identifies that commit and run; the user confirmed that `gl_test` succeeded for this workflow. These are EDA flow results, not measurements from fabricated silicon.

| Metric | Recorded result |
|---|---:|
| Standard-cell area | 13,088.8 µm² |
| Core area | 16,493.3 µm² |
| Core utilization | 79.36% |
| Worst setup slack | +6.292 ns |
| Worst hold slack | +0.115 ns |
| Setup violations | 0 |
| Hold violations | 0 |
| Maximum-slew violations under the configured 1.5 ns limit | 0 |
| Maximum-capacitance violations | 0 |
| Maximum-fanout violations | 1 |
| Magic DRC errors | 0 |
| LVS device differences | 0 |
| LVS net differences | 0 |
| Antenna violations | 0 |

## Known physical-design issue

The report identifies one maximum-fanout violation on the root clock buffer (`clkbuf_0_clk/X`), driving 16 loads against a configured limit of 10. The maximum-transition setting is 1.5 ns. Zero reported slew violations means checks pass under that configured threshold; it does not establish that the underlying physical transition improved.

The configuration sets `RUN_KLAYOUT_DRC: 0`, so KLayout DRC was not run and should not be described as passed. Magic DRC, LVS, and antenna results above are reported separately.

## Reproducibility

For future runs, record the full commit SHA, direct GitHub Actions run URL, `src/config.json`, `info.yaml`, and associated GDS logs. Physical metrics may change with RTL, tool versions, PDK revisions, or configuration.
