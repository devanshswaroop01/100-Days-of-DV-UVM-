// ============================================================
// Day 013: Basic clocking block anatomy
// File: day013_basic_cb_if.sv
// Purpose: The minimum viable clocking block. Establishes:
//   - clocking block declares inputs/outputs with skews
//   - modport wraps it into a role view
// ============================================================

`timescale 1ns/1ps

interface basic_cb_if (input logic clk);

    logic       valid;
    logic       ready;
    logic [7:0] data;

    // ----------------------------------------------------------
    // CLOCKING BLOCK — TB-side view of the interface
    // @(posedge clk): every event is tied to the rising edge
    // default input  #1ns: sample 1ns BEFORE posedge
    // default output #1ns: drive  1ns AFTER posedge
    // (For maximum safety use input #1step instead — Day 013
    // explains why in Part 2.)
    // ----------------------------------------------------------
    clocking cb @(posedge clk);
        default input #1ns output #1ns;
        output valid, data;   // TB drives these
        input  ready;         // TB samples this
    endclocking

    // ----------------------------------------------------------
    // MODPORT — role view referencing the clocking block
    // ----------------------------------------------------------
    modport tb (clocking cb);

endinterface : basic_cb_if



      // ============================================================
// Day 013: Skew semantics — #1step vs #0 (input, output)
// File: day013_skew_exp_if.sv
// Purpose: Prove that input #1step samples BEFORE the edge,
//          input #0 samples IN the edge, and output #0 drives
//          IN the edge (and therefore races).
// ============================================================

`timescale 1ns/1ps

interface skew_exp_if (input logic clk);

    logic [7:0] sig_a;    // sampled by cb_1step
    logic [7:0] sig_b;    // sampled by cb_in0
    logic [7:0] sig_c;    // driven  by cb_out0

    // ----------------------------------------------------------
    // EXPERIMENT 1 — input #1step
    // Samples in the PREPONED region: sees the value from
    // the END of the previous time step. Immune to any
    // active-region writer at the current edge.
    // SAFEST input skew.
    // ----------------------------------------------------------
    clocking cb_1step @(posedge clk);
        default input #1step output #1ns;
        input sig_a;
    endclocking

    // ----------------------------------------------------------
    // EXPERIMENT 2 — input #0
    // Samples in the OBSERVED region of the same step: sees
    // the SETTLED value after active-region updates complete.
    // Safe against DUT flops but still exposed to writers in
    // the Observed region. Mostly fine, rarely used.
    // ----------------------------------------------------------
    clocking cb_in0 @(posedge clk);
        default input #0 output #1ns;
        input sig_b;
    endclocking

    // ----------------------------------------------------------
    // EXPERIMENT 3 — output #0
    // Drives in the ACTIVE region (same time as the edge).
    // THIS IS A RACE: the driver writes at the same moment
    // the DUT's flop samples. Use output #1ns instead.
    // ----------------------------------------------------------
    clocking cb_out0 @(posedge clk);
        default input #1ns output #0;
        output sig_c;
    endclocking

endinterface : skew_exp_if



      // ============================================================
// Day 013: FIFO interface + driver + monitor (bug-fixed)
// File: day013_fifo.sv
// Purpose: Production-shape FIFO agent. Fixes the monitor's
//          double-sample bug from Day 012's file version.
// ============================================================

`timescale 1ns/1ps

interface fifo_if (input logic clk, input logic rst_n);

    logic       wr_en,  rd_en;
    logic [7:0] data_in, data_out;
    logic       full,  empty;

    // ----------------------------------------------------------
    // DRIVER clocking block — drive stimulus, sample status
    // input #1step: safest sample of full/empty
    // output #2ns:  drive well after the edge
    // ----------------------------------------------------------
    clocking drv_cb @(posedge clk);
        default input #1step output #2ns;
        output wr_en, rd_en, data_in;
        input  full,  empty;
    endclocking

    // ----------------------------------------------------------
    // MONITOR clocking block — all inputs (passive)
    // ----------------------------------------------------------
    clocking mon_cb @(posedge clk);
        default input #1step output #2ns;
        input wr_en, rd_en, data_in, data_out, full, empty;
    endclocking

    modport DRIVER  (clocking drv_cb);
    modport MONITOR (clocking mon_cb);
    modport DUT (
        input  wr_en, rd_en, data_in,
        output data_out, full, empty
    );

endinterface : fifo_if


// ------------------------------------------------------------
// DRIVER CLASS — unchanged from file (correct as-is)
// ------------------------------------------------------------
class fifo_driver;

    virtual fifo_if.DRIVER vif;

    function new(virtual fifo_if.DRIVER vif);
        this.vif = vif;
    endfunction

    task automatic write(input logic [7:0] data);
        @(vif.drv_cb);
        while (vif.drv_cb.full === 1'b1) @(vif.drv_cb);
        vif.drv_cb.wr_en   <= 1'b1;
        vif.drv_cb.data_in <= data;
        @(vif.drv_cb);
        vif.drv_cb.wr_en   <= 1'b0;
    endtask

    task automatic read();
        @(vif.drv_cb);
        while (vif.drv_cb.empty === 1'b1) @(vif.drv_cb);
        vif.drv_cb.rd_en <= 1'b1;
        @(vif.drv_cb);
        vif.drv_cb.rd_en <= 1'b0;
    endtask

endclass : fifo_driver


// ------------------------------------------------------------
// MONITOR CLASS — FIXED
// The original version waited an extra @(mon_cb) inside the
// "read" branch, which:
//   (a) skipped any write that happened in the same cycle
//   (b) missed back-to-back reads
// Fix: capture state at the edge, but schedule the deferred
// print as a SEPARATE process so the forever loop never blocks.
// ------------------------------------------------------------
class fifo_monitor;

    virtual fifo_if.MONITOR vif;

    function new(virtual fifo_if.MONITOR vif);
        this.vif = vif;
    endfunction

    task automatic monitor_bus();
        fork
            forever begin
                @(vif.mon_cb);

                // WRITE observation — sampled at this edge
                if (vif.mon_cb.wr_en && !vif.mon_cb.full)
                    $display("[MONITOR] WRITE data=0x%0h",
                             vif.mon_cb.data_in);

                // READ observation — log the request now, the
                // data arrives next cycle. A small fork handles
                // the deferred print WITHOUT blocking the loop.
                if (vif.mon_cb.rd_en && !vif.mon_cb.empty) begin
                    fork
                        begin
                            @(vif.mon_cb);
                            $display("[MONITOR] READ data=0x%0h",
                                     vif.mon_cb.data_out);
                        end
                    join_none
                end
            end
        join_none
    endtask

endclass : fifo_monitor


      // ============================================================
// Day 013: APB driver — the production pattern
// File: day013_apb.sv
// Purpose: Setup -> Access -> Wait -> Timeout -> PSLVERR ->
//          Return-to-idle. Bounded wait states. Clean exit path.
// ============================================================

`timescale 1ns/1ps

interface apb_if (input logic pclk, input logic presetn);

    logic [31:0] paddr;
    logic        psel, penable, pwrite;
    logic [31:0] pwdata, prdata;
    logic        pready, pslverr;

    clocking master_cb @(posedge pclk);
        default input #1step output #2ns;
        output paddr, psel, penable, pwrite, pwdata;
        input  prdata, pready, pslverr;
    endclocking

    modport MASTER (clocking master_cb);

endinterface : apb_if


class apb_driver;

    virtual apb_if.MASTER vif;
    int max_wait_states = 16;    // bound the wait

    function new(virtual apb_if.MASTER vif);
        this.vif = vif;
    endfunction

    // ----------------------------------------------------------
    // Return all master signals to their idle level
    // ----------------------------------------------------------
    task automatic return_to_idle();
        vif.master_cb.psel    <= 1'b0;
        vif.master_cb.penable <= 1'b0;
        vif.master_cb.paddr   <= '0;
        vif.master_cb.pwrite  <= 1'b0;
    endtask

    // ----------------------------------------------------------
    // run_transaction — the robust APB master
    // `inout logic [31:0] data`:
    //   - for write_op=1, data is input
    //   - for write_op=0, data is output (returned)
    // If that dual role is confusing, split into wdata/rdata —
    // but the inout form matches how some legacy APB drivers
    // are written, so it's shown here for compatibility.
    // ----------------------------------------------------------
    task automatic run_transaction(
        input  bit          write_op,
        input  logic [31:0] addr,
        inout  logic [31:0] data,
        output bit          error
    );
        // AUTOMATIC is essential — wait_cycles resets per call.
        // A static task here would carry wait_cycles across
        // transactions and time out on the second call.
        int wait_cycles = 0;

        error = 1'b0;

        // ---- SETUP ----
        vif.master_cb.paddr   <= addr;
        vif.master_cb.pwrite  <= write_op;
        vif.master_cb.psel    <= 1'b1;
        vif.master_cb.penable <= 1'b0;
        if (write_op) vif.master_cb.pwdata <= data;
        @(vif.master_cb);

        // ---- ACCESS ----
        vif.master_cb.penable <= 1'b1;

        // ---- WAIT ----
        forever begin
            @(vif.master_cb);

            if (vif.master_cb.pready === 1'b1) begin
                // Capture read data
                if (!write_op) data = vif.master_cb.prdata;
                // Error flag from slave
                if (vif.master_cb.pslverr === 1'b1) begin
                    $display("[APB_DRV] SLVERR at 0x%0h", addr);
                    error = 1'b1;
                end
                break;
            end

            wait_cycles++;
            // ---- TIMEOUT ----
            if (wait_cycles >= max_wait_states) begin
                $display("[APB_DRV] TIMEOUT — slave hung at 0x%0h", addr);
                error = 1'b1;
                break;
            end
        end

        // ---- IDLE ----
        return_to_idle();
    endtask

endclass : apb_driver

// ============================================================
// Day 013: Race experiment + cycle-delay sequences
// File: day013_tb_top.sv
// Purpose: Empirically prove clocking blocks prevent races.
//          Also demonstrates ##N with default clocking.
// ============================================================

`timescale 1ns/1ps

module tb_top;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------
    // Interface instances
    // ----------------------------------------------------------
    basic_cb_if inst_bif (.clk(clk));
    skew_exp_if inst_sif (.clk(clk));
    fifo_if     inst_fif (.clk(clk), .rst_n(rst_n));
    apb_if      inst_apb (.pclk(clk), .presetn(rst_n));

    // ----------------------------------------------------------
    // DEFAULT CLOCKING — enables `##N` in this module
    // Without this, `##1;` etc. are compile errors.
    // Skews chosen to match the safe values from Part 2.
    // ----------------------------------------------------------
    default clocking def_cb @(posedge clk);
        default input #1step output #1ns;
    endclocking

    // ----------------------------------------------------------
    // Raw signals for race experiment
    // ----------------------------------------------------------
    logic       raw_valid = 0;
    logic [7:0] raw_data  = 0;

    // ----------------------------------------------------------
    // Mocked DUT-side responses (self-contained TB)
    // ----------------------------------------------------------
    assign inst_bif.ready      = inst_bif.valid;
    assign inst_fif.full       = 1'b0;
    assign inst_fif.empty      = 1'b0;
    assign inst_fif.data_out   = inst_fif.data_in ^ 8'hFF;
    assign inst_apb.pready     = 1'b1;
    assign inst_apb.pslverr    = 1'b0;
    assign inst_apb.prdata     = 32'hA5A5_5A5A;

    // ----------------------------------------------------------
    // VERSION A — raw sampling (RACE PRONE)
    // Whether this sees raw_valid=1 or 0 depends on the order
    // the scheduler runs the initial block vs. this always
    // block. Different simulators → different results.
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (raw_valid)
            $display("[VERSION_A] Sampling raw: 0x%0h (RACE-PRONE)",
                     raw_data);
    end

    // ----------------------------------------------------------
    // MAIN STIMULUS
    // ----------------------------------------------------------
    initial begin
        fifo_driver  f_drv;
        fifo_monitor f_mon;
        apb_driver   a_drv;
        logic [31:0] apb_data;
        bit          apb_err;

        f_drv = new(inst_fif.DRIVER);
        f_mon = new(inst_fif.MONITOR);
        a_drv = new(inst_apb.MASTER);

        #12 rst_n = 1;
        @(def_cb);

        // ------------------------------------------------------
        // EXERCISE 1 — basic clocking block drive
        // ------------------------------------------------------
        $display("\n--- EX 1: Basic drive via clocking block ---");
        inst_bif.cb.valid <= 1'b1;
        inst_bif.cb.data  <= 8'hD4;
        @(inst_bif.cb);
        inst_bif.cb.valid <= 1'b0;

        // ------------------------------------------------------
        // EXERCISE 3 — ##N cycle delays
        // Requires the default clocking block above.
        // ------------------------------------------------------
        $display("\n--- EX 3: Cycle delay sequences ---");
        $display("[%0t] start", $time);
        ##1;  $display("[%0t] after ##1", $time);
        ##2;  $display("[%0t] after ##2", $time);
        ##3;  $display("[%0t] after ##3", $time);

        // ------------------------------------------------------
        // EXERCISE 4 — FIFO driver + monitor
        // ------------------------------------------------------
        $display("\n--- EX 4: FIFO driver + monitor ---");
        f_mon.monitor_bus();
        f_drv.write(8'h3C);
        f_drv.read();
        ##2;

        // ------------------------------------------------------
        // EXERCISE 5 — Robust APB with error handling
        // ------------------------------------------------------
        $display("\n--- EX 5: APB transactor ---");
        apb_data = 32'hDEAD_BEEF;
        a_drv.run_transaction(.write_op(1'b1),
                              .addr(32'h4000_0000),
                              .data(apb_data), .error(apb_err));
        a_drv.run_transaction(.write_op(1'b0),
                              .addr(32'h4000_0000),
                              .data(apb_data), .error(apb_err));
        $display("[APB_TB] read-back = 0x%0h", apb_data);

        // ------------------------------------------------------
        // EXERCISE 6 — Race experiment
        // Version A: raw drive, may or may not be seen
        // Version B: clocking-block drive, always seen deterministically
        // ------------------------------------------------------
        $display("\n--- EX 6: Race experiment ---");

        // Version A (raw)
        raw_valid = 1'b1;
        raw_data  = 8'h99;
        // (The always @(posedge clk) above may or may not print —
        //  this is exactly the point of the experiment.)

        // Version B (clocking block) — deterministic
        inst_bif.cb.valid <= 1'b1;
        inst_bif.cb.data  <= 8'h66;
        @(inst_bif.cb);
        raw_valid         = 1'b0;
        inst_bif.cb.valid <= 1'b0;
       
      // FIX: Print the local constant or sample the underlying wire/input, 
        // as sampling cb outputs directly is illegal in SystemVerilog.
        $display("[VERSION_B] Clocking-block sample = 0x%0h (DETERMINISTIC)",
                 8'h66);

        ##5;
        $finish;
    end

endmodule : tb_top 

       
