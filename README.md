# LFSR Random Number Generator and Dice Game

A 16-bit maximal-length LFSR with a loadable seed drives a two-dice game with scoring. Sequence length and dice distribution are checked in simulation with self-checking testbenches. Every simulated roll is also compared against an independent Python model.

Target: Xilinx Spartan-7 (board not chosen yet), Vivado. The RTL is plain Verilog-2001. The core uses no vendor primitives.

## Status

| item | status |
|---|---|
| RTL (8 modules) | done, lint-clean (verilator `-Wall`; see note on the top) |
| simulation (icarus 12) | **5/5 testbenches PASS, cross-check PASS**, see `reports/simulation_results.md` |
| testbench strength | 15/15 injected bugs behave as expected (`tools/mutation_test.sh`) |
| synthesizability | yosys `synth_xilinx -family xc7`: no latches, 185 FFs, ~118 LCs (yosys estimate) |
| vivado 2025.2 simulation | all 5 testbenches PASS in xsim, with the same finish times as icarus |
| vivado synthesis + implementation | 124 LUT / 170 FF, **WNS +5.057 ns at 100 MHz**, on a placeholder part (`xc7s50csga324-1`) with clock-only constraints, see `reports/vivado_results.md` |
| board / pins / bitstream / hardware test | **not done**: no board selected yet |

The timing above covers internal paths only. Real pin placement, a board XDC and a hardware test are still outstanding (see "remaining tasks").

## Where to start (for the team)

Read in this order. Each step builds on the previous one.

1. **sections 3–4 of this README**: why this polynomial, and why rejection sampling with 4 steps per draw. This is the actual engineering.
2. **`rtl/lfsr16.v` → `rtl/die_mapper.v` → `rtl/dice_roller.v`**: the random-number path. These files are short and heavily commented.
3. **`rtl/score_engine.v` → `rtl/dice_game.v`**: the game rules and how the pieces connect.
4. **`tb/lfsr_tb.v`**: how a self-checking testbench proves a period, rather than eyeballing waveforms.
5. **`tools/ref_model.py`**: the same design written independently in Python. Simulation output is diffed against it.
6. **`tools/mutation_test.sh`**: how to check that the testbenches can actually fail.
7. **`rtl/btn_conditioner.v`, `rtl/seg7_mux4.v`, `rtl/top_module.v`**: the hardware-facing part (metastability, debouncing, display multiplexing, clock enables).

To try it: run `./sim/run_sim.sh`. Then break something in `rtl/` (flip a tap, change `STEPS`) and watch a testbench fail.

---

## 1. Requirements, ambiguities and decisions

The one-line brief ("LFSR-based generator with a seed and a two-dice game with scoring; sequence length and uniformity checked in simulation") leaves a lot open. These are the decisions taken. Each one is isolated so it can be changed.

| question | decision | why / where to change |
|---|---|---|
| LFSR width and polynomial | 16-bit Fibonacci, p(x) = x^16+x^14+x^13+x^11+1 | proven primitive (sec. 3); `lfsr16.v` |
| what happens on reset | `rst` loads `DEFAULT_SEED` = 0xACE1 | parameter |
| how the seed gets in | `new_game` loads the `seed` port (switches on the board) | `dice_game.v` |
| seed = 0 | replaced by `DEFAULT_SEED` (all-zero locks an LFSR) | `lfsr16.v` |
| deterministic or "fun" | deterministic: the same seed always gives the same game | the alternative (step the LFSR every idle clock so press timing adds entropy) is a ~1-line change but breaks reproducibility, so it was left out |
| bits to die face | rejection sampling on 3 bits, reject codes 0 and 7 | sec. 4; `die_mapper.v` |
| LFSR steps per draw | 4 | sec. 4; `STEPS` parameter |
| game rules | race to target: add die1+die2 every roll, game over at score >= target, fewer rolls is better | `score_engine.v` only |
| default target | 50 (top parameter) | `TARGET` |
| roll press while a roll is running | dropped, not queued | `dice_game.v` |
| new game during a roll | aborts the roll and clears everything | `dice_roller.v` |
| score overflow | saturates, never wraps | `score_engine.v` |
| display | 4-digit 7-seg: `[die1][die2][score tens][score ones]`, dp = game over; LEDs show rolls/sum/game over | `top_module.v`, adapt to the board |

Still open, and only you can answer these (all of them sit in `top_module.v` / XDC):

1. Exact board / part number, clock frequency, and which clock pin.
2. Number of switches (16 assumed for the seed), buttons, LEDs, and whether a 7-seg display exists (4 digits assumed).
3. Button, segment and anode polarity.
4. Whether a dedicated reset button is wanted (currently: power-on reset + "new game" button).

---

## 2. Architecture

```
                         top_module.v  (board wrapper, only board-specific RTL)
 btn_new_game ─► btn_conditioner ──┐
 btn_roll ─────► btn_conditioner ──┼─ pulses ─┐
 sw_seed[15:0] ─► 2-FF sync ───────┘          │
 power-on counter ── rst, auto new_game ──────┤
                                              ▼
        ┌──────────────────────── dice_game.v (portable core) ─────────────────────┐
        │  lfsr16 ──state[2:0]──► dice_roller ──die1,die2,done──► score_engine     │
        │     ▲ step ◄──────────────┘  (contains die_mapper)     sum,score,rolls,  │
        │     └ load/seed (new_game)                             game_over         │
        └──────────────────────────────────────────────────────────────────────────┘
                                              │
                       to_bcd2 ─► seg7_mux4 ──┴─► seg[6:0], dp, an[3:0], led[15:0]
```

| file | role | depends on |
|---|---|---|
| `rtl/lfsr16.v` | PRNG: rst/load/step, zero-seed guard | none |
| `rtl/die_mapper.v` | 3 bits to face or reject (combinational) | none |
| `rtl/dice_roller.v` | FSM: draws, rejects, commits two dice atomically | die_mapper |
| `rtl/score_engine.v` | game rules: sum, score, rolls, game over | none (no RNG knowledge) |
| `rtl/dice_game.v` | core integration and roll-request gating | the four above |
| `rtl/btn_conditioner.v` | 2-FF sync, debounce, press pulse | none |
| `rtl/seg7_mux4.v` | 4-digit multiplexed 7-seg driver (clock-enable) | none |
| `rtl/top_module.v` | board wrapper: POR, inputs, display, LEDs | everything |

`dice_roller` is a module that was not in the original suggested list. It keeps the "how to get two valid dice out of a bit stream" FSM separate from the "what is the game" rules (`score_engine`) and from the bit source (`lfsr16`). Each of the three can be swapped without touching the others.

Design rules followed throughout:
- one clock, all registers on `posedge clk`
- synchronous active-high resets
- slow things (debounce, display refresh) use clock-enable counters, never derived clocks
- non-blocking assignments in sequential blocks
- every combinational `case` has a default (no latches; yosys asserts this)
- bad parameters stop elaboration (a reference to a non-existent `ERROR_...` module inside a `generate if`)

---

## 3. LFSR mathematics

**Register.** Fibonacci form, shifting toward the MSB, with the new bit entering `state[0]`:

```
state_next = { state[14:0], state[15] ^ state[13] ^ state[12] ^ state[10] }
```

**Polynomial.** Writing b_n for the bit entering at step n, the register holds b_{n-1} in bit 0 through b_{n-16} in bit 15, so the update is the recurrence

  b_n = b_{n-16} ⊕ b_{n-14} ⊕ b_{n-13} ⊕ b_{n-11}

Its characteristic polynomial is x^16 + x^5 + x^3 + x^2 + 1. That is the reciprocal of p(x) = x^16 + x^14 + x^13 + x^11 + 1, which is the "taps 16, 14, 13, 11" form usually listed. A polynomial is primitive if and only if its reciprocal is, so the two descriptions are equivalent.

**Why the period is 65535.** A degree-n polynomial over GF(2) is primitive exactly when x has multiplicative order 2^n − 1 modulo p(x). Here 2^16 − 1 = 65535 = 3 · 5 · 17 · 257, so it is enough to check:

- x^65535 ≡ 1 (mod p)
- x^(65535/q) ≢ 1 (mod p) for each q in {3, 5, 17, 257}

`tools/ref_model.py` checks both conditions with exact GF(2) arithmetic, and both p and its reciprocal pass. As negative controls, x^16+x^15+1 and a one-tap-off variant fail. For a primitive characteristic polynomial, the LFSR steps through all 2^16 − 1 nonzero states before repeating. The update is also invertible (the tap on bit 15 means the oldest bit can be recovered) and maps 0 to 0, so a nonzero state can never become zero.

**The polynomial was not taken on trust.** It was checked three independent ways:

1. algebraically, as above
2. by brute force in Python
3. in the actual Verilog: `lfsr_tb` steps 5 different seeds through a full cycle with a 65536-entry visited table. Each run gave period 65535, every nonzero state exactly once, no zero, and no early repeat.

The testbench also checks golden values produced by the Python model.

---

## 4. Dice mapping

**Why naive modulo is wrong.**
- Taking 3 bits and computing `rnd % 6 + 1`: the 8 codes map 2, 2, 1, 1, 1, 1 onto faces 1–6, so faces 1 and 2 come up twice as often.
- Taking the whole 16-bit state, `state % 6 + 1`: the bias is tiny (10922 vs 10923 over a period), but it costs a 16-bit modulo for no reason.

**What is used: rejection sampling.** Take 3 fresh bits (8 equally likely codes), reject 0 and 7, and keep 1–6. The accepted code *is* the face, so the mapper is one 3-input compare with no arithmetic. Each draw is accepted with probability 6/8, so a die needs 4/3 draws on average.

**Why 4 LFSR steps per draw.**
- It must be at least 3. Otherwise consecutive draws share bits and are directly correlated (with 1 step per draw, the next code is `(prev<<1 | newbit) & 7`).
- It must be coprime to 65535. With gcd(4, 65535) = 1, 65535 consecutive draws visit every LFSR state exactly once. With 3 or 5 steps, which divide 65535, only a third or a fifth of the states would ever be sampled.

**Exact counts this gives**, checked in `die_mapper_tb` rather than eyeballed. An m-sequence contains every nonzero 16-bit state once, so over one draw period each nonzero 3-bit pattern appears 2^13 times and `000` appears 2^13 − 1 times:

| code | 0 (reject) | 1 | 2 | 3 | 4 | 5 | 6 | 7 (reject) |
|---|---|---|---|---|---|---|---|---|
| count / 65535 draws | 8191 | 8192 | 8192 | 8192 | 8192 | 8192 | 8192 | 8192 |

**Rejection is bounded.** Over the whole cycle the longest run of rejected draws is 7. The cycle is the same for every seed, so this holds for every seed. Worst-case roll latency is therefore 1 + 2·8·5 = 81 cycles (0.81 µs at 100 MHz). The longest latency observed over a full cycle was 56 cycles.

**Uniform faces are not the same as independent dice.** These are different claims, and they were checked separately:

- *Faces.* Over the 24576-roll period, die1 and die2 each show every face exactly 4096 times.
- *Pairs.* The 36 (die1, die2) pairs are **not** exactly uniform, and cannot be: 24576/36 = 682.67 is not an integer. Observed counts run from 673 to 693.
  - When no reject falls between the two dice, the two 3-bit windows lie inside one 16-bit span, and all 36 pairs come out exactly 512 times each.
  - When 3 or more rejects fall between them (384 rolls), the span exceeds 16 bits, the LFSR's linear recurrence couples the bits, and pair counts range from 7 to 16.
- *Too uniform to be random.* The pair chi-square is 1.10 with 35 degrees of freedom. A truly random source would give about 35, and values that low would almost never occur. This is the classic signature of a full-period LFSR: a balanced, structured sequence, not a random one.

---

## 5. Game rules (default)

1. Power-up or **new game**: score 0, rolls 0, dice blank, and the LFSR is loaded from the seed switches.
2. **Roll**: two dice appear together. Their sum is added to the score and the roll counter goes up by 1.
3. When score ≥ target (50 by default), the game is over: the right-hand decimal point and `led[15]` light, and further rolls are ignored.
4. The aim is to reach the target in as few rolls as possible.
5. The same seed always plays the same game. Use different switch settings for different games.

Edge cases, all tested:
- target 0 ends the game after the first roll
- the score saturates instead of wrapping
- the roll counter saturates at 255
- presses during a roll are dropped
- new game during a roll aborts it cleanly

---

## 6. Verification

Run everything with `./sim/run_sim.sh`. It needs `iverilog` (≥ 11) and `python3` and exits 0 only if every check passes.

| testbench | what it proves |
|---|---|
| `tb/lfsr_tb.v` | reset value; seed load; zero-seed guard; hold; priority rst > load > step; golden vectors; full period 65535 / no zero / no early repeat for 5 seeds; repeatability; mid-sequence reset |
| `tb/die_mapper_tb.v` | all 8 codes; exact counts over every state and over 65535 decimated draws; 16383 rejects; max reject run 7 |
| `tb/score_engine_tb.v` | rules with directly driven dice: accumulation, ==target, overshoot, ignore after game over, clear, saturation, all 36 sums, roll-counter saturation |
| `tb/dice_game_tb.v` | scoreboard on every roll; replay; busy/abort/same-cycle cases; target edges; saturation over 60 seeds; latency bound; 49152-roll statistics; roll period exactly 24576 |
| `tb/top_tb.v` | power-on seed load; bouncing press gives exactly one roll; short glitch ignored; 7-seg contents decoded; LEDs; game-over dp; new-game button |
| `tools/ref_model.py` | independent model (primitivity, brute-force period, golden vectors, dice model). All 49152 simulated rolls are diffed against it |
| `tools/mutation_test.sh` | injects 15 known bugs; 13 are caught. The other 2 remove deliberately redundant safety gates in `dice_game.v` and are correctly reported as equivalent |
| `tools/yosys_check.ys` | no latches; maps to 7-series cells |

---

## 7. Limitations (stated plainly)

- **Not random, not secure.** An LFSR is a linear function of its state. Seeing 16 consecutive output bits reveals the state, and everything after that is predictable. Never use this for anything security-related or for real-money gambling.
- **The seed picks a starting point, not a new sequence.** All nonzero seeds lie on the same 65535-state cycle. The dice stream repeats every 24576 rolls, and every seed lands somewhere on one of exactly two fixed 24576-roll loops (64 seeds tested: 30 on loop A, 34 on loop B). 65535 seeds are 65535 starting points, not 65535 different games.
- **The pair distribution is close to uniform but not exact** (sec. 4). Its statistics are "too good", which is a property of LFSRs, not something a random source would show.
- **Deterministic by design.** The same seed and the same presses give the same game. That is good for testing and reproducibility, but it is not what "rolling dice" means to a player.

Ways to improve this, none of which are implemented:
- step the LFSR while idle (user timing becomes entropy)
- use a larger LFSR or an xorshift generator
- combine two LFSRs with coprime periods
- for real entropy, a ring-oscillator TRNG (vendor- and placement-specific)

---

## 8. Getting it into Vivado

**Quickest: run the script.** From the repo root:

```
vivado -mode batch -source vivado/create_project.tcl
```

or `source <repo>/vivado/create_project.tcl` in the Vivado Tcl console. This creates `vivado_proj/` (git-ignored). It adds rtl/ and tb/ (referenced, not copied) plus `constraints/timing.xdc`, sets the tops, and sets the sim runtime to `all`. Then open `vivado_proj/lfsr_dice.xpr`. The individual commands were run in Vivado 2025.2. The script that wraps them with repo-relative paths was checked with a tclsh dry run, with the Vivado commands stubbed out, to confirm the file paths resolve. It has not yet been run inside Vivado itself.

**File order** when typing the files in by hand (each file only uses modules from files before it):

1. `die_mapper.v`
2. `lfsr16.v`
3. `dice_roller.v`
4. `score_engine.v`
5. `dice_game.v`
6. `btn_conditioner.v`
7. `seg7_mux4.v`
8. `top_module.v`

Then the testbenches: `lfsr_tb.v`, `die_mapper_tb.v`, `score_engine_tb.v`, `dice_game_tb.v`, `top_tb.v`.

**Project setup:**
1. Create an RTL project and pick your board's part.
2. Add `rtl/*.v` as design sources and set `top_module` as top.
3. Add `tb/*.v` as simulation sources. In the simulation set, set the top to the testbench you want to run.
4. **Simulation run time:** xsim stops at 1000 ns by default. Set *Settings → Simulation → xsim.simulate.runtime* to `all`, or type `run all` in the Tcl console. Every testbench ends itself with `$finish` and prints `..._TB: PASS` or `FAIL`.
5. `dice_game_tb` simulates about 7.9 ms (≈790k clocks). In xsim 2025.2 this took about 8 s of wall-clock time.
6. `dice_game_tb` writes `rolls_sim.txt` into the xsim run directory (`<project>.sim/sim_1/behav/xsim/`). To repeat the Python cross-check, run `python3 tools/ref_model.py <dir>` and diff `rolls_ref.txt` against it.

**Synthesis and implementation** run with just `constraints/timing.xdc`, which contains only the clock and no pins. Do not generate a bitstream until a board XDC exists: it will fail DRC on unplaced I/O.

**Note on lint:** verilator warns that the integer parameters passed into the 24-bit counter parameters are truncated. This is intentional and guarded: `top_module` refuses any `CLK_HZ` setting whose counts do not fit in 24 bits.

---

## 9. Remaining tasks before running on a real Spartan-7

1. Choose the board. Fill in the part number, clock pin/frequency and the I/O pin map in an XDC (template in `constraints/`).
2. Set the top parameters to match the board: `CLK_HZ`, `BTN_ACTIVE_LOW`, `SEG_ACTIVE_LOW`, `AN_ACTIVE_LOW`. If there are fewer than 16 switches, tie the unused `sw_seed` bits in the top. If there is no 7-seg display, drop `seg7_mux4` and map die1, die2 and score to LEDs.
3. Decide whether a dedicated reset button is wanted. The power-on reset relies on registers initialising to 0 after configuration, which 7-series parts do; that one line is the only FPGA-specific assumption.
4. Re-run Vivado synthesis and implementation on the real part with the real XDC. Done so far on the placeholder part: 124 LUT / 170 FF, WNS +5.057 ns. Still to confirm:
   - the 15 trimmed FFs are the never-set counter MSBs (`Synth 8-3333`)
   - the 46 methodology warnings are TIMING-18 (`report_methodology`)
   - no latches appear in the synthesis log
5. Check that `ASYNC_REG` was applied to the synchroniser pairs, and that no `set_false_path` is needed (the buttons and switches are asynchronous, synchronised, and do not need timing constraints).
6. On hardware:
   - the same seed must give the same game every time
   - bouncy buttons must give exactly one roll per press
   - display brightness and ghosting should be acceptable (tune `DIGIT_HZ`)
7. Optional: add an ILA on `lfsr_state`, `die1`, `die2` and `score` for on-chip debug.

---

## Files

```
lfsr_dice_game/
├── rtl/          lfsr16, die_mapper, dice_roller, score_engine, dice_game,
│                 btn_conditioner, seg7_mux4, top_module
├── tb/           lfsr_tb, die_mapper_tb, score_engine_tb, dice_game_tb, top_tb
├── sim/          run_sim.sh  (writes logs to sim/out/, git-ignored)
├── tools/        ref_model.py, mutation_test.sh, yosys_check.ys
├── constraints/  README.md, timing.xdc (clock only),
│                 template.xdc (pin placeholders only, no invented pins)
├── vivado/       create_project.tcl
├── reports/      simulation_results.md, vivado_results.md
├── .gitignore, LICENSE (MIT)
└── README.md
```

## License

MIT, see `LICENSE`.
