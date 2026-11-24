// -----------------------------------------------------------------------------
// die_mapper_tb.v - self-checking testbench for die_mapper (+ lfsr16 source)
//
// checks:
//  [1] all 8 input codes: 0 and 7 rejected, 1..6 pass through unchanged
//  [2] low 3 bits over every LFSR state (65535): exact counts
//        code 0 -> 8191, codes 1..7 -> 8192   (an m-sequence contains every
//        nonzero 16-bit state once; the all-zero state is the one missing)
//  [3] decimated draws exactly as the roller uses them (4 steps per draw),
//      65535 draws: same exact counts, faces 1..6 = 8192 each, rejects 16383,
//      LFSR back at the seed, every accepted face in 1..6, max run of
//      consecutive rejects = 7 (python model value, cyclic over two periods)
//  [4] informational only: naive (state % 6) + 1 counts, for the report
// prints "DIE_MAPPER_TB: PASS" or "DIE_MAPPER_TB: FAIL (n errors)".
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module die_mapper_tb;

    localparam [15:0] SEED  = 16'hACE1;
    localparam        STEPS = 4;

    reg         clk = 1'b0;
    reg         rst = 1'b1, load = 1'b0, step = 1'b0;
    reg  [15:0] seed = SEED;
    wire [15:0] q;

    reg  [2:0]  rnd_direct;
    wire        valid_d, valid_l;
    wire [2:0]  face_d, face_l;

    integer errors = 0;
    integer i, k, run, maxrun, rejects;
    integer cnt [0:7];
    integer naive [0:5];

    lfsr16 #(.DEFAULT_SEED(SEED)) u_lfsr (.clk(clk), .rst(rst), .load(load), .seed(seed), .step(step), .state(q));
    die_mapper u_map_direct (.rnd(rnd_direct), .valid(valid_d), .face(face_d));
    die_mapper u_map_lfsr   (.rnd(q[2:0]),     .valid(valid_l), .face(face_l));

    always #5 clk = ~clk;
    task tick; begin @(posedge clk); #1; end endtask

    // checks one mapper output against its input code
    task check_map(input [2:0] code, input v, input [2:0] f);
        begin
            if (code == 3'd0 || code == 3'd7) begin
                if (v !== 1'b0 || f !== 3'd0) begin
                    errors = errors + 1;
                    $display("  ERROR code %0d: valid=%b face=%0d, expected reject", code, v, f);
                end
            end else begin
                if (v !== 1'b1 || f !== code || f < 1 || f > 6) begin
                    errors = errors + 1;
                    $display("  ERROR code %0d: valid=%b face=%0d", code, v, f);
                end
            end
        end
    endtask

    task clear_counts; begin for (i = 0; i < 8; i = i + 1) cnt[i] = 0; end endtask

    task expect_counts(input [8*24-1:0] what);
        begin
            $display("  %0s: code0=%0d  faces1..6=%0d %0d %0d %0d %0d %0d  code7=%0d",
                     what, cnt[0], cnt[1], cnt[2], cnt[3], cnt[4], cnt[5], cnt[6], cnt[7]);
            if (cnt[0] != 8191) begin errors = errors + 1; $display("  ERROR code 0 count"); end
            for (i = 1; i < 8; i = i + 1)
                if (cnt[i] != 8192) begin errors = errors + 1; $display("  ERROR code %0d count", i); end
        end
    endtask

    initial begin
        tick; tick; rst = 1'b0;

        $display("[1] exhaustive mapping of the 8 codes");
        for (k = 0; k < 8; k = k + 1) begin
            rnd_direct = k[2:0];
            #1;
            check_map(rnd_direct, valid_d, face_d);
            $display("  rnd=%0d -> valid=%b face=%0d", rnd_direct, valid_d, face_d);
        end

        $display("[2] every LFSR state once (step every clock)");
        clear_counts;
        for (i = 0; i < 6; i = i + 1) naive[i] = 0;
        load = 1'b1; tick; load = 1'b0;
        for (k = 0; k < 65535; k = k + 1) begin
            cnt[q[2:0]] = cnt[q[2:0]] + 1;
            naive[q % 6] = naive[q % 6] + 1;
            check_map(q[2:0], valid_l, face_l);
            step = 1'b1; tick; step = 1'b0;
        end
        expect_counts("all states");
        if (q !== SEED) begin errors = errors + 1; $display("  ERROR not back at seed"); end

        $display("[3] decimated draws, %0d steps per draw, 2 x 65535 draws", STEPS);
        clear_counts;
        rejects = 0; run = 0; maxrun = 0;
        load = 1'b1; tick; load = 1'b0;
        for (k = 0; k < 2 * 65535; k = k + 1) begin
            step = 1'b1;
            repeat (STEPS) tick;
            step = 1'b0;
            check_map(q[2:0], valid_l, face_l);
            if (k < 65535) begin
                cnt[q[2:0]] = cnt[q[2:0]] + 1;
                if (!valid_l) rejects = rejects + 1;
            end
            if (!valid_l) begin
                run = run + 1;
                if (run > maxrun) maxrun = run;
            end else begin
                run = 0;
            end
            if (k == 65534 && q !== SEED) begin
                errors = errors + 1; $display("  ERROR draw cycle did not return to seed");
            end
        end
        expect_counts("65535 draws");
        $display("  rejected draws %0d (expected 16383), max consecutive rejects %0d (expected 7)",
                 rejects, maxrun);
        if (rejects != 16383) begin errors = errors + 1; $display("  ERROR reject count"); end
        if (maxrun  != 7)     begin errors = errors + 1; $display("  ERROR max reject run"); end

        $display("[4] informational: naive (state %% 6)+1 over all states");
        $display("  faces 1..6 = %0d %0d %0d %0d %0d %0d  (not used by the design)",
                 naive[0], naive[1], naive[2], naive[3], naive[4], naive[5]);

        if (errors == 0) $display("DIE_MAPPER_TB: PASS");
        else             $display("DIE_MAPPER_TB: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
