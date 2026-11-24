#!/usr/bin/env bash
# run every testbench with icarus verilog, then cross-check the game
# against the independent python model. exit code 0 only if all pass.
#   usage: ./sim/run_sim.sh          (from anywhere)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/sim/out"
RTL="$ROOT/rtl"
TB="$ROOT/tb"
mkdir -p "$OUT"
cd "$OUT" || exit 1
FAIL=0

run() {   # name, iverilog args...
    local name="$1"; shift
    echo "================ $name ================"
    if ! iverilog -g2005 -Wall -o "$name.vvp" "$@" 2> "$name.compile.log"; then
        cat "$name.compile.log"; echo "$name: COMPILE FAILED"; FAIL=1; return
    fi
    grep -v "timescale" "$name.compile.log" | grep -v "inherited timescale" || true
    vvp -n "$name.vvp" | tee "$name.log"
    grep -q ": PASS" "$name.log" || FAIL=1
}

run lfsr_tb       "$TB/lfsr_tb.v"       "$RTL/lfsr16.v"
run die_mapper_tb "$TB/die_mapper_tb.v" "$RTL/lfsr16.v" "$RTL/die_mapper.v"
run score_engine_tb "$TB/score_engine_tb.v" "$RTL/score_engine.v"
run dice_game_tb  "$TB/dice_game_tb.v"  "$RTL/lfsr16.v" "$RTL/die_mapper.v" \
                  "$RTL/dice_roller.v" "$RTL/score_engine.v" "$RTL/dice_game.v"
run top_tb        "$TB/top_tb.v"        "$RTL"/*.v

echo "================ python reference model ================"
python3 "$ROOT/tools/ref_model.py" "$OUT" | tee ref_model.log
if diff -q rolls_sim.txt rolls_ref.txt > /dev/null; then
    echo "CROSS-CHECK: PASS (49152 simulated rolls identical to python model)"
else
    echo "CROSS-CHECK: FAIL (rolls_sim.txt differs from rolls_ref.txt)"; FAIL=1
fi

echo
if [ "$FAIL" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$FAIL"
