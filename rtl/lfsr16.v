// -----------------------------------------------------------------------------
// lfsr16.v - 16-bit maximal-length fibonacci LFSR
//
// polynomial   p(x) = x^16 + x^14 + x^13 + x^11 + 1   (primitive, see README)
// form         fibonacci, shifts toward the msb, new bit enters state[0]
// taps         exponent e -> register bit e-1  =>  bits 15, 13, 12, 10
// period       2^16 - 1 = 65535 states, every nonzero state exactly once
//
// priority     rst > load > step   (all synchronous, active-high)
//   rst   : state <= DEFAULT_SEED
//   load  : state <= seed, or DEFAULT_SEED if seed == 0 (lockup guard)
//   step  : advance one state; holds otherwise (clock-enable style)
//
// the all-zero state can never be entered: rst/load never write zero, and the
// update is a bijection on the nonzero states (tap on bit 15 makes it
// invertible, and 0 maps only to 0).
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module lfsr16 #(
    parameter [15:0] DEFAULT_SEED = 16'hACE1   // must be nonzero
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        load,
    input  wire [15:0] seed,
    input  wire        step,
    output reg  [15:0] state
);

    // elaboration-time guard: a zero default seed would lock the register.
    // referencing a module that does not exist stops synthesis/elaboration.
    generate
        if (DEFAULT_SEED == 16'd0) begin : g_bad_param
            ERROR_lfsr16_DEFAULT_SEED_must_be_nonzero u_error ();
        end
    endgenerate

    wire        feedback  = state[15] ^ state[13] ^ state[12] ^ state[10];
    wire [15:0] safe_seed = (seed == 16'd0) ? DEFAULT_SEED : seed;

    always @(posedge clk) begin
        if (rst)
            state <= DEFAULT_SEED;
        else if (load)
            state <= safe_seed;
        else if (step)
            state <= {state[14:0], feedback};
    end

endmodule
