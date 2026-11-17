// ============================================================
// Day 002: SystemVerilog Data Types
// File: day002_datatypes_tb.sv
// Purpose: Compare 4-state vs 2-state types, signed vs unsigned,
//          and integer widths in one run.
// ============================================================

`timescale 1ns/1ps

module day002_datatypes_tb;

    // ----------------------------------------------------------
    // FOUR-STATE DATA TYPES
    // - logic : SV universal type (replaces reg/wire in most uses)
    // - reg   : legacy Verilog procedural type (still legal in SV)
    // - wire  : net type — MUST be driven by `assign` or port
    // ----------------------------------------------------------
    logic l;      // 4-state, single driver, procedural or assign
    reg   r;      // 4-state, procedural only (legacy)
    wire  w;      // 4-state net, assign-only

    // ----------------------------------------------------------
    // TWO-STATE DATA TYPE
    // - bit : only 0/1, X or Z assignment silently -> 0
    // ----------------------------------------------------------
    bit   b;

    // ----------------------------------------------------------
    // SIGNED vs UNSIGNED
    // - unsigned is the DEFAULT for logic/reg/wire/bit
    // - `signed` keyword placed BEFORE the width
    // Both are 8 bits here -> same bits, different interpretation
    // ----------------------------------------------------------
    logic signed   [7:0] signed_num;
    logic unsigned [7:0] unsigned_num;

    // ----------------------------------------------------------
    // INTEGER TYPES (all signed by default)
    // byte=8, shortint=16, int=32, longint=64
    // ----------------------------------------------------------
    byte     byte_var;
    shortint short_var;
    int      int_var;
    longint  long_var;

    // ----------------------------------------------------------
    // CONTINUOUS ASSIGNMENT to wire
    // `w` follows `b` whenever `b` changes (event-driven)
    // NOTE: `w` is driven here — no other driver allowed.
    // ----------------------------------------------------------
    assign w = b;

    initial begin
        $display("===== DAY 002: DATA TYPES =====");

        // ------------------------------------------------------
        // Initial values — demonstrate 4-state capability
        // l = X (unknown), r = Z (high-Z), b = 0 (2-state)
        // ------------------------------------------------------
        l = 1'bx;
        r = 1'bz;
        b = 1'b0;
        #1;   // let the assign propagate to `w`

        $display("logic = %b", l);    // x  -> 4-state holds X
        $display("reg   = %b", r);    // z  -> 4-state holds Z
        $display("wire  = %b", w);    // 0  -> follows `b`
        $display("bit   = %b", b);    // 0  -> 2-state, clean

        // ------------------------------------------------------
        // Signedness demo: SAME bits, DIFFERENT decimal value
        // 8'b1111_1111 as unsigned = 255
        // 8'b1111_1111 as signed   = -1
        // ------------------------------------------------------
        signed_num   = 8'b1111_1111;
        unsigned_num = 8'b1111_1111;
        $display("Signed value   = %0d", signed_num);    // -1
        $display("Unsigned value = %0d", unsigned_num);  // 255

        // ------------------------------------------------------
        // Widths via $bits() — the portable query
        // ------------------------------------------------------
        $display("byte width     = %0d", $bits(byte_var));    // 8
        $display("shortint width = %0d", $bits(short_var));   // 16
        $display("int width      = %0d", $bits(int_var));     // 32
        $display("longint width  = %0d", $bits(long_var));    // 64
        $display("==============================");

        $finish;
    end

endmodule

 // ============================================================
// Day 002: Signed vs Unsigned Arithmetic
// File: day002_arithmetic_tb.sv
// Purpose: Show that + on unsigned wraps silently, while +
//          on signed stays in-range and produces correct math.
// ============================================================

`timescale 1ns/1ps

module day002_arithmetic_tb;

    // Unsigned 8-bit operands
    logic        [7:0] unsigned_a, unsigned_b, unsigned_result;

    // Signed 8-bit operands (explicit `signed` keyword)
    logic signed [7:0] signed_a,   signed_b,   signed_result;

    initial begin

        // ------------------------------------------------------
        // UNSIGNED OVERFLOW DEMO
        // 250 + 10 = 260, but 8 bits only hold 0..255
        // Result wraps: 260 mod 256 = 4
        // SystemVerilog does NOT warn — silent overflow.
        // ------------------------------------------------------
        unsigned_a = 8'd250;
        unsigned_b = 8'd10;
        unsigned_result = unsigned_a + unsigned_b;
        $display("Unsigned addition:");
        $display("%0d + %0d = %0d  (expected 260, wrapped)",
                 unsigned_a, unsigned_b, unsigned_result);   // 4

        // ------------------------------------------------------
        // SIGNED ARITHMETIC
        // 100 + 50 = 150, which fits in signed 8-bit (-128..127)?
        // NO — 150 > 127, so signed 8-bit wraps to -106.
        // Try a safe pair: 50 + 50 = 100 (in range).
        // ------------------------------------------------------
        signed_a = 8'sd50;
        signed_b = 8'sd50;
        signed_result = signed_a + signed_b;
        $display("Signed addition (safe):");
        $display("%0d + %0d = %0d",
                 signed_a, signed_b, signed_result);         // 100

        // Now force signed overflow to illustrate the wrap
        signed_a = 8'sd100;
        signed_b = 8'sd50;
        signed_result = signed_a + signed_b;
        $display("Signed addition (overflow):");
        $display("%0d + %0d = %0d  (wrapped to negative)",
                 signed_a, signed_b, signed_result);         // -106

        $finish;
    end

endmodule 

// ============================================================
// Day 002: X/Z Detection and Equality Operators
// File: day002_unknown_tb.sv
// Purpose: Contrast == (logical) with === (case) when X/Z
//          are present, and demonstrate $isunknown().
// ============================================================

`timescale 1ns/1ps

module day002_unknown_tb;

    logic [3:0] a, b;

    initial begin
        // Both vectors contain an X in bit [1]
        a = 4'b10x1;
        b = 4'b10x1;

        // ------------------------------------------------------
        // `==`  (logical equality)
        // If ANY bit is X/Z on either side -> result is X
        // So `a == b` yields X, not 1 — even though the
        // vectors are bit-identical!
        // ------------------------------------------------------
        $display("Logical equality: %b", a == b);    // x

        // ------------------------------------------------------
        // `===` (case equality)
        // Compares X/Z *literally* bit-by-bit.
        // Returns 1 or 0 only.
        // This is the TB's friend — use it for pass/fail.
        // ------------------------------------------------------
        $display("Case equality: %b", a === b);      // 1

        // ------------------------------------------------------
        // `$isunknown()` — system function
        // Returns 1 if ANY bit of the argument is X or Z.
        // Clean way to flag "this signal went bad".
        // ------------------------------------------------------
        $display("Contains unknown: %b", $isunknown(a));  // 1

        $finish;
    end

endmodule 
