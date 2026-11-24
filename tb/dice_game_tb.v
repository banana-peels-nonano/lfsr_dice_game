// -----------------------------------------------------------------------------
// dice_game_tb.v - self-checking testbench for the game core (dice_game)
//
// functional part (dut, SCORE_W = 8) - a reference scoreboard checks every
// roll: both dice in 1..6, sum, score (saturating), roll count, game_over.
//   [1]  reset state
//   [2]  new game with seed, full game to target 50, every roll checked
//   [3]  roll requests after game over are ignored
//   [4]  same seed -> identical game (reproducibility)
//   [5]  requests while busy are dropped: one roll per accepted request
//   [6]  new_game during a roll aborts it cleanly
//   [7]  new_game and roll_req in the same cycle: new_game wins
//   [8]  target edge cases 0 and 2 (first roll ends the game)
//   [9]  target 255 on an 8-bit score: saturation, no wrap (many seeds)
//   [10] roll latency stays within the analytic bound
//
// statistics part (dut_s, SCORE_W = 24, unreachable target)
//   [11] 2 x 24576 back-to-back rolls from seed ACE1:
//        * roll sequence period is exactly 24576 rolls
//        * exact face counts (python model: 4096 per face per die)
//        * pair histogram, chi-square, sums, correlations (reported)
//        * every roll written to rolls_sim.txt; run_sim.sh diffs it against
//          the python model's rolls_ref.txt
// prints "DICE_GAME_TB: PASS" or "DICE_GAME_TB: FAIL (n errors)".
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module dice_game_tb;

    localparam [15:0] DEF        = 16'hACE1;
    localparam integer ROLL_PER  = 24576;
    localparam integer N_STATS   = 2 * ROLL_PER;
    localparam integer TIMEOUT   = 200;
    // worst case: 1 accept cycle + 2 dice * 8 draws (7 rejects + 1 accept) * 5 cycles
    localparam integer LAT_BOUND = 1 + 2 * 8 * 5;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    task tick; begin @(posedge clk); #1; end endtask

    // ---------------- dut (8-bit score) ----------------
    reg         rst = 1'b1, new_game = 1'b0, roll_req = 1'b0;
    reg  [15:0] seed = 16'h0000;
    reg  [7:0]  target = 8'd50;
    wire [2:0]  die1, die2;
    wire [3:0]  sum;
    wire [7:0]  score, rolls;
    wire        busy, game_over, roll_done;
    wire [15:0] lfsr_state;

    dice_game #(.SCORE_W(8), .DEFAULT_SEED(DEF), .STEPS(4)) dut (
        .clk(clk), .rst(rst), .new_game(new_game), .seed(seed), .roll_req(roll_req),
        .target(target), .die1(die1), .die2(die2), .sum(sum), .score(score),
        .rolls(rolls), .busy(busy), .game_over(game_over), .roll_done(roll_done),
        .lfsr_state(lfsr_state));

    // ---------------- dut_s (24-bit score, statistics) ----------------
    reg         new_game_s = 1'b0, roll_req_s = 1'b0;
    wire [2:0]  die1_s, die2_s;
    wire [3:0]  sum_s;
    wire [23:0] score_s;
    wire [7:0]  rolls_s;
    wire        busy_s, game_over_s, roll_done_s;
    wire [15:0] lfsr_s;

    dice_game #(.SCORE_W(24), .DEFAULT_SEED(DEF), .STEPS(4)) dut_s (
        .clk(clk), .rst(rst), .new_game(new_game_s), .seed(DEF), .roll_req(roll_req_s),
        .target(24'hFFFFFF), .die1(die1_s), .die2(die2_s), .sum(sum_s), .score(score_s),
        .rolls(rolls_s), .busy(busy_s), .game_over(game_over_s), .roll_done(roll_done_s),
        .lfsr_state(lfsr_s));

    // ---------------- bookkeeping ----------------
    integer errors = 0;
    integer done_count = 0;                 // roll_done pulses seen on dut
    always @(posedge clk) if (roll_done) done_count = done_count + 1;

    integer m_score, m_rolls;               // scoreboard model
    reg     m_over;
    integer max_lat = 0, lat;
    integer i, j, k, n, g, sat_games, rec_n;
    reg [2:0] rec1 [0:63];
    reg [2:0] rec2 [0:63];
    reg       got;

    task err(input [8*48-1:0] msg);
        begin errors = errors + 1; $display("  ERROR %0s", msg); end
    endtask

    task model_clear; begin m_score = 0; m_rolls = 0; m_over = 1'b0; end endtask

    task check_outputs;
        begin
            if (score !== m_score[7:0] || rolls !== m_rolls[7:0] || game_over !== m_over) begin
                errors = errors + 1;
                $display("  ERROR state: score %0d/%0d rolls %0d/%0d over %b/%b",
                         score, m_score, rolls, m_rolls, game_over, m_over);
            end
        end
    endtask

    task start_new_game(input [15:0] s, input [7:0] t);
        begin
            seed = s; target = t;
            new_game = 1'b1; tick; new_game = 1'b0;
            model_clear;
            if (lfsr_state !== ((s == 16'd0) ? DEF : s)) err("lfsr not loaded with seed");
            if (die1 !== 3'd0 || die2 !== 3'd0 || sum !== 4'd0 || busy !== 1'b0) err("new game not clean");
            check_outputs;
        end
    endtask

    // one roll request + full scoreboard check. 'got' = a roll happened.
    task roll_and_check;
        begin
            roll_req = 1'b1; tick; roll_req = 1'b0;
            lat = 1; got = 1'b0;
            while (!roll_done && lat < TIMEOUT) begin tick; lat = lat + 1; end
            if (roll_done) begin
                got = 1'b1;
                if (m_over) err("roll accepted after game over");
                if (lat > max_lat) max_lat = lat;
                if (die1 < 1 || die1 > 6 || die2 < 1 || die2 > 6) begin
                    errors = errors + 1; $display("  ERROR dice out of range %0d %0d", die1, die2);
                end
                if (!m_over) begin
                    m_score = m_score + die1 + die2;
                    if (m_score > 255) m_score = 255;
                    if (m_rolls < 255) m_rolls = m_rolls + 1;
                    if (m_score >= target) m_over = 1'b1;
                end
                tick;                                  // score registers update
                if (sum !== die1 + die2) err("sum wrong");
                if (busy) err("busy after roll_done");
            end else if (!m_over) begin
                err("roll timed out");
            end
            check_outputs;
        end
    endtask

    // ---------------- statistics storage ----------------
    reg  [2:0]  s1 [0:N_STATS-1];
    reg  [2:0]  s2 [0:N_STATS-1];
    reg  [15:0] st [0:N_STATS-1];
    integer pair [0:35];
    integer f1 [1:6];
    integer f2 [1:6];
    integer sums [2:12];
    integer fd, mism, early_return, score_model, pmin, pmax;
    real    chi, e, mx, my, sxy, sxx, syy, x, y;

    initial begin
        tick; tick; tick;
        rst = 1'b0;

        // ---------------------------------------------------------------
        $display("[1] reset state");
        if (die1 !== 0 || die2 !== 0 || sum !== 0 || score !== 0 || rolls !== 0 ||
            game_over !== 0 || busy !== 0 || roll_done !== 0) err("reset outputs not zero");
        if (lfsr_state !== DEF) err("lfsr not at default seed after reset");

        // ---------------------------------------------------------------
        $display("[2] full game, seed 1234, target 50");
        start_new_game(16'h1234, 8'd50);
        rec_n = 0;
        while (!game_over && rec_n < 64) begin
            roll_and_check;
            rec1[rec_n] = die1; rec2[rec_n] = die2; rec_n = rec_n + 1;
        end
        $display("  game over after %0d rolls, score %0d", rolls, score);
        if (!game_over) err("game never ended");
        if (score < 50 || score > 61) err("final score outside 50..61");

        // ---------------------------------------------------------------
        $display("[3] requests after game over are ignored");
        n = done_count;
        for (i = 0; i < 3; i = i + 1) roll_and_check;
        if (done_count != n) err("roll_done after game over");

        // ---------------------------------------------------------------
        $display("[4] same seed replays the same game");
        start_new_game(16'h1234, 8'd50);
        mism = 0;
        for (i = 0; i < rec_n; i = i + 1) begin
            roll_and_check;
            if (die1 !== rec1[i] || die2 !== rec2[i]) mism = mism + 1;
        end
        $display("  %0d rolls replayed, %0d mismatches", rec_n, mism);
        if (mism != 0) err("replay differs");
        if (!game_over) err("replay did not end at the same roll");

        // ---------------------------------------------------------------
        $display("[5] extra requests while busy are dropped");
        start_new_game(16'h00FF, 8'd200);
        n = done_count;
        roll_req = 1'b1; tick; roll_req = 1'b0;
        k = 0;
        while (busy && k < TIMEOUT) begin          // hammer roll_req while busy
            roll_req = 1'b1; tick; roll_req = 1'b0; k = k + 1;
        end
        for (i = 0; i < 2 * TIMEOUT; i = i + 1) tick;
        $display("  %0d extra requests while busy, %0d roll(s) completed, rolls=%0d",
                 k, done_count - n, rolls);
        if (done_count - n != 1 || rolls !== 8'd1) err("busy requests not dropped");
        if (score !== sum) err("score != sum after one roll");

        // ---------------------------------------------------------------
        $display("[6] new_game during a roll aborts it");
        start_new_game(16'h0042, 8'd200);
        roll_and_check;                                    // one finished roll first
        roll_req = 1'b1; tick; roll_req = 1'b0;
        tick; tick;
        if (!busy) err("expected busy");
        n = done_count;
        seed = 16'h0042; new_game = 1'b1; tick; new_game = 1'b0;
        for (i = 0; i < 2 * TIMEOUT; i = i + 1) tick;
        if (done_count != n) err("aborted roll still completed");
        if (busy || die1 !== 0 || die2 !== 0 || score !== 0 || rolls !== 0 || game_over)
            err("state not clean after abort");
        if (lfsr_state !== 16'h0042) err("lfsr not reloaded after abort");

        // ---------------------------------------------------------------
        $display("[7] new_game and roll_req in the same cycle");
        n = done_count;
        seed = 16'h0042; new_game = 1'b1; roll_req = 1'b1; tick;
        new_game = 1'b0; roll_req = 1'b0;
        if (busy) err("roll started in the new_game cycle");
        for (i = 0; i < TIMEOUT; i = i + 1) tick;
        if (done_count != n) err("roll happened");

        // ---------------------------------------------------------------
        $display("[8] targets 0 and 2: first roll ends the game");
        start_new_game(16'h0007, 8'd0);
        roll_and_check;
        if (!game_over || rolls !== 8'd1) err("target 0");
        start_new_game(16'h0007, 8'd2);
        roll_and_check;
        if (!game_over || rolls !== 8'd1) err("target 2");

        // ---------------------------------------------------------------
        $display("[9] target 255 on an 8-bit score, seeds 1..60");
        sat_games = 0;
        for (g = 1; g <= 60; g = g + 1) begin
            start_new_game(g[15:0], 8'd255);
            k = 0;
            while (!game_over && k < 100) begin
                n = m_score;
                roll_and_check;
                if (score < n) err("score decreased (wrap)");
                k = k + 1;
            end
            if (!game_over) err("target 255 never reached");
            if (score == 8'd255 && n + sum > 255) sat_games = sat_games + 1;
        end
        $display("  %0d of 60 games ended by saturating at 255, none wrapped", sat_games);
        if (sat_games == 0) err("saturation path never exercised");

        // ---------------------------------------------------------------
        $display("[10] latency: max %0d cycles request->roll_done (bound %0d)", max_lat, LAT_BOUND);
        if (max_lat > LAT_BOUND) err("latency above analytic bound");

        // ---------------------------------------------------------------
        $display("[11] statistics: %0d back-to-back rolls, seed %h", N_STATS, DEF);
        new_game_s = 1'b1; tick; new_game_s = 1'b0;
        max_lat = 0;
        for (i = 0; i < N_STATS; i = i + 1) begin
            st[i] = lfsr_s;                          // lfsr state as the roll starts
            roll_req_s = 1'b1; tick; roll_req_s = 1'b0;
            lat = 1;
            while (!roll_done_s && lat < TIMEOUT) begin tick; lat = lat + 1; end
            if (!roll_done_s) begin err("stats roll timed out"); i = N_STATS; end
            if (lat > max_lat) max_lat = lat;
            s1[i] = die1_s; s2[i] = die2_s;
            tick;
        end
        $display("  max latency over the full cycle: %0d cycles", max_lat);
        if (max_lat > LAT_BOUND) err("stats latency above bound");

        // period of the roll sequence
        early_return = 0;
        for (i = 1; i < ROLL_PER; i = i + 1) if (st[i] == DEF) early_return = early_return + 1;
        mism = 0;
        for (i = 0; i < ROLL_PER; i = i + 1)
            if (s1[i] !== s1[i + ROLL_PER] || s2[i] !== s2[i + ROLL_PER]) mism = mism + 1;
        $display("  lfsr at seed again at roll %0d: %b; earlier returns: %0d; period-shift mismatches: %0d",
                 ROLL_PER, st[ROLL_PER] == DEF, early_return, mism);
        if (st[ROLL_PER] !== DEF || early_return != 0 || mism != 0) err("roll period is not 24576");

        // score consistency for the 24-bit instance
        score_model = 0;
        for (i = 0; i < N_STATS; i = i + 1) score_model = score_model + s1[i] + s2[i];
        $display("  24-bit score %0d, model %0d", score_s, score_model);
        if (score_s != score_model) err("24-bit score mismatch");
        if (rolls_s !== 8'hFF) err("roll counter did not saturate at 255");

        // histograms over exactly one period
        for (i = 0; i < 36; i = i + 1) pair[i] = 0;
        for (i = 1; i <= 6; i = i + 1) begin f1[i] = 0; f2[i] = 0; end
        for (i = 2; i <= 12; i = i + 1) sums[i] = 0;
        for (i = 0; i < ROLL_PER; i = i + 1) begin
            f1[s1[i]] = f1[s1[i]] + 1;
            f2[s2[i]] = f2[s2[i]] + 1;
            pair[(s1[i] - 1) * 6 + (s2[i] - 1)] = pair[(s1[i] - 1) * 6 + (s2[i] - 1)] + 1;
            k = s1[i] + s2[i];                 // integer: avoids 3-bit wrap
            sums[k] = sums[k] + 1;
        end
        $display("  die1 faces 1..6: %0d %0d %0d %0d %0d %0d", f1[1], f1[2], f1[3], f1[4], f1[5], f1[6]);
        $display("  die2 faces 1..6: %0d %0d %0d %0d %0d %0d", f2[1], f2[2], f2[3], f2[4], f2[5], f2[6]);
        for (i = 1; i <= 6; i = i + 1)
            if (f1[i] != 4096 || f2[i] != 4096) err("face count != 4096 (python model)");

        e = ROLL_PER / 36.0;
        chi = 0.0; pmin = 1 << 30; pmax = 0;
        $display("  pair counts, rows die1 = 1..6, cols die2 = 1..6 (expected %0.2f):", e);
        for (i = 0; i < 6; i = i + 1) begin
            $display("    %0d: %4d %4d %4d %4d %4d %4d", i + 1,
                     pair[i*6], pair[i*6+1], pair[i*6+2], pair[i*6+3], pair[i*6+4], pair[i*6+5]);
            for (j = 0; j < 6; j = j + 1) begin
                chi = chi + (pair[i*6+j] - e) * (pair[i*6+j] - e) / e;
                if (pair[i*6+j] < pmin) pmin = pair[i*6+j];
                if (pair[i*6+j] > pmax) pmax = pair[i*6+j];
            end
        end
        $display("  pair min %0d max %0d, chi-square (35 dof) = %0.2f  (5%% critical 49.80)", pmin, pmax, chi);
        if (pmin == 0) err("a dice pair never occurs");
        if (chi > 49.80) err("pair chi-square above 5% critical value");
        $display("  sums 2..12: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                 sums[2], sums[3], sums[4], sums[5], sums[6], sums[7],
                 sums[8], sums[9], sums[10], sums[11], sums[12]);
        k = 0;
        for (i = 2; i <= 12; i = i + 1) k = k + sums[i];
        if (k != ROLL_PER || sums[7] < sums[6] || sums[7] < sums[8]) err("sum histogram inconsistent");

        // pearson correlation die1 vs die2 within a roll
        mx = 0; my = 0;
        for (i = 0; i < ROLL_PER; i = i + 1) begin mx = mx + s1[i]; my = my + s2[i]; end
        mx = mx / ROLL_PER; my = my / ROLL_PER;
        sxy = 0; sxx = 0; syy = 0;
        for (i = 0; i < ROLL_PER; i = i + 1) begin
            x = s1[i] - mx; y = s2[i] - my;
            sxy = sxy + x * y; sxx = sxx + x * x; syy = syy + y * y;
        end
        $display("  pearson(die1, die2) = %0.5f", sxy / $sqrt(sxx * syy));
        // die2 of roll k vs die1 of roll k+1
        sxy = 0;
        for (i = 0; i < ROLL_PER; i = i + 1) begin
            x = s2[i] - my; y = s1[(i + 1) % ROLL_PER] - mx;
            sxy = sxy + x * y;
        end
        $display("  pearson(die2[k], die1[k+1]) = %0.5f", sxy / $sqrt(sxx * syy));

        // dump for the python cross-check
        fd = $fopen("rolls_sim.txt", "w");
        for (i = 0; i < N_STATS; i = i + 1) $fdisplay(fd, "%0d %0d", s1[i], s2[i]);
        $fclose(fd);
        $display("  wrote %0d rolls to rolls_sim.txt", N_STATS);

        if (errors == 0) $display("DICE_GAME_TB: PASS");
        else             $display("DICE_GAME_TB: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
