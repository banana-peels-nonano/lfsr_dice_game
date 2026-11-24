# Simulation results

All of this was produced by actually running the tools in this repository. Nothing was hand-edited. To regenerate it, run `./sim/run_sim.sh`, `./tools/mutation_test.sh` and `yosys tools/yosys_check.ys`.

| tool | version |
|---|---|
| Icarus Verilog | 12.0 (stable) |
| Verilator (lint only) | 5.020 |
| Yosys | 0.33 |
| Python | 3.13 |
| Vivado | not used for this report; Vivado 2025.2 results are in `vivado_results.md` |

## Summary

| check | result |
|---|---|
| lfsr_tb | PASS |
| die_mapper_tb | PASS |
| score_engine_tb | PASS |
| dice_game_tb | PASS |
| top_tb | PASS |
| 49152 simulated rolls vs independent python model | identical |
| mutation test | 15/15 as expected (13 caught, 2 equivalent) |
| verilator -Wall, core (`dice_game` and below) | 0 warnings |
| verilator -Wall, top | 2 WIDTHTRUNC warnings (intentional integer to 24-bit parameter, guarded), plus UNUSEDSIGNAL for debug outputs that are deliberately unused |
| yosys latch check | no latches |

## Key numbers

| quantity | expected | measured |
|---|---|---|
| LFSR period (5 seeds) | 65535 | 65535 each, no zero, no early repeat |
| low-3-bit codes over all states | 0: 8191, 1..7: 8192 | exact match |
| codes over 65535 draws (4 steps/draw) | same | exact match |
| rejected draws per 65535 | 16383 | 16383 |
| longest run of rejects | 7 (python) | 7 |
| roll latency bound | ≤ 81 cycles | max 56 |
| roll-sequence period | 24576 (python) | 24576, no earlier return |
| faces per die per period | 4096 (python) | 4096 for every face, both dice |
| pair chi-square (35 dof) | ≈35 if truly random | **1.10**: too uniform, LFSR structure |
| pearson(die1, die2) | 0 | 0.00107 |

## Full simulation log

```
================ lfsr_tb ================
[1] reset value
[2] seed load, zero-seed guard, hold, load priority
[3] golden vectors from python model, seed ACE1
[4] full period, several seeds
  seed 0001: period 65535, distinct nonzero states 65535, zero seen 0, early repeat 0
  seed ace1: period 65535, distinct nonzero states 65535, zero seen 0, early repeat 0
  seed ffff: period 65535, distinct nonzero states 65535, zero seen 0, early repeat 0
  seed 8000: period 65535, distinct nonzero states 65535, zero seen 0, early repeat 0
  seed 5a5a: period 65535, distinct nonzero states 65535, zero seen 0, early repeat 0
[5] repeatability: two instances, same seed
  5000 steps identical
  different seeds: 0/100 equal states
[6] reset mid-sequence restores the default-seed sequence
  100 states after reset match the first run
LFSR_TB: PASS
================ die_mapper_tb ================
[1] exhaustive mapping of the 8 codes
[2] every LFSR state once (step every clock)
  all states: code0=8191  faces1..6=8192 8192 8192 8192 8192 8192  code7=8192
[3] decimated draws, 4 steps per draw, 2 x 65535 draws
  65535 draws: code0=8191  faces1..6=8192 8192 8192 8192 8192 8192  code7=8192
  rejected draws 16383 (expected 16383), max consecutive rejects 7 (expected 7)
[4] informational: naive (state % 6)+1 over all states
  faces 1..6 = 10922 10923 10923 10923 10922 10922  (not used by the design)
DIE_MAPPER_TB: PASS
================ score_engine_tb ================
[1] reset
[2] accumulation
[3] score == target ends the game
[5] roll_done after game over ignored
[6] clear
[4] overshoot ends the game
[7] saturation at 255
[8] all 36 pairs
[9] roll counter saturates
SCORE_ENGINE_TB: PASS
================ dice_game_tb ================
[1] reset state
[2] full game, seed 1234, target 50
  game over after 6 rolls, score 51
[3] requests after game over are ignored
[4] same seed replays the same game
  6 rolls replayed, 0 mismatches
[5] extra requests while busy are dropped
  10 extra requests while busy, 1 roll(s) completed, rolls=1
[6] new_game during a roll aborts it
[7] new_game and roll_req in the same cycle
[8] targets 0 and 2: first roll ends the game
[9] target 255 on an 8-bit score, seeds 1..60
  52 of 60 games ended by saturating at 255, none wrapped
[10] latency: max 56 cycles request->roll_done (bound 81)
[11] statistics: 49152 back-to-back rolls, seed ace1
  max latency over the full cycle: 56 cycles
  lfsr at seed again at roll 24576: 1; earlier returns: 0; period-shift mismatches: 0
  24-bit score 344064, model 344064
  die1 faces 1..6: 4096 4096 4096 4096 4096 4096
  die2 faces 1..6: 4096 4096 4096 4096 4096 4096
  pair counts, rows die1 = 1..6, cols die2 = 1..6 (expected 682.67):
    1:  681  689  679  691  680  676
    2:  683  684  684  682  683  680
    3:  688  674  684  676  684  690
    4:  676  683  693  683  677  684
    5:  681  685  683  680  683  684
    6:  687  681  673  684  689  682
  pair min 673 max 693, chi-square (35 dof) = 1.10  (5% critical 49.80)
  sums 2..12: 681 1372 2051 2725 3410 4100 3411 2720 2051 1373 682
  pearson(die1, die2) = 0.00107
  pearson(die2[k], die1[k+1]) = -0.00128
  wrote 49152 rolls to rolls_sim.txt
DICE_GAME_TB: PASS
================ top_tb ================
[1] power-on loads switch seed
[2] initial display
  display: a a 0 0  (expected a a 0 0)
[3] bouncy press -> one roll
  rolls = 1
[4] glitch shorter than debounce -> nothing
[5] display and leds follow the game
  display: 5 5 1 0  (expected 5 5 1 0)
[6] play to game over
  game over after 6 rolls, score 51
  display: 5 2 5 1  (expected 5 2 5 1)
[7] new-game button, switches = 0
  display: a a 0 0  (expected a a 0 0)
TOP_TB: PASS
================ python reference model ================
=== 1. polynomial algebra ===
p(x)      = 0x16801  x^16+x^14+x^13+x^11+1     primitive: True
recip p*  = 0x1002D  x^16+x^5+x^3+x^2+1        primitive: True
control   x^16+x^15+1                       primitive: False
control   x^16+x^14+x^13+x^12+1 (wrong tap) primitive: False
tap bits used by rtl: [15, 13, 12, 10]

=== 2. brute-force period ===
seed 0x0001 -> period 65535
seed 0xACE1 -> period 65535
seed 0xFFFF -> period 65535
seed 0x8000 -> period 65535
distinct states visited from seed 1: 65535 (zero visited: False)

=== 3. golden vectors from seed 0xACE1 ===
after     1 steps: 0x59C3
after     2 steps: 0xB387
after     3 steps: 0x670F
after    16 steps: 0xE455
after   100 steps: 0x4753
after  1000 steps: 0x8A87
after 65534 steps: 0xD670
after 65535 steps: 0xACE1

=== 4. die mapping, exact counts ===
low-3-bit codes over all 65535 states: [8191, 8192, 8192, 8192, 8192, 8192, 8192, 8192]
codes over 65535 decimated draws:     [8191, 8192, 8192, 8192, 8192, 8192, 8192, 8192]
draw sequence returns to seed after 65535 draws: True
max consecutive rejected draws (cyclic): 7

=== 5. naive modulo for comparison (faces 1..6) ===
(state16 % 6)+1 over full period: [10922, 10923, 10923, 10923, 10922, 10922]
(rnd3 % 6)+1 over the 8 codes:    [2, 2, 1, 1, 1, 1]   <- faces 1,2 twice as likely

=== 6. game model ===
roll-sequence period: 24576 rolls (lfsr back at seed)
die1 faces 1..6: [4096, 4096, 4096, 4096, 4096, 4096]
die2 faces 1..6: [4096, 4096, 4096, 4096, 4096, 4096]
both combined  : [8192, 8192, 8192, 8192, 8192, 8192]
pair counts (rows die1=1..6, cols die2=1..6), expected 682.67 each:
   1:  681  689  679  691  680  676
   2:  683  684  684  682  683  680
   3:  688  674  684  676  684  690
   4:  676  683  693  683  677  684
   5:  681  685  683  680  683  684
   6:  687  681  673  684  689  682
pair min/max: 673 / 693   chi2 (35 dof) = 1.10   (5% critical value 49.80)
sum counts 2..12: [681, 1372, 2051, 2725, 3410, 4100, 3411, 2720, 2051, 1373, 682]
expected        : ['682.7', '1365.3', '2048.0', '2730.7', '3413.3', '4096.0', '3413.3', '2730.7', '2048.0', '1365.3', '682.7']
pearson(die1, die2)          = +0.00107
pearson(sum[k], sum[k+1])    = -0.00111
pearson(die2[k], die1[k+1])  = -0.00128
0 rejects between dice   n=18432  pair min/max 512/512
>=3 rejects between      n=  384  pair min/max 7/16
mean draws per die: 1.3333 (ideal 8/6 = 1.3333)

=== 7. what the seed actually selects ===
64 seeds tested: 30 on loop A, 34 on loop B, 0 elsewhere
loop B pair min/max 672/692, chi2 1.13
CROSS-CHECK: PASS (49152 simulated rolls identical to python model)

ALL TESTS PASSED
```

## Mutation test

```
mutation results:
  caught  lfsr: wrong tap (bit 10 -> bit 11)
  caught  lfsr: zero-seed guard removed
  caught  lfsr: shift direction reversed
  caught  mapper: code 7 accepted
  caught  roller: 5 steps per draw (off by one)
  caught  roller: die2 reuses die1 draw
  caught  score: scoring continues after game over
  caught  score: no saturation (wraps)
  caught  score: > instead of >= target
  caught  roller: clear (new game) ignored
  equiv   game: roll_req not gated by busy (redundant)
  equiv   game: roll_req not gated by new_game (redundant)
  caught  button: pulse on release too
  caught  button: no debounce (1-cycle accept)
  caught  display: digits 0 and 1 swapped
15 of 15 mutations behaved as expected
```

## Yosys 7-series mapping (estimate, top_module, CLK_HZ = 100 MHz)

This only shows that the design is synthesizable and latch-free. It is **not** a Vivado utilisation or timing report.

```
   Number of cells:                458
     BUFG                            1
     CARRY4                         30
     FDRE                          164
     FDSE                           21
     IBUF                           19
     LUT2                           48
     LUT3                           15
     LUT4                           10
     LUT5                           32
     LUT6                           49
     MUXF7                           8
     MUXF8                           2
     OBUF                           28
```

## Interpretation

- The period and the face distributions are **exact** and match the theory, not merely "look uniform".
- Pair uniformity is approximate. 24576 rolls cannot split evenly into 36 pairs, and the counts (673 to 693) are far closer to 682.67 than randomness would produce. This is expected from a full-period LFSR and is a limitation, not a success.
- Every seed lands on one of two fixed 24576-roll loops (python section 7). The seed selects a starting point, not a new sequence.
