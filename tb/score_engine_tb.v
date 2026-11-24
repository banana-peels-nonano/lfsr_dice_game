// -----------------------------------------------------------------------------
// score_engine_tb.v - unit test of the scoring rules, no RNG involved
//
// dice values are driven directly so every rule is hit deterministically:
//   [1] reset state                [4] score > target (overshoot) ends game
//   [2] sum + accumulation         [5] roll_done after game over ignored
//   [3] score == target ends game  [6] clear restores the initial state
//   [7] saturation at 255 (target 255, 8-bit score), no wrap
//   [8] all 36 dice pairs give the right sum
//   [9] roll counter saturates at 255
// prints "SCORE_ENGINE_TB: PASS" or "SCORE_ENGINE_TB: FAIL (n errors)".
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module score_engine_tb;

    reg        clk = 1'b0, rst = 1'b1, clear = 1'b0, roll_done = 1'b0;
    reg  [2:0] die1 = 3'd0, die2 = 3'd0;
    reg  [7:0] target = 8'd20;
    wire [3:0] sum;
    wire [7:0] score, rolls;
    wire       game_over;

    score_engine #(.W(8)) dut (
        .clk(clk), .rst(rst), .clear(clear), .roll_done(roll_done),
        .die1(die1), .die2(die2), .target(target),
        .sum(sum), .score(score), .rolls(rolls), .game_over(game_over));

    always #5 clk = ~clk;
    task tick; begin @(posedge clk); #1; end endtask

    integer errors = 0;
    integer a, b;

    task roll(input [2:0] d1, input [2:0] d2);
        begin
            die1 = d1; die2 = d2; roll_done = 1'b1; tick; roll_done = 1'b0;
            die1 = 3'd0; die2 = 3'd0; tick;      // dice change after the pulse: must not matter
        end
    endtask

    task expect(input [3:0] e_sum, input [7:0] e_score, input [7:0] e_rolls, input e_over);
        begin
            if (sum !== e_sum || score !== e_score || rolls !== e_rolls || game_over !== e_over) begin
                errors = errors + 1;
                $display("  ERROR sum %0d/%0d score %0d/%0d rolls %0d/%0d over %b/%b",
                         sum, e_sum, score, e_score, rolls, e_rolls, game_over, e_over);
            end
        end
    endtask

    initial begin
        tick; tick;
        $display("[1] reset");          expect(0, 0, 0, 0);
        rst = 1'b0; tick;               expect(0, 0, 0, 0);

        $display("[2] accumulation");
        roll(3'd3, 3'd4);               expect(7, 7, 1, 0);
        roll(3'd6, 3'd6);               expect(12, 19, 2, 0);
        $display("[3] score == target ends the game");
        roll(3'd1, 3'd0);  // not a legal die, but the engine just adds: tests exact-equal path
        expect(1, 20, 3, 1);
        $display("[5] roll_done after game over ignored");
        roll(3'd5, 3'd5);               expect(1, 20, 3, 1);

        $display("[6] clear");
        clear = 1'b1; tick; clear = 1'b0; expect(0, 0, 0, 0);

        $display("[4] overshoot ends the game");
        roll(3'd6, 3'd5);               expect(11, 11, 1, 0);
        roll(3'd6, 3'd6);               expect(12, 23, 2, 1);

        $display("[7] saturation at 255");
        clear = 1'b1; tick; clear = 1'b0;
        target = 8'd255;
        for (a = 0; a < 20; a = a + 1) roll(3'd6, 3'd6);     // 240
        expect(12, 240, 20, 0);
        roll(3'd5, 3'd5);               expect(10, 250, 21, 0);
        roll(3'd6, 3'd6);               expect(12, 255, 22, 1);   // 262 saturates

        $display("[8] all 36 pairs");
        target = 8'd255;
        for (a = 1; a <= 6; a = a + 1)
            for (b = 1; b <= 6; b = b + 1) begin
                clear = 1'b1; tick; clear = 1'b0;
                roll(a[2:0], b[2:0]);
                expect(a + b, a + b, 1, 0);
            end

        $display("[9] roll counter saturates");
        clear = 1'b1; tick; clear = 1'b0;
        target = 8'd255;
        for (a = 0; a < 300; a = a + 1) begin
            die1 = 3'd0; die2 = 3'd0; roll_done = 1'b1; tick;   // sum 0 keeps the game running
        end
        roll_done = 1'b0; tick;
        expect(0, 0, 255, 0);

        if (errors == 0) $display("SCORE_ENGINE_TB: PASS");
        else             $display("SCORE_ENGINE_TB: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
