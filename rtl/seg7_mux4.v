// -----------------------------------------------------------------------------
// seg7_mux4.v - 4-digit multiplexed seven-segment driver
//
// digit codes (4 bits): 0..9 = numerals, 4'hA = dash, anything else = blank.
// seg[6:0] = {g,f,e,d,c,b,a}. which pin is 'a' etc. is decided in the XDC.
// one digit is lit at a time; a clock-enable tick every DIV_CYCLES clocks
// moves to the next digit (no derived clock). outputs are registered.
// polarity parameters: most digilent-style boards are active-low for both
// segments and anodes - check your board's schematic.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module seg7_mux4 #(
    parameter             CNT_W          = 24,
    parameter [CNT_W-1:0] DIV_CYCLES     = 24'd100_000,  // 1 kHz per digit @ 100 MHz
    parameter             SEG_ACTIVE_LOW = 1,
    parameter             AN_ACTIVE_LOW  = 1
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] d3,        // leftmost
    input  wire [3:0] d2,
    input  wire [3:0] d1,
    input  wire [3:0] d0,        // rightmost
    input  wire [3:0] dp_mask,   // decimal point per digit, active-high
    output reg  [6:0] seg,
    output reg        dp,
    output reg  [3:0] an
);

    reg [CNT_W-1:0] div_cnt;
    reg [1:0]       sel;
    reg [3:0]       code;
    reg [6:0]       pattern;     // active-high gfedcba

    always @(posedge clk) begin
        if (rst) begin
            div_cnt <= {CNT_W{1'b0}};
            sel     <= 2'd0;
        end else if (div_cnt == DIV_CYCLES - 1'b1) begin
            div_cnt <= {CNT_W{1'b0}};
            sel     <= sel + 2'd1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    always @(*) begin
        case (sel)
            2'd0:    code = d0;
            2'd1:    code = d1;
            2'd2:    code = d2;
            default: code = d3;
        endcase
    end

    always @(*) begin
        case (code)
            4'd0:    pattern = 7'h3F;
            4'd1:    pattern = 7'h06;
            4'd2:    pattern = 7'h5B;
            4'd3:    pattern = 7'h4F;
            4'd4:    pattern = 7'h66;
            4'd5:    pattern = 7'h6D;
            4'd6:    pattern = 7'h7D;
            4'd7:    pattern = 7'h07;
            4'd8:    pattern = 7'h7F;
            4'd9:    pattern = 7'h6F;
            4'hA:    pattern = 7'h40;     // dash
            default: pattern = 7'h00;     // blank
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            seg <= (SEG_ACTIVE_LOW != 0) ? 7'h7F : 7'h00;
            dp  <= (SEG_ACTIVE_LOW != 0) ? 1'b1  : 1'b0;
            an  <= (AN_ACTIVE_LOW  != 0) ? 4'hF  : 4'h0;
        end else begin
            seg <= (SEG_ACTIVE_LOW != 0) ? ~pattern       : pattern;
            dp  <= (SEG_ACTIVE_LOW != 0) ? ~dp_mask[sel]  : dp_mask[sel];
            an  <= (AN_ACTIVE_LOW  != 0) ? ~(4'b0001 << sel) : (4'b0001 << sel);
        end
    end

endmodule
