// -----------------------------------------------------------------------------
// die_mapper.v - 3 random bits -> one six-sided die face, by rejection
//
//   rnd  : 0  1  2  3  4  5  6  7
//   face : -  1  2  3  4  5  6  -        (- = rejected, valid = 0)
//
// why: 8 codes cannot be split evenly into 6 faces, so any fixed mapping of
// all 8 codes is biased (rnd % 6 + 1 makes faces 1 and 2 twice as likely).
// rejecting 2 of 8 codes leaves 6 equally likely codes. choosing 0 and 7 as
// the rejected codes means the accepted code *is* the face: no adder, no
// modulo, just a 3-input compare. purely combinational.
//
// cost: 25% of draws are rejected, mean draws per face = 8/6 = 1.333.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module die_mapper (
    input  wire [2:0] rnd,
    output wire       valid,
    output wire [2:0] face     // 1..6 when valid, 0 when rejected
);

    assign valid = (rnd != 3'd0) && (rnd != 3'd7);
    assign face  = valid ? rnd : 3'd0;

endmodule
