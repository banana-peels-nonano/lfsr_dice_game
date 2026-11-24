#!/usr/bin/env bash
# mutation test: inject known bugs into a scratch copy of the rtl and make
# sure the relevant testbench FAILS. a testbench that passes a broken design
# is not testing anything.   usage: ./tools/mutation_test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CAUGHT=0; TOTAL=0

mutate() {  # description, file, sed-expr, tb, rtl files...
    local desc="$1" file="$2" expr="$3" tb="$4"; shift 4
    TOTAL=$((TOTAL + 1))
    rm -rf "$WORK/rtl"; cp -r "$ROOT/rtl" "$WORK/rtl"
    sed -i "$expr" "$WORK/rtl/$file"
    if cmp -s "$ROOT/rtl/$file" "$WORK/rtl/$file"; then
        echo "  [setup error] mutation did not change $file: $desc"; return
    fi
    local files=()
    for f in "$@"; do files+=("$WORK/rtl/$f"); done
    ( cd "$WORK" && iverilog -g2005 -o m.vvp "$ROOT/tb/$tb" "${files[@]}" 2>/dev/null \
        && vvp -n m.vvp > m.log 2>&1 )
    local passed=0
    grep -q ": PASS" "$WORK/m.log" 2>/dev/null && passed=1
    if [ "${EQUIV:-0}" -eq 1 ]; then
        # known-equivalent mutant: removing a redundant safety gate changes
        # nothing observable, so the testbench is EXPECTED to pass
        if [ $passed -eq 1 ]; then echo "  equiv   $desc"; CAUGHT=$((CAUGHT + 1));
        else echo "  UNEXPECTED FAIL  $desc"; fi
    elif [ $passed -eq 1 ]; then
        echo "  MISSED  $desc"
    else
        echo "  caught  $desc"; CAUGHT=$((CAUGHT + 1))
    fi
    rm -f "$WORK/m.log"
}

CORE=(lfsr16.v die_mapper.v dice_roller.v score_engine.v dice_game.v)
echo "mutation results:"
mutate "lfsr: wrong tap (bit 10 -> bit 11)"            lfsr16.v 's/state\[12\] ^ state\[10\]/state[12] ^ state[11]/' lfsr_tb.v lfsr16.v
mutate "lfsr: zero-seed guard removed"                 lfsr16.v 's/(seed == 16.d0) ? DEFAULT_SEED : seed/seed/' lfsr_tb.v lfsr16.v
mutate "lfsr: shift direction reversed"                lfsr16.v 's/{state\[14:0\], feedback}/{feedback, state[15:1]}/' lfsr_tb.v lfsr16.v
mutate "mapper: code 7 accepted"                       die_mapper.v 's/ \&\& (rnd != 3.d7)//' die_mapper_tb.v lfsr16.v die_mapper.v
mutate "roller: 5 steps per draw (off by one)"         dice_roller.v 's/step_cnt == STEPS - 1/step_cnt == STEPS/' dice_game_tb.v "${CORE[@]}"
mutate "roller: die2 reuses die1 draw"                 dice_roller.v 's/die2   <= face;/die2   <= die1_tmp;/' dice_game_tb.v "${CORE[@]}"
mutate "score: scoring continues after game over"      score_engine.v 's/roll_done \&\& !game_over/roll_done/' score_engine_tb.v score_engine.v
mutate "score: no saturation (wraps)"                  score_engine.v 's/next_score\[W\] ? {W{1.b1}} : next_score\[W-1:0\]/next_score[W-1:0]/' dice_game_tb.v "${CORE[@]}"
mutate "score: > instead of >= target"                 score_engine.v 's/next_score >= /next_score > /' score_engine_tb.v score_engine.v
mutate "roller: clear (new game) ignored"              dice_roller.v 's/if (rst || clear) begin/if (rst) begin/' dice_game_tb.v "${CORE[@]}"
# the two gates below are deliberately redundant (the roller only starts from
# IDLE, and its clear has priority over start); expected to be equivalent
EQUIV=1 mutate "game: roll_req not gated by busy (redundant)"              dice_game.v 's/roll_req \&\& !busy \&\&/roll_req \&\&/' dice_game_tb.v "${CORE[@]}"
EQUIV=1 mutate "game: roll_req not gated by new_game (redundant)" dice_game.v 's/ \&\& !new_game;/;/' dice_game_tb.v "${CORE[@]}"
mutate "button: pulse on release too"                  btn_conditioner.v 's/pulse <= sync1;/pulse <= 1.b1;/' top_tb.v btn_conditioner.v seg7_mux4.v top_module.v "${CORE[@]}"
mutate "button: no debounce (1-cycle accept)"          btn_conditioner.v 's/cnt == STABLE_CYCLES - 1.b1/1/' top_tb.v btn_conditioner.v seg7_mux4.v top_module.v "${CORE[@]}"
mutate "display: digits 0 and 1 swapped"               seg7_mux4.v 's/2.d0:    code = d0;/2'"'"'d0:    code = d1;/' top_tb.v btn_conditioner.v seg7_mux4.v top_module.v "${CORE[@]}"
echo "$CAUGHT of $TOTAL mutations behaved as expected"
[ "$CAUGHT" -eq "$TOTAL" ]
