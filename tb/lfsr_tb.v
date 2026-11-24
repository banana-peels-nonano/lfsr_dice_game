// -----------------------------------------------------------------------------
// lfsr_tb.v - self-checking testbench for lfsr16
//
// checks: reset value, seed load, zero-seed guard, hold when step=0,
// priority rst > load > step, golden vectors from the independent python
// model, full period 65535 with no zero state and no early repeat for
// several seeds, repeatability (two instances, same seed), behaviour after
// a mid-sequence reset.
// prints "LFSR_TB: PASS" or "LFSR_TB: FAIL (n errors)".
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module lfsr_tb;

    localparam [15:0] DEF = 16'hACE1;

    reg         clk = 1'b0;
    reg         rst, load, step;
    reg  [15:0] seed;
    wire [15:0] q;

    // second instance for the repeatability check
    reg         load_b, step_b;
    reg  [15:0] seed_b;
    wire [15:0] q_b;

    integer errors = 0;
    integer i, n, period;
    reg     visited [0:65535];
    reg [15:0] first_run [0:99];
    reg [15:0] start;
    reg        repeated, saw_zero;

    lfsr16 #(.DEFAULT_SEED(DEF)) dut   (.clk(clk), .rst(rst), .load(load),   .seed(seed),   .step(step),   .state(q));
    lfsr16 #(.DEFAULT_SEED(DEF)) dut_b (.clk(clk), .rst(rst), .load(load_b), .seed(seed_b), .step(step_b), .state(q_b));

    always #5 clk = ~clk;

    task check16(input [15:0] got, input [15:0] exp, input [8*40-1:0] what);
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("  ERROR %0s: got %h expected %h", what, got, exp);
            end
        end
    endtask

    task tick; begin @(posedge clk); #1; end endtask

    task do_load(input [15:0] s);
        begin load = 1'b1; seed = s; tick; load = 1'b0; end
    endtask

    // full-period test from a given seed
    task period_test(input [15:0] s);
        begin
            for (i = 0; i < 65536; i = i + 1) visited[i] = 1'b0;
            do_load(s);
            start    = q;
            repeated = 1'b0;
            saw_zero = 1'b0;
            period   = 0;
            visited[q] = 1'b1;
            step = 1'b1;
            for (n = 1; n <= 65535; n = n + 1) begin
                tick;
                if (q == 16'd0) saw_zero = 1'b1;
                if (q == start && period == 0) period = n;
                if (visited[q] && n < 65535) repeated = 1'b1;
                visited[q] = 1'b1;
            end
            step = 1'b0;
            n = 0;
            for (i = 1; i < 65536; i = i + 1) if (visited[i]) n = n + 1;
            $display("  seed %h: period %0d, distinct nonzero states %0d, zero seen %0d, early repeat %0d",
                     s, period, n, saw_zero, repeated);
            if (period != 65535 || n != 65535 || saw_zero || repeated) begin
                errors = errors + 1;
                $display("  ERROR period test failed for seed %h", s);
            end
        end
    endtask

    initial begin
        rst = 1'b1; load = 1'b0; step = 1'b0; seed = 16'h0000;
        load_b = 1'b0; step_b = 1'b0; seed_b = 16'h0000;
        tick; tick;

        $display("[1] reset value");
        check16(q, DEF, "reset value");
        step = 1'b1; tick;                       // rst must win over step
        check16(q, DEF, "rst has priority over step");
        load = 1'b1; seed = 16'h1234; tick;      // rst must win over load
        check16(q, DEF, "rst has priority over load");
        load = 1'b0; step = 1'b0;
        rst = 1'b0; tick;
        check16(q, DEF, "hold after reset release");

        $display("[2] seed load, zero-seed guard, hold, load priority");
        do_load(16'h1234);  check16(q, 16'h1234, "load 1234");
        do_load(16'hFFFF);  check16(q, 16'hFFFF, "load FFFF");
        do_load(16'h0000);  check16(q, DEF,      "load 0 -> default seed");
        tick; tick; tick;   check16(q, DEF,      "hold with step=0");
        load = 1'b1; step = 1'b1; seed = 16'h0F0F; tick;
        check16(q, 16'h0F0F, "load has priority over step");
        load = 1'b0; step = 1'b0;

        $display("[3] golden vectors from python model, seed ACE1");
        do_load(DEF);
        step = 1'b1;
        for (n = 1; n <= 65535; n = n + 1) begin
            tick;
            case (n)
                1:     check16(q, 16'h59C3, "step 1");
                2:     check16(q, 16'hB387, "step 2");
                3:     check16(q, 16'h670F, "step 3");
                16:    check16(q, 16'hE455, "step 16");
                100:   check16(q, 16'h4753, "step 100");
                1000:  check16(q, 16'h8A87, "step 1000");
                65534: check16(q, 16'hD670, "step 65534");
                65535: check16(q, 16'hACE1, "step 65535 (back to seed)");
                default: ;
            endcase
        end
        step = 1'b0;

        $display("[4] full period, several seeds");
        period_test(16'h0001);
        period_test(16'hACE1);
        period_test(16'hFFFF);
        period_test(16'h8000);
        period_test(16'h5A5A);

        $display("[5] repeatability: two instances, same seed");
        load = 1'b1; seed = 16'hBEEF; load_b = 1'b1; seed_b = 16'hBEEF; tick;
        load = 1'b0; load_b = 1'b0;
        step = 1'b1; step_b = 1'b1;
        n = 0;
        for (i = 0; i < 5000; i = i + 1) begin
            tick;
            if (q !== q_b) n = n + 1;
        end
        step = 1'b0; step_b = 1'b0;
        if (n != 0) begin errors = errors + 1; $display("  ERROR %0d mismatches", n); end
        else $display("  5000 steps identical");
        // different seed must give a different sequence
        load = 1'b1; seed = 16'hBEEF; load_b = 1'b1; seed_b = 16'hBEF0; tick;
        load = 1'b0; load_b = 1'b0; step = 1'b1; step_b = 1'b1;
        n = 0;
        for (i = 0; i < 100; i = i + 1) begin tick; if (q === q_b) n = n + 1; end
        step = 1'b0; step_b = 1'b0;
        $display("  different seeds: %0d/100 equal states", n);
        if (n > 5) begin errors = errors + 1; $display("  ERROR different seeds track each other"); end

        $display("[6] reset mid-sequence restores the default-seed sequence");
        rst = 1'b1; tick; rst = 1'b0;
        step = 1'b1;
        for (i = 0; i < 100; i = i + 1) begin tick; first_run[i] = q; end
        for (i = 0; i < 777; i = i + 1) tick;    // wander off
        step = 1'b0;
        rst = 1'b1; tick; rst = 1'b0;
        check16(q, DEF, "state after mid-sequence reset");
        step = 1'b1;
        n = 0;
        for (i = 0; i < 100; i = i + 1) begin tick; if (q !== first_run[i]) n = n + 1; end
        step = 1'b0;
        if (n != 0) begin errors = errors + 1; $display("  ERROR %0d mismatches after reset", n); end
        else $display("  100 states after reset match the first run");

        if (errors == 0) $display("LFSR_TB: PASS");
        else             $display("LFSR_TB: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
