// -----------------------------------------------------------------------------
// dice_game.v - portable game core: lfsr16 + dice_roller + score_engine
//
// no board i/o here. all inputs are synchronous, single-cycle pulses where
// noted; the board top is responsible for synchronising/debouncing.
//
//   new_game : pulse. reloads the LFSR from 'seed' (0 -> DEFAULT_SEED),
//              aborts any roll in progress, clears dice/score/rolls/game_over.
//   roll_req : pulse. accepted only when not busy, not game over, and not in
//              the same cycle as new_game. requests that arrive while busy
//              are dropped, not queued (one press = at most one roll).
//
// same seed -> same sequence of rolls, by design (reproducible).
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module dice_game #(
    parameter        SCORE_W      = 8,
    parameter [15:0] DEFAULT_SEED = 16'hACE1,
    parameter        STEPS        = 4
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               new_game,
    input  wire [15:0]        seed,
    input  wire               roll_req,
    input  wire [SCORE_W-1:0] target,
    output wire [2:0]         die1,
    output wire [2:0]         die2,
    output wire [3:0]         sum,
    output wire [SCORE_W-1:0] score,
    output wire [7:0]         rolls,
    output wire               busy,
    output wire               game_over,
    output wire               roll_done,
    output wire [15:0]        lfsr_state      // for debug / test only
);

    wire lfsr_step;
    wire roll_start = roll_req && !busy && !game_over && !new_game;

    lfsr16 #(
        .DEFAULT_SEED (DEFAULT_SEED)
    ) u_lfsr (
        .clk   (clk),
        .rst   (rst),
        .load  (new_game),
        .seed  (seed),
        .step  (lfsr_step),
        .state (lfsr_state)
    );

    dice_roller #(
        .STEPS (STEPS)
    ) u_roller (
        .clk       (clk),
        .rst       (rst),
        .clear     (new_game),
        .start     (roll_start),
        .rnd       (lfsr_state[2:0]),
        .lfsr_step (lfsr_step),
        .busy      (busy),
        .done      (roll_done),
        .die1      (die1),
        .die2      (die2)
    );

    score_engine #(
        .W (SCORE_W)
    ) u_score (
        .clk       (clk),
        .rst       (rst),
        .clear     (new_game),
        .roll_done (roll_done),
        .die1      (die1),
        .die2      (die2),
        .target    (target),
        .sum       (sum),
        .score     (score),
        .rolls     (rolls),
        .game_over (game_over)
    );

endmodule
