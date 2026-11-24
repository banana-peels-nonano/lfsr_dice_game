// -----------------------------------------------------------------------------
// dice_roller.v - draws two dice from the LFSR using rejection sampling
//
// one "draw" = advance the LFSR STEPS times, then look at its low 3 bits.
//   STEPS = 4 is deliberate:
//     * >= 3, so the 3 bits of each draw are fresh (no bit shared with the
//       previous draw's window)
//     * gcd(4, 65535) = 1, so 65535 consecutive draws visit every LFSR state
//       exactly once -> exact, checkable face counts over a full period.
//       (STEPS = 3 or 5 would divide 65535 and shrink the draw cycle.)
//
// fsm:  IDLE --start--> DRAW (STEPS cycles, lfsr_step=1) --> EVAL
//       EVAL: rejected            -> DRAW again
//             accepted, 1st die   -> hold in die1_tmp, DRAW again
//             accepted, 2nd die   -> commit die1/die2 together, done=1, IDLE
//
// both dice are committed in the same cycle so a display never shows a new
// die1 next to an old die2. 'start' is ignored unless IDLE (caller should
// also gate it). 'clear' aborts any roll and zeros the outputs.
// latency: 5 cycles per draw; worst case measured over the full LFSR cycle
// is 7 consecutive rejects (see reports), so a roll is bounded, not open-ended.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module dice_roller #(
    parameter STEPS = 4            // 1..16, must be coprime to 65535
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       clear,
    input  wire       start,
    input  wire [2:0] rnd,         // low 3 bits of the LFSR state
    output wire       lfsr_step,
    output wire       busy,
    output reg        done,        // 1-cycle pulse, dice valid from this cycle
    output reg  [2:0] die1,
    output reg  [2:0] die2
);

    generate
        if (STEPS < 1 || STEPS > 16) begin : g_bad_param
            ERROR_dice_roller_STEPS_out_of_range u_error ();
        end
    endgenerate

    localparam [1:0] S_IDLE = 2'd0,
                     S_DRAW = 2'd1,
                     S_EVAL = 2'd2;

    reg [1:0] state;
    reg [3:0] step_cnt;
    reg       second;       // 0: drawing die1, 1: drawing die2
    reg [2:0] die1_tmp;

    wire       face_valid;
    wire [2:0] face;

    die_mapper u_mapper (
        .rnd   (rnd),
        .valid (face_valid),
        .face  (face)
    );

    assign lfsr_step = (state == S_DRAW);
    assign busy      = (state != S_IDLE);

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst || clear) begin
            state    <= S_IDLE;
            step_cnt <= 4'd0;
            second   <= 1'b0;
            die1_tmp <= 3'd0;
            die1     <= 3'd0;
            die2     <= 3'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state    <= S_DRAW;
                        step_cnt <= 4'd0;
                        second   <= 1'b0;
                    end
                end
                S_DRAW: begin
                    if (step_cnt == STEPS - 1) begin
                        state    <= S_EVAL;
                        step_cnt <= 4'd0;
                    end else begin
                        step_cnt <= step_cnt + 4'd1;
                    end
                end
                S_EVAL: begin
                    if (!face_valid) begin
                        state <= S_DRAW;                 // reject, draw again
                    end else if (!second) begin
                        die1_tmp <= face;
                        second   <= 1'b1;
                        state    <= S_DRAW;
                    end else begin
                        die1   <= die1_tmp;
                        die2   <= face;
                        done   <= 1'b1;
                        second <= 1'b0;
                        state  <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
