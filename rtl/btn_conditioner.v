// -----------------------------------------------------------------------------
// btn_conditioner.v - synchronise + debounce + press pulse for one button
//
//   btn_in --[xor polarity]--> 2-FF synchroniser --> stability counter --> level
//                                                                    \--> pulse
//
// * 2-FF synchroniser removes metastability from the asynchronous pin.
// * 'level' only changes after the synchronised input has been different from
//   it for STABLE_CYCLES consecutive clocks; any bounce restarts the count.
// * 'pulse' is high for exactly one clock when 'level' goes 0 -> 1 (press).
// * ACTIVE_LOW = 1 for buttons that read 0 when pressed.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module btn_conditioner #(
    parameter          CNT_W         = 24,
    parameter [CNT_W-1:0] STABLE_CYCLES = 24'd1_000_000,   // 10 ms @ 100 MHz
    parameter          ACTIVE_LOW    = 0
) (
    input  wire clk,
    input  wire rst,
    input  wire btn_in,          // raw, asynchronous
    output reg  level,           // debounced, active-high
    output reg  pulse            // 1 clock per press
);

    (* ASYNC_REG = "TRUE" *) reg sync0, sync1;   // keep the pair close in vivado
    reg [CNT_W-1:0] cnt;

    wire raw = (ACTIVE_LOW != 0) ? ~btn_in : btn_in;

    always @(posedge clk) begin
        pulse <= 1'b0;
        if (rst) begin
            sync0 <= 1'b0;
            sync1 <= 1'b0;
            level <= 1'b0;
            cnt   <= {CNT_W{1'b0}};
        end else begin
            sync0 <= raw;
            sync1 <= sync0;
            if (sync1 == level) begin
                cnt <= {CNT_W{1'b0}};
            end else if (cnt == STABLE_CYCLES - 1'b1) begin
                cnt   <= {CNT_W{1'b0}};
                level <= sync1;
                pulse <= sync1;            // only on the press edge
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

endmodule
