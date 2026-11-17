// ============================================================
// Day 015: fork...join — all children must finish
// File: day015_parallel_dma.sv
// Purpose: Spawn N parallel channel tasks; parent blocks until
//          the SLOWEST one completes.
// ============================================================

`timescale 1ns/1ps

module day015_parallel_dma;

    // ----------------------------------------------------------
    // Channel task — automatic so each fork branch has its own
    // local `delay_time`. Without `automatic`, all 4 threads
    // share ONE storage location → all see the last value.
    // ----------------------------------------------------------
    task automatic run_channel(input int channel_id);
        int delay_time;
        delay_time = 10 * (channel_id + 1);   // 10, 20, 30, 40

        $display("[CH %0d] START   at t=%0t", channel_id, $time);
        #(delay_time);
        $display("[CH %0d] DONE    at t=%0t", channel_id, $time);
    endtask

    initial begin
        $display("===== fork...join (all must finish) =====");

        fork
            run_channel(0);   // 10 ns
            run_channel(1);   // 20 ns
            run_channel(2);   // 30 ns
            run_channel(3);   // 40 ns  <-- slowest
        join
        // Reached only after ALL 4 children complete

        $display("ALL DMA CHANNELS COMPLETED at t=%0t", $time);
        $finish;
    end

endmodule


// ============================================================
// Day 015: fork...join_any — first child wins
// File: day015_join_any.sv
// Purpose: Spawn 3 children with different delays. Parent
//          resumes as soon as the FIRST one completes.
// ============================================================

`timescale 1ns/1ps

module day015_join_any;

    initial begin
        $display("===== fork...join_any =====");
        $display("[%0t] Parent spawning 3 threads...", $time);

        fork
            begin #15; $display("[%0t] Child A done (15)", $time); end
            begin #5;  $display("[%0t] Child B done (5)  <-- FIRST", $time); end
            begin #25; $display("[%0t] Child C done (25)", $time); end
        join_any

        // Parent resumes here as soon as Child B finishes (t=5)
        $display("[%0t] Parent resumed! Child B finished first.", $time);

        // ----------------------------------------------------------
        // CRITICAL: Children A and C are still running in the
        // background. If we $finish now, they'll never get to
        // print their DONE messages.
        //
        // Two options:
        //   (a) Wait for them: #25 (or wait fork)
        //   (b) Kill them:      disable fork
        //
        // For a demo, wait — cleaner output. In a real watchdog
        // you'd kill them.
        // ----------------------------------------------------------
        #25;
        $display("[%0t] All background threads resolved.", $time);
        $finish;
    end

endmodule 


// ============================================================
// Day 015: fork...join_none + wait fork
// File: day015_join_none.sv
// Purpose: Fire-and-forget background threads, then
//          synchronize at a barrier with `wait fork`.
// ============================================================

`timescale 1ns/1ps

module day015_join_none;

    initial begin
        $display("===== fork...join_none + wait fork =====");
        $display("[%0t] Spawning background tasks...", $time);

        fork
            begin #12; $display("[%0t] BG Task X done (12)", $time); end
            begin #8;  $display("[%0t] BG Task Y done (8)",  $time); end
            begin #18; $display("[%0t] BG Task Z done (18)", $time); end
        join_none

        // ----------------------------------------------------------
        // Parent resumes IMMEDIATELY at t=0 — BEFORE any child
        // has even started their delays.
        // ----------------------------------------------------------
        $display("[%0t] Parent continued INSTANTLY (no wait).",
                 $time);

        // ----------------------------------------------------------
        // Do some "parent" work in parallel with the background
        // threads. This is where a real TB would do setup,
        // reporting, or another stimulus thread.
        // ----------------------------------------------------------
        #3;
        $display("[%0t] Parent doing other work...", $time);

        // ----------------------------------------------------------
        // BARRIER: wait for all fork-spawned threads in this
        // scope to finish. After this point, no background thread
        // is still running.
        // ----------------------------------------------------------
        wait fork;
        $display("[%0t] Barrier crossed. All BG tasks resolved.",
                 $time);
        $finish;
    end

endmodule 


          // ============================================================
// Day 015: Timeout watchdog — the canonical pattern
// File: day015_timeout.sv
// Purpose: Race transfer-completion vs timeout. Whichever
//          finishes first, kill the other.
// ============================================================

`timescale 1ns/1ps

module day015_timeout;

    // ----------------------------------------------------------
    // Reusable timeout wrapper
    // - done_delay:    how long the transfer takes
    // - timeout_delay: how long the watchdog waits
    // - title:         for log readability
    // ----------------------------------------------------------
    task automatic execute_monitored_dma(
        input int done_delay,
        input int timeout_delay,
        input string title
    );
        bit timed_out;

        $display("\n[%0t] Scenario: %s", $time, title);

        // ------------------------------------------------------
        // Two children race: transfer vs watchdog.
        // join_any resumes at whichever finishes first.
        // ------------------------------------------------------
        fork : race_block
            begin
                #(done_delay);
                $display("[%0t]   Transfer COMPLETE (done_delay=%0d)",
                         $time, done_delay);
                timed_out = 0;
            end
            begin
                #(timeout_delay);
                $display("[%0t]   WATCHDOG EXPIRED (timeout=%0d)",
                         $time, timeout_delay);
                timed_out = 1;
            end
        join_any

        // ------------------------------------------------------
        // Kill whichever child is still running. Using the named
        // block `race_block` scopes the disable correctly.
        // ------------------------------------------------------
        disable race_block;

        if (timed_out)
            $display("[%0t]   RESULT: FAIL — timeout", $time);
        else
            $display("[%0t]   RESULT: PASS — completed", $time);
    endtask

    // ----------------------------------------------------------
    // Main stimulus — one fast case, one slow case
    // ----------------------------------------------------------
    initial begin
        $display("===== Timeout Watchdog =====");

        // Case A: transfer (60) < timeout (100) -> PASS
        execute_monitored_dma(60, 100, "Fast transfer");

        // Case B: transfer (140) > timeout (100) -> FAIL (timeout wins)
        execute_monitored_dma(140, 100, "Slow transfer (will timeout)");

        $finish;
    end

endmodule


          // ============================================================
// Day 015: Concurrent APB monitors — the real-world pattern
// File: day015_concurrent_apb.sv
// Purpose: 3 monitors race for PREADY, PSLVERR, or timeout.
//          First match wins; others are disabled.
//          This is the canonical UVM monitor shape.
// ============================================================

`timescale 1ns/1ps

module day015_concurrent_apb;

    // ----------------------------------------------------------
    // APB response signals — driven by external stimulus
    // ----------------------------------------------------------
    logic apb_pready  = 0;
    logic apb_pslverr = 0;

    // ----------------------------------------------------------
    // MONITOR — the canonical multi-condition pattern
    // 3 trackers race:
    //   ready   -> success
    //   error   -> SLVERR
    //   timeout -> watchdog
    // First to fire wins; others disabled.
    // ----------------------------------------------------------
    task automatic apb_bus_transaction_monitor();
        $display("[%0t]   [MON] Arming bus sniffers...", $time);

        fork : sniff_block
            begin : ready_tracker
                wait (apb_pready === 1'b1);
                $display("[%0t]     -> SUCCESS handshake detected",
                         $time);
            end
            begin : error_tracker
                wait (apb_pslverr === 1'b1);
                $display("[%0t]     -> ERROR response detected",
                         $time);
            end
            begin : timeout_tracker
                #100;
                $display("[%0t]     -> TIMEOUT — bus unresponsive",
                         $time);
            end
        join_any

        // ------------------------------------------------------
        // Kill the losers. Named block scoping (`sniff_block`)
        // ensures we don't accidentally disable other forks in
        // the same calling scope.
        // ------------------------------------------------------
        disable sniff_block;
        $display("[%0t]   [MON] Target matched. Sniffers disarmed.",
                 $time);
    endtask

    // ----------------------------------------------------------
    // Main stimulus — two scenarios
    // ----------------------------------------------------------
    initial begin
        $display("===== Concurrent APB Verification =====");

        // ------------------------------------------------------
        // Scenario 1: normal completion
        // Slave asserts PREADY at t=20, then deasserts.
        // Monitor fires at t=20 before timeout.
        // ------------------------------------------------------
        $display("\n[%0t] Scenario 1: Normal completion", $time);
        fork
            begin
                #20 apb_pready = 1;
                #10 apb_pready = 0;
            end
            apb_bus_transaction_monitor();
        join

        // ------------------------------------------------------
        // Scenario 2: error response
        // Reset flags, then slave asserts PSLVERR at t=15.
        // ------------------------------------------------------
        apb_pready  = 0;
        apb_pslverr = 0;
        $display("\n[%0t] Scenario 2: Error response", $time);
        fork
            begin
                #15 apb_pslverr = 1;
                #10 apb_pslverr = 0;
            end
            apb_bus_transaction_monitor();
        join

        $finish;
    end

endmodule 

          
