# Verification and Physical-Design Notes

## Functional test vectors

The Cocotb suite exercises positive and negative INT4 values, boundary values, and zero weights. Expected outputs follow the current datapath equation:

`y[r] = x[r] * (w[0] + w[1] + w[2] + w[3])`.

| Case | Features | Weights | Expected outputs |
|---:|---|---|---|
| 1 | `[1, 2, 3, 4]` | `[1, 2, -1, 1]` | `[3, 6, 9, 12]` |
| 2 | `[2, -3, 7, -8]` | `[4, -2, 1, -1]` | `[4, -6, 14, -16]` |
| 3 | `[7, -8, 0, -1]` | `[7, 7, 7, 7]` | `[196, -224, 0, -28]` |
| 4 | `[-8, 7, -5, 3]` | `[-8, -8, -8, -8]` | `[256, -224, 160, -96]` |
| 5 | `[-8, -1, 1, 7]` | `[-8, 7, -8, 7]` | `[16, 2, -2, -14]` |
| 6 | `[-8, -1, 0, 7]` | `[0, 0, 0, 0]` | `[0, 0, 0, 0]` |
| 7 | `[-7, 5, -2, 6]` | `[-3, 2, 4, -1]` | `[-14, 10, -4, 12]` |

Run the test workflow from GitHub Actions for the exact CI result of a given commit.

## Enable / completion handshake regression

The wrapper latches the core completion event independently of `ena`, because the core continues computing even when the wrapper is disabled. `uio_out[3]` is therefore a result-valid/ready level: it remains asserted until all eight result bytes have been read. The added `test_ena_low_during_completion` test drops `ena` immediately after completion becomes visible, holds it low for several cycles, re-enables the wrapper, and checks all four signed results. This test has been added to the suite but must be run in the project's simulation environment before its pass status is claimed.

## Recorded physical-design results

Source: the successful LibreLane GDS artifact's `runs/wokwi/final/metrics.csv`.

| Metric | Value |
|---|---:|
| Standard-cell area | 13,098.8 µm² |
| Core area | 16,493.3 µm² |
| Core utilization | 79.42% |
| Setup worst slack | +6.383 ns |
| Hold worst slack | +0.110 ns |
| Setup violations | 0 |
| Hold violations | 0 |
| Maximum-slew violations under the configured 1.5 ns limit | 0 |
| Maximum-capacitance violations | 0 |
| Maximum-fanout violations | 1 |
| Magic DRC errors | 0 |
| LVS device differences | 0 |
| LVS net differences | 0 |
| Antenna violations | 0 |

## Known issue

The metrics report one maximum-fanout violation on the root clock buffer (`clkbuf_0_clk/X`), which drives 16 loads against a configured limit of 10. The design's maximum-transition setting is 1.5 ns; zero reported slew violations means the checks pass under that threshold, not that the transition was physically improved by the setting. Obtain guidance for the intended shuttle before deciding if more clock-tree changes are required.

## Reproducibility

Record the commit SHA, GitHub Actions run URL, `src/config.json`, `info.yaml`, and the downloaded GDS logs when capturing new results. Metrics can change when RTL, tool versions, PDK revisions, or configuration changes.
