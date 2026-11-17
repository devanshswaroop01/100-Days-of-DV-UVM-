// ============================================================
// Day 001: Standard SystemVerilog Testbench Structure
// File: day001_basic_tb.sv
// Purpose: Demonstrate minimum viable TB — clock, reset,
//          monitor, and clean simulation control.
// ============================================================

`timescale 1ns/1ps   // time_unit=1ns, time_precision=1ps
                     // ALL #delays are interpreted in ns
                     // Simulation resolves events to 1ps granularity

module day001_basic_tb;

    // ----------------------------------------------------------
    // 1. SIGNAL DECLARATIONS
    // Use `logic` (SV) instead of `reg`/`wire` (Verilog)
    // because logic can be driven from initial/always blocks
    // and connected to module ports.
    // ----------------------------------------------------------
    logic clk;       // 100 MHz clock
    logic rst_n;     // Active-low reset

    // ----------------------------------------------------------
    // 2. CLOCK GENERATION
    // 100 MHz => Period = 10 ns => half-period = 5 ns
    // `forever` loops indefinitely — standard TB idiom.
    // ----------------------------------------------------------
    initial begin
        clk = 1'b0;                       // Initialize at t=0
        forever #5 clk = ~clk;            // Toggle every 5ns
    end
    // Waveform: 0ns:0, 5ns:1, 10ns:0, 15ns:1, ... period=10ns

    // ----------------------------------------------------------
    // 3. RESET GENERATION (Active-Low)
    // Hold reset low for 5 clock edges, then release.
    // Using @(posedge clk) makes reset synchronous to clock —
    // deterministic and avoids race with clock edges.
    // ----------------------------------------------------------
    initial begin
        rst_n = 1'b0;                     // Assert reset at t=0
        repeat (5) @(posedge clk);        // Wait 5 rising edges
        rst_n = 1'b1;                     // Release reset
    end

    // ----------------------------------------------------------
    // 4. SIMULATION CONTROL + MONITORING
    // $display: one-shot print
    // $monitor: prints only when a listed signal changes
    // wait()  : blocks until condition is true
    // $finish: ends simulation (required — else infinite loop)
    // ----------------------------------------------------------
    initial begin
        $display("--------------------------------");
        $display("Day 001: Basic Testbench Started");
        $display("--------------------------------");

        // $monitor fires on ANY change of clk or rst_n
        $monitor("Time=%0t | clk=%0b | rst_n=%0b",
                 $time, clk, rst_n);

        wait(rst_n == 1'b1);              // Block until reset released
        @(posedge clk);                   // Align to next clock edge
        $display("Reset released. Testbench running.");

        #50;                              // Run 50ns of "work"
        $display("Simulation completed.");
        $finish;                          // MUST call to stop sim
    end

endmodule 

// ============================================================
// Day 001: module vs program block semantics
// File: day001_module_vs_program.sv
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// DUT (Design Under Test) — MUST be a module
// Simulates a simple toggle flop on the clock.
// ------------------------------------------------------------
module dut;
    logic clk;
    logic data;

    // Clock generator (in real design, clock comes from outside;
    // here we self-generate for a self-contained demo)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Toggle `data` on every rising edge — synthesizable RTL
    always @(posedge clk) begin
        data <= ~data;
    end
endmodule

// ------------------------------------------------------------
// PROGRAM BLOCK — testbench-only environment
// Key rules enforced by SV:
//   * Only `initial` and `final` blocks allowed
//   * NO `always`, `assign`, or hardware constructs
//   * Executes in the REACTIVE region of the scheduler,
//     AFTER all active-region (DUT) updates settle.
// This eliminates TB/DUT race conditions.
// ------------------------------------------------------------
program test_program;
    initial begin
        $display("[PROGRAM] Executing at %0t", $time);
    end
endprogram

// ------------------------------------------------------------
// TOP — instantiates DUT + program
// Program blocks are instantiated like modules in SV.
// ------------------------------------------------------------
module top;
    dut            d1();   // DUT instance
    test_program   p1();   // Program instance

    initial begin
        // Simulate for a short window then finish
        #50;
        $display("[TOP] Finishing at %0t", $time);
        $finish;
    end
endmodule

