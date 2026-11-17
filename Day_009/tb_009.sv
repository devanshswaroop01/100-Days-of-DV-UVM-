// ============================================================
// Day 009: 4:1 Multiplexer — always_comb + unique case
// File: day009_mux4x1.sv
// Purpose: Simplest combinational block. Shows default-
//          assignment-before-case to prevent latches, and
//          unique case to catch missing/overlapping selectors.
// ============================================================

`timescale 1ns/1ps

module mux4x1 (
    input  logic [7:0] in0, in1, in2, in3,
    input  logic [1:0] sel,
    output logic [7:0] out
);

    // ----------------------------------------------------------
    // always_comb: combinational block
    // - auto-sensitivity on in0..in3, sel
    // - executes at t=0 so `out` is never X at start
    // ----------------------------------------------------------
    always_comb begin
        // Default: kills unintended latch inference. If `sel` is
        // X/Z, out stays 0 instead of going X — usually desired
        // for output isolation, but verify your spec.
        out = 8'h00;

        // unique case: simulator errors if 0 or >1 branch match
        // With 2-bit sel, all 4 cases are covered, so `default`
        // is unnecessary — but adding it protects against X-prop
        // in the downstream tool.
        unique case (sel)
            2'b00: out = in0;
            2'b01: out = in1;
            2'b10: out = in2;
            2'b11: out = in3;
        endcase
    end

endmodule


// ============================================================
// Day 009: 16-bit Counter — always_ff idioms
// File: day009_counter16.sv
// Purpose: The reference always_ff block: async reset, sync
//          clear, enable, hold. Order of `if` clauses = priority.
// ============================================================

`timescale 1ns/1ps

module counter16 (
    input  logic        clk,
    input  logic        rst_n,    // active-low ASYNC reset
    input  logic        en,       // count-enable
    input  logic        syn_clr,  // SYNCHRONOUS clear
    output logic [15:0] count
);

    // ----------------------------------------------------------
    // always_ff: sequential block
    // - tool requires exactly one clock event in the header
    // - tool warns if you use blocking `=` on `count`
    // ----------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        // Priority: reset > sync_clr > en > hold
        if (!rst_n) begin
            count <= 16'h0000;       // async: fires on negedge rst_n
        end
        else if (syn_clr) begin
            count <= 16'h0000;       // sync: only at clk edge
        end
        else if (en) begin
            count <= count + 1'b1;   // increment
        end
        // No explicit else — count holds its value. always_ff
        // understands this as a flop, not a latch.
    end

endmodule


// ============================================================
// Day 009: 8-input Priority Encoder — priority case
// File: day009_priority_encoder8.sv
// Purpose: The canonical use of `priority case`. Highest-
//          numbered active request wins. `valid` flags whether
//          any request was active at all.
// ============================================================

`timescale 1ns/1ps

module priority_encoder8 (
    input  logic [7:0] req,
    output logic [2:0] grant,
    output logic       valid
);

    always_comb begin
        // Defaults prevent latches
        grant = 3'b000;
        valid = 1'b1;

        // ------------------------------------------------------
        // priority case (1'b1): each item is a boolean expression
        // First TRUE expression wins, top to bottom.
        // - req[7] checked before req[6], etc.
        // - simulator warns if multiple match — by design here
        // ------------------------------------------------------
        priority case (1'b1)
            req[7]: grant = 3'd7;
            req[6]: grant = 3'd6;
            req[5]: grant = 3'd5;
            req[4]: grant = 3'd4;
            req[3]: grant = 3'd3;
            req[2]: grant = 3'd2;
            req[1]: grant = 3'd1;
            req[0]: grant = 3'd0;
            default: begin
                grant = 3'b000;
                valid = 1'b0;   // no request active
            end
        endcase
    end

endmodule


// ============================================================
// Day 009: Two-Block DMA FSM (capstone)
// File: day009_dma_fsm.sv
// Purpose: The canonical two-block FSM. Combines:
//          - Exercise #1's combinational output decoder
//          - Exercise #2's sequential state register
//          - Exercise #6's enum-typed unified FSM
//          States: IDLE -> READ -> WRITE -> DONE -> IDLE
// ============================================================

`timescale 1ns/1ps

module dma_fsm (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic read_complete,
    input  logic write_complete,
    output logic dma_read,
    output logic dma_write,
    output logic dma_done,
    output logic busy
);

    // ----------------------------------------------------------
    // State encoding — enum gives us named states in waveforms
    // and compile-time type checking.
    // ----------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        READ  = 2'b01,
        WRITE = 2'b10,
        DONE  = 2'b11
    } dma_state_e;

    dma_state_e current_state, next_state;

    // ----------------------------------------------------------
    // BLOCK 1 — Combinational: next_state + outputs
    // - unique case: runtime error if current_state is X
    // - defaults first: no latches
    // - outputs computed here (combinational) so they're valid
    //   in the SAME cycle as current_state — Mealy-style.
    // ----------------------------------------------------------
    always_comb begin
        next_state = current_state;   // default: hold state
        dma_read   = 1'b0;
        dma_write  = 1'b0;
        dma_done   = 1'b0;
        busy       = 1'b0;

        unique case (current_state)
            IDLE: begin
                busy = 1'b0;
                if (start) next_state = READ;
            end
            READ: begin
                busy     = 1'b1;
                dma_read = 1'b1;
                if (read_complete) next_state = WRITE;
            end
            WRITE: begin
                busy      = 1'b1;
                dma_write = 1'b1;
                if (write_complete) next_state = DONE;
            end
            DONE: begin
                busy     = 1'b0;
                dma_done = 1'b1;
                next_state = IDLE;    // auto-return
            end
        endcase
    end

    // ----------------------------------------------------------
    // BLOCK 2 — Sequential: register next_state into current
    // - always_ff: exactly one clk edge
    // - async reset to IDLE
    // ----------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else        current_state <= next_state;
    end

endmodule 

// Code your design here
// ============================================================
// Day 009: DMA FSM Testbench
// File: day009_dma_fsm_tb.sv
// ============================================================

`timescale 1ns/1ps

module day009_dma_fsm_tb;

    logic clk, rst_n, start, read_complete, write_complete;
    logic dma_read, dma_write, dma_done, busy;

    dma_fsm dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .read_complete(read_complete),
        .write_complete(write_complete),
        .dma_read(dma_read), .dma_write(dma_write),
        .dma_done(dma_done), .busy(busy)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // State-change logger — one line per transition
    always @(dut.current_state) begin
        case (dut.current_state)
            2'b00: $display("[%0t] STATE -> IDLE",     $time);
            2'b01: $display("[%0t] STATE -> READ",     $time);
            2'b10: $display("[%0t] STATE -> WRITE",    $time);
            2'b11: $display("[%0t] STATE -> DONE",     $time);
        endcase
    end

    initial begin
        $display("===== DMA FSM TESTBENCH =====");

        // Init + reset
        start = 0; read_complete = 0; write_complete = 0;
        rst_n = 0;
        #12;                     // release reset out-of-phase
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        @(posedge clk);

        // IDLE -> READ
        $display("[%0t] Driving START=1", $time);
        start = 1;
        @(posedge clk);
        start = 0;
        #1;

        // READ -> WRITE
        $display("[%0t] Driving READ_COMPLETE=1", $time);
        read_complete = 1;
        @(posedge clk);
        read_complete = 0;
        #1;

        // WRITE -> DONE
        $display("[%0t] Driving WRITE_COMPLETE=1", $time);
        write_complete = 1;
        @(posedge clk);
        write_complete = 0;

        // DONE -> IDLE (auto)
        @(posedge clk);
        #1;

        $display("===== SIMULATION COMPLETE =====");
        $finish;
    end

endmodule 




// ============================================================
// Day 009: Blocking vs Non-Blocking — the swap experiment
// File: day009_assignment_semantics.sv
// Purpose: Prove that `<=` swaps correctly and `=` does not.
//          This is the canonical interview question, and it's
//          worth understanding at the scheduler level.
// ============================================================

`timescale 1ns/1ps

module assignment_semantics_demo;

    logic clk;
    logic [7:0] r1, r2;    // non-blocking experiment
    logic [7:0] b1, b2;    // blocking experiment

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------
    // Part A — NON-BLOCKING swap
    // Scheduler:
    //   1. Evaluate RHS:  r2_old, r1_old
    //   2. Schedule LHS updates for end of step
    //   3. Apply both updates concurrently
    // Result: r1 = old_r2, r2 = old_r1 — correct swap.
    // ----------------------------------------------------------
    always_ff @(posedge clk) begin
        r1 <= r2;
        r2 <= r1;
    end

    // ----------------------------------------------------------
    // Part B — BLOCKING swap (broken)
    // Scheduler:
    //   1. b1 = b2  -> b1 is now old_b2 IMMEDIATELY
    //   2. b2 = b1  -> reads the NEW b1 (= old_b2)
    // Result: b1 = old_b2, b2 = old_b2 — data loss.
    // ----------------------------------------------------------
    always_ff @(posedge clk) begin
        b1 = b2;
        b2 = b1;
    end

    initial begin
        $display("===== ASSIGNMENT SEMANTICS EXPERIMENT =====");

        // Different initial values
        r1 = 8'hAA; r2 = 8'hBB;
        b1 = 8'hAA; b2 = 8'hBB;

        $display("Before clock edge:");
        $display("  Non-blocking: R1=0x%0h, R2=0x%0h", r1, r2);
        $display("  Blocking:     B1=0x%0h, B2=0x%0h", b1, b2);

        @(posedge clk);
        #1;    // wait for non-blocking updates to land

        $display("After one clock edge:");
        $display("  Non-blocking: R1=0x%0h, R2=0x%0h  (SWAP OK)",
                 r1, r2);
        $display("  Blocking:     B1=0x%0h, B2=0x%0h  (DATA LOSS)",
                 b1, b2);

        $finish;
    end

endmodule

