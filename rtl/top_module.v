// -----------------------------------------------------------------------------
// top_module.v - board-level wrapper (board NOT yet chosen)
//
// everything board-specific lives here or in the XDC. the game core
// (dice_game and below) has no knowledge of buttons, switches or displays.
//
// i/o assumed (adapt once the board is known):
//   clk           : one board oscillator, frequency = CLK_HZ
//   btn_new_game  : push button -> new game (reload seed from switches)
//   btn_roll      : push button -> roll
//   sw_seed[15:0] : seed switches (boards with fewer switches: tie the rest)
//   seg/dp/an     : 4-digit multiplexed seven-segment display
//                     [die1] [die2] [score tens] [score ones]
//                     '-' before the first roll; dp on the right digit = game over
//   led[15]       : game over
//   led[14:8]     : rolls taken (binary, 7 lsbs)
//   led[7:4]      : last sum (binary)
//   led[3:0]      : off
//
// reset: a 4-bit power-on counter holds rst for 8 clocks after configuration,
// then fires one automatic new_game so the switch seed is used from power-up.
// the counter relies on its register coming up as 0 after configuration
// (true on 7-series via GSR / INIT); this is the only line that assumes an
// FPGA rather than a generic reset input.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module top_module #(
    parameter        CLK_HZ         = 100_000_000,
    parameter        DEBOUNCE_MS    = 10,
    parameter        DIGIT_HZ       = 1000,         // per-digit refresh rate
    parameter [7:0]  TARGET         = 8'd50,
    parameter        BTN_ACTIVE_LOW = 0,
    parameter        SEG_ACTIVE_LOW = 1,
    parameter        AN_ACTIVE_LOW  = 1
) (
    input  wire        clk,
    input  wire        btn_new_game,
    input  wire        btn_roll,
    input  wire [15:0] sw_seed,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire        dp,
    output wire [3:0]  an
);

    // constant arithmetic only - evaluated at elaboration
    localparam integer DEB_RAW   = (CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer DEB_CYC   = (DEB_RAW < 1) ? 1 : DEB_RAW;
    localparam integer DIG_RAW   = CLK_HZ / DIGIT_HZ;
    localparam integer DIG_CYC   = (DIG_RAW < 1) ? 1 : DIG_RAW;

    // both counters below are 24 bits wide; refuse configurations that overflow
    generate
        if (DEB_CYC > 16777215 || DIG_CYC > 16777215) begin : g_bad_param
            ERROR_top_module_counter_too_small_for_CLK_HZ u_error ();
        end
    endgenerate

    // ---------------- power-on reset ----------------
    reg [3:0] por_cnt = 4'd0;                 // init value: FPGA configuration
    wire      rst     = ~por_cnt[3];
    reg       rst_d   = 1'b1;
    always @(posedge clk) begin
        if (!por_cnt[3])
            por_cnt <= por_cnt + 4'd1;
        rst_d <= rst;
    end
    wire por_new_game = rst_d & ~rst;         // one pulse as reset releases

    // ---------------- inputs ----------------
    wire new_game_pulse, roll_pulse;
    wire new_game_level, roll_level;          // unused, kept for debug

    btn_conditioner #(
        .CNT_W (24), .STABLE_CYCLES (DEB_CYC), .ACTIVE_LOW (BTN_ACTIVE_LOW)
    ) u_btn_new (
        .clk (clk), .rst (rst), .btn_in (btn_new_game),
        .level (new_game_level), .pulse (new_game_pulse)
    );

    btn_conditioner #(
        .CNT_W (24), .STABLE_CYCLES (DEB_CYC), .ACTIVE_LOW (BTN_ACTIVE_LOW)
    ) u_btn_roll (
        .clk (clk), .rst (rst), .btn_in (btn_roll),
        .level (roll_level), .pulse (roll_pulse)
    );

    // switches are quasi-static and only sampled on new_game; a 2-FF
    // synchroniser per bit is enough
    (* ASYNC_REG = "TRUE" *) reg [15:0] sw_meta, sw_sync;
    always @(posedge clk) begin
        sw_meta <= sw_seed;
        sw_sync <= sw_meta;
    end

    // ---------------- game core ----------------
    wire [2:0]  die1, die2;
    wire [3:0]  sum;
    wire [7:0]  score, rolls;
    wire        busy, game_over, roll_done;
    wire [15:0] lfsr_state;

    dice_game #(
        .SCORE_W (8), .DEFAULT_SEED (16'hACE1), .STEPS (4)
    ) u_game (
        .clk        (clk),
        .rst        (rst),
        .new_game   (new_game_pulse | por_new_game),
        .seed       (sw_sync),
        .roll_req   (roll_pulse),
        .target     (TARGET),
        .die1       (die1),
        .die2       (die2),
        .sum        (sum),
        .score      (score),
        .rolls      (rolls),
        .busy       (busy),
        .game_over  (game_over),
        .roll_done  (roll_done),
        .lfsr_state (lfsr_state)
    );

    // ---------------- outputs ----------------
    // 0..99 -> two decimal digits by a compare chain (cheaper than a
    // generic divider; the display only has room for two score digits)
    function [7:0] to_bcd2;                        // {tens, ones}
        input [6:0] v;
        reg   [6:0] r;
        reg   [3:0] t;
        begin
            if      (v >= 7'd90) begin t = 4'd9; r = v - 7'd90; end
            else if (v >= 7'd80) begin t = 4'd8; r = v - 7'd80; end
            else if (v >= 7'd70) begin t = 4'd7; r = v - 7'd70; end
            else if (v >= 7'd60) begin t = 4'd6; r = v - 7'd60; end
            else if (v >= 7'd50) begin t = 4'd5; r = v - 7'd50; end
            else if (v >= 7'd40) begin t = 4'd4; r = v - 7'd40; end
            else if (v >= 7'd30) begin t = 4'd3; r = v - 7'd30; end
            else if (v >= 7'd20) begin t = 4'd2; r = v - 7'd20; end
            else if (v >= 7'd10) begin t = 4'd1; r = v - 7'd10; end
            else                 begin t = 4'd0; r = v;          end
            to_bcd2 = {t, r[3:0]};
        end
    endfunction

    wire [6:0] score_disp = (score > 8'd99) ? 7'd99 : score[6:0];
    wire [7:0] score_bcd  = to_bcd2(score_disp);
    wire [3:0] tens       = score_bcd[7:4];
    wire [3:0] ones       = score_bcd[3:0];
    wire [3:0] dig_die1   = (die1 == 3'd0) ? 4'hA : {1'b0, die1};
    wire [3:0] dig_die2   = (die2 == 3'd0) ? 4'hA : {1'b0, die2};

    seg7_mux4 #(
        .CNT_W (24), .DIV_CYCLES (DIG_CYC),
        .SEG_ACTIVE_LOW (SEG_ACTIVE_LOW), .AN_ACTIVE_LOW (AN_ACTIVE_LOW)
    ) u_disp (
        .clk (clk), .rst (rst),
        .d3 (dig_die1), .d2 (dig_die2), .d1 (tens), .d0 (ones),
        .dp_mask ({3'b000, game_over}),
        .seg (seg), .dp (dp), .an (an)
    );

    assign led = {game_over, rolls[6:0], sum, 4'b0000};

endmodule
