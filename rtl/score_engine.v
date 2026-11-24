// -----------------------------------------------------------------------------
// score_engine.v - game rules, independent of how the dice are produced
//
// default game ("race to target"):
//   * each completed roll adds die1 + die2 (2..12) to the score
//   * the roll counter counts completed rolls (saturates at 255)
//   * when score >= target the game is over; further rolls are ignored
//   * clear (new game) or rst returns everything to zero
//   * target = 0 means the first roll ends the game
//   * a lower roll count at game over is a better result
//
// the score saturates at 2^W - 1 instead of wrapping. saturation can only be
// reached when target > 2^W - 13; saturated score >= any target, so the game
// still ends correctly.
//
// to change the rules, replace this module; the interface is just
// roll_done + die1 + die2 in, score state out.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module score_engine #(
    parameter W = 8                         // score width
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         clear,
    input  wire         roll_done,          // 1-cycle pulse from the roller
    input  wire [2:0]   die1,
    input  wire [2:0]   die2,
    input  wire [W-1:0] target,
    output reg  [3:0]   sum,                // last roll's sum, 0 before first roll
    output reg  [W-1:0] score,
    output reg  [7:0]   rolls,
    output reg          game_over
);

    generate
        if (W < 4) begin : g_bad_param
            ERROR_score_engine_W_must_be_at_least_4 u_error ();
        end
    endgenerate

    wire [3:0] roll_sum  = {1'b0, die1} + {1'b0, die2};      // max 12, fits 4 bits
    wire [W:0] next_score = {1'b0, score} + {{(W-3){1'b0}}, roll_sum};

    always @(posedge clk) begin
        if (rst || clear) begin
            sum       <= 4'd0;
            score     <= {W{1'b0}};
            rolls     <= 8'd0;
            game_over <= 1'b0;
        end else if (roll_done && !game_over) begin
            sum   <= roll_sum;
            score <= next_score[W] ? {W{1'b1}} : next_score[W-1:0];
            if (rolls != 8'hFF)
                rolls <= rolls + 8'd1;
            if (next_score >= {1'b0, target})
                game_over <= 1'b1;
        end
    end

endmodule
