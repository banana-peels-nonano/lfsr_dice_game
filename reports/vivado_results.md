# Vivado results

These numbers come from a run on a team member's machine (Linux, **Vivado 2025.2**). They were transcribed from screenshots of that session, not from exported report files. When the project is re-run, export `report_utilization` and `report_timing_summary` and add them here.

The setup was:
- part `xc7s50csga324-1`, a placeholder because no board has been chosen
- constraints: only `create_clock -period 10.000` (`constraints/timing.xdc`), no pin assignments

## Behavioural simulation (xsim)

| testbench | result | `$finish` time, xsim | same run, Icarus 12 |
|---|---|---|---|
| lfsr_tb | PASS | 3,993,086 ns | 3,993,086 ns |
| die_mapper_tb | PASS | 5,898,186 ns | 5,898,186 ns |
| score_engine_tb | PASS | 4,706 ns | 4,706 ns |
| dice_game_tb | PASS | 7,900,916 ns | 7,900,916 ns |
| top_tb | PASS | 14,156 ns | 14,156 ns |

Both simulators finish every testbench at the same simulated time. `dice_game_tb` took about 8 s of wall-clock time in xsim. `top_tb` elaborating and passing confirms that the `ERROR_...` entries shown in Vivado's Sources hierarchy are only the parameter guards inside false `generate` branches. They are never instantiated.

## Synthesis (`synth_1`, default strategy)

| LUT | FF | BRAM | URAM | DSP |
|---|---|---|---|---|
| 127 | 170 | 0 | 0 | 0 |

The RTL contains 185 flip-flops by hand count, and Yosys keeps all 185. The difference of 15 is *believed* to be the counter MSBs that can never be set:
- the debounce counters stop at 999,999 < 2^20, so bits 20–23 are unused: 2 × 4 = 8
- the display counter stops at 99,999 < 2^17, so bits 17–23 are unused: 7

This has **not yet been confirmed** against the synthesis log (look for `Synth 8-3333` messages).

## Implementation (`impl_1`, default strategy)

| WNS | TNS | WHS | THS | TPWS | failed routes | LUT | FF | total power |
|---|---|---|---|---|---|---|---|---|
| +5.057 ns | 0.000 | +0.124 ns | 0.000 | 0.000 | 0 | 124 | 170 | 0.075 W |

- Setup and hold are met at 100 MHz. The worst internal path is about 4.94 ns, which would allow roughly 200 MHz.
- These figures cover internal paths only. The I/O was placed automatically because there are no pin constraints yet.
- Methodology checks report **46 warnings**. This number equals the count of I/O ports (18 inputs + 28 outputs), so they are *expected* to be TIMING-18 (missing input/output delay). That is **not yet confirmed** with `report_methodology`. `constraints/timing.xdc` contains the false-path lines that should clear them.
- No bitstream was generated. It would fail DRC on the unplaced I/O until there is a board XDC.
