// -----------------------------------------------------------------------------
// top_tb.v - smoke test of the board wrapper (top_module) with fast timing
//
// CLK_HZ = 10 kHz and DEBOUNCE_MS = 1 give a 10-cycle debounce; DIGIT_HZ =
// 1000 gives 10 cycles per display digit. same logic, shorter counters.
//   [1] power-on: auto new_game loads the switch seed
//   [2] display before the first roll shows "- - 0 0"
//   [3] a bouncing press + bouncing release = exactly one roll
//   [4] a glitch shorter than the debounce time = no roll
//   [5] seven-segment digits and LEDs match the game state
//   [6] play to game over: same result as dice_game_tb (seed 1234: 6 rolls,
//       score 51), dp lit on the right digit, presses after that ignored
//   [7] new-game button with switches = 0 -> default seed ACE1, score cleared
// prints "TOP_TB: PASS" or "TOP_TB: FAIL (n errors)".
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module top_tb;

    reg         clk = 1'b0;
    reg         btn_new = 1'b0, btn_roll = 1'b0;
    reg  [15:0] sw = 16'h1234;
    wire [15:0] led;
    wire [6:0]  seg;
    wire        dp;
    wire [3:0]  an;

    top_module #(
        .CLK_HZ(10_000), .DEBOUNCE_MS(1), .DIGIT_HZ(1000), .TARGET(8'd50),
        .BTN_ACTIVE_LOW(0), .SEG_ACTIVE_LOW(1), .AN_ACTIVE_LOW(1)
    ) dut (
        .clk(clk), .btn_new_game(btn_new), .btn_roll(btn_roll), .sw_seed(sw),
        .led(led), .seg(seg), .dp(dp), .an(an)
    );

    always #5 clk = ~clk;
    task tick; begin @(posedge clk); #1; end endtask
    task wait_cycles(input integer n); integer c; begin for (c = 0; c < n; c = c + 1) tick; end endtask

    integer errors = 0;
    integer i, r0;
    reg [3:0] shown [0:3];       // decoded digit per anode position
    reg       dp_shown [0:3];

    task err(input [8*48-1:0] msg);
        begin errors = errors + 1; $display("  ERROR %0s", msg); end
    endtask

    // active-low segments -> digit code (0-9, A = dash, F = blank, E = unknown)
    function [3:0] decode(input [6:0] s);
        case (~s)
            7'h3F: decode = 4'd0;  7'h06: decode = 4'd1;  7'h5B: decode = 4'd2;
            7'h4F: decode = 4'd3;  7'h66: decode = 4'd4;  7'h6D: decode = 4'd5;
            7'h7D: decode = 4'd6;  7'h07: decode = 4'd7;  7'h7F: decode = 4'd8;
            7'h6F: decode = 4'd9;  7'h40: decode = 4'hA;  7'h00: decode = 4'hF;
            default: decode = 4'hE;
        endcase
    endfunction

    // watch the multiplexed display for 2 full frames and record each digit
    task capture_display;
        integer c;
        begin
            for (c = 0; c < 4; c = c + 1) begin shown[c] = 4'hE; dp_shown[c] = 1'b0; end
            for (c = 0; c < 80; c = c + 1) begin
                tick;
                case (an)
                    4'b1110: begin shown[0] = decode(seg); dp_shown[0] = ~dp; end
                    4'b1101: begin shown[1] = decode(seg); dp_shown[1] = ~dp; end
                    4'b1011: begin shown[2] = decode(seg); dp_shown[2] = ~dp; end
                    4'b0111: begin shown[3] = decode(seg); dp_shown[3] = ~dp; end
                    default: ;
                endcase
            end
        end
    endtask

    task check_display(input [3:0] e3, input [3:0] e2, input [3:0] e1, input [3:0] e0);
        begin
            capture_display;
            $display("  display: %h %h %h %h  (expected %h %h %h %h)",
                     shown[3], shown[2], shown[1], shown[0], e3, e2, e1, e0);
            if (shown[3] !== e3 || shown[2] !== e2 || shown[1] !== e1 || shown[0] !== e0)
                err("display mismatch");
        end
    endtask

    // press with contact bounce on both edges
    task bouncy_press(output dummy);
        begin
            dummy = 1'b0;
            btn_roll = 1; wait_cycles(3); btn_roll = 0; wait_cycles(2);
            btn_roll = 1; wait_cycles(4); btn_roll = 0; wait_cycles(1);
            btn_roll = 1; wait_cycles(60);                    // held
            btn_roll = 0; wait_cycles(3); btn_roll = 1; wait_cycles(2);
            btn_roll = 0; wait_cycles(60);                    // released
        end
    endtask

    reg dummy;
    integer score_now, rolls_now;

    initial begin
        // [1]
        wait_cycles(20);
        $display("[1] power-on loads switch seed");
        if (dut.u_game.lfsr_state !== 16'h1234) err("lfsr not loaded from switches at power-on");

        // [2]
        $display("[2] initial display");
        check_display(4'hA, 4'hA, 4'd0, 4'd0);
        if (led !== 16'h0000) err("leds not zero");

        // [3]
        $display("[3] bouncy press -> one roll");
        bouncy_press(dummy);
        $display("  rolls = %0d", dut.rolls);
        if (dut.rolls !== 8'd1) err("bouncy press did not give exactly one roll");

        // [4]
        $display("[4] glitch shorter than debounce -> nothing");
        btn_roll = 1; wait_cycles(6); btn_roll = 0; wait_cycles(60);
        if (dut.rolls !== 8'd1) err("glitch produced a roll");

        // [5]
        $display("[5] display and leds follow the game");
        score_now = dut.score;
        check_display({1'b0, dut.die1}, {1'b0, dut.die2}, score_now / 10, score_now % 10);
        if (led[15] !== dut.game_over || led[14:8] !== dut.rolls[6:0] ||
            led[7:4] !== dut.sum || led[3:0] !== 4'd0) err("led mapping");

        // [6]
        $display("[6] play to game over");
        i = 0;
        while (!dut.game_over && i < 40) begin bouncy_press(dummy); i = i + 1; end
        $display("  game over after %0d rolls, score %0d", dut.rolls, dut.score);
        if (dut.rolls !== 8'd6 || dut.score !== 8'd51) err("differs from dice_game_tb seed-1234 result");
        score_now = dut.score;
        check_display({1'b0, dut.die1}, {1'b0, dut.die2}, score_now / 10, score_now % 10);
        if (dp_shown[0] !== 1'b1 || dp_shown[1] | dp_shown[2] | dp_shown[3]) err("game-over dp");
        if (led[15] !== 1'b1) err("game-over led");
        rolls_now = dut.rolls;
        bouncy_press(dummy);
        if (dut.rolls !== rolls_now) err("roll accepted after game over");

        // [7]
        $display("[7] new-game button, switches = 0");
        sw = 16'h0000; wait_cycles(5);
        btn_new = 1; wait_cycles(30); btn_new = 0; wait_cycles(30);
        if (dut.u_game.lfsr_state !== 16'hACE1) err("zero switch seed not replaced by ACE1");
        if (dut.score !== 0 || dut.rolls !== 0 || dut.game_over !== 0) err("new game not clean");
        check_display(4'hA, 4'hA, 4'd0, 4'd0);

        if (errors == 0) $display("TOP_TB: PASS");
        else             $display("TOP_TB: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
