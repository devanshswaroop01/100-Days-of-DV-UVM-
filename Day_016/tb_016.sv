
// ============================================================
// Day 016: Nested fork-join hierarchy
// File: day016_nested_fork.sv
// Purpose: Show that a fork branch can itself contain a fork.
//          The parent's `join` waits for the branch that has
//          the inner join — which waits for inner children.
// ============================================================
​
`timescale 1ns/1ps
​
module day016_nested_fork;
​
    task automatic run_exercise_1();
        $display("\n[EX1] --- Nested fork-join ---");
        $display("[%0t] Top parent active.", $time);
​
        // ------------------------------------------------------
        // OUTER fork: two branches, one of which contains an
        // INNER fork. The parent's `join` waits for BOTH outer
        // branches. Branch B contains an inner `join`, so the
        // outer join effectively waits for Branch B's children
        // too.
        // ------------------------------------------------------
        fork
            // Branch A: simple 20 ns delay
            begin : branch_a
                #20;
                $display("[%0t] Branch A complete.", $time);
            end
​
            // Branch B: inner fork — spawns two more children
            begin : branch_b
                $display("[%0t] Branch B started, spawning inner.",
                         $time);
​
                fork
                    begin
                        #10;
                        $display("[%0t]   B.child1 done.", $time);
                    end
                    begin
                        #30;
                        $display("[%0t]   B.child2 done.", $time);
                    end
                join   // inner join waits for child1 AND child2
​
                $display("[%0t] Branch B inner join done.", $time);
            end
        join       // outer join waits for A AND B
​
        $display("[%0t] Parent resumed.", $time);
    endtask
​
    initial begin
        run_exercise_1();
        $finish;
    end
​
endmodule 

// ============================================================
// Day 016: process::self() + await()
// File: day016_await.sv
// Purpose: Capture a process handle, then use await() to block
//          the parent until that specific worker finishes.
//
// FIX vs file version: the original never called await().
// Here, the parent truly blocks on worker completion.
// ============================================================

`timescale 1ns/1ps

module day016_await;

    task automatic run_exercise_2();
        // ------------------------------------------------------
        // SHARED handle — must be declared OUTSIDE both forks,
        // because the worker writes it and the parent reads it.
        // ------------------------------------------------------
        process worker_h;

        $display("\n[EX2] --- process::self() + await() ---");

        // ------------------------------------------------------
        // SPAWN WORKER: capture its own handle into worker_h
        // ------------------------------------------------------
        fork
            begin
                worker_h = process::self();
                $display("[%0t] Worker running (status=%s)",
                         $time, worker_h.status().name());
                #25;
                $display("[%0t] Worker finishing.", $time);
            end
        join_none

        // ------------------------------------------------------
        // PARENT WAITS: grab the handle, then block on await().
        // The #0 ensures the worker has run its process::self()
        // line and populated worker_h.
        // ------------------------------------------------------
        #0;   // yield so worker stores its handle

        if (worker_h == null) begin
            $display("[%0t] ERROR: worker_h still null", $time);
        end
        else begin
            $display("[%0t] Parent awaiting worker (status=%s)...",
                     $time, worker_h.status().name());
            worker_h.await();   // <-- THE MISSING LINE FROM THE FILE
            $display("[%0t] Parent unblocked (status=%s)",
                     $time, worker_h.status().name());
        end
    endtask

    initial begin
        run_exercise_2();
        $finish;
    end

endmodule

// ============================================================
// Day 016: Selective thread termination with kill()
// File: day016_kill.sv
// Purpose: Spawn 3 threads, kill ONLY one by handle, leave the
//          other two running to completion.
// ============================================================

`timescale 1ns/1ps

module day016_kill;

    task automatic run_exercise_3();
        process p0, p1, p2;

        $display("\n[EX3] --- Selective kill() ---");

        // ------------------------------------------------------
        // Spawn 3 threads with different durations
        // ------------------------------------------------------
        fork
            begin p0 = process::self(); #40;
                  $display("[%0t]   [P0] finished", $time); end
            begin p1 = process::self(); #20;
                  $display("[%0t]   [P1] finished", $time); end
            begin p2 = process::self(); #50;
                  $display("[%0t]   [P2] finished", $time); end
        join_none

        // Yield so all three threads populate their handles
        #5;

        // ------------------------------------------------------
        // Kill P1 only. P1 was going to finish at t=20, but we
        // kill it at t=5 — it will never print.
        // P0 and P2 continue to finish normally.
        // ------------------------------------------------------
        $display("[%0t] Killing P1 (was due at t=20).", $time);
        if (p1 != null) p1.kill();

        // ------------------------------------------------------
        // Wait for the survivors. Since we're using join_none,
        // `wait fork` is the safe barrier.
        // ------------------------------------------------------
        wait fork;

        // Confirm final statuses
        $display("[%0t] Final statuses:", $time);
        $display("    P0 = %s", p0.status().name());
        $display("    P1 = %s", p1.status().name());
        $display("    P2 = %s", p2.status().name());
    endtask

    initial begin
        run_exercise_3();
        $finish;
    end

endmodule 

          // ============================================================
// Day 016: Suspend and resume a running process
// File: day016_suspend.sv
// Purpose: Show that suspend/resume pauses the worker's `#delay`
//          and resumes it from where it left off. Total elapsed
//          = active_before + suspended + active_after.
// ============================================================

`timescale 1ns/1ps

module day016_suspend;

    task automatic run_exercise_4();
        process worker_p;

        $display("\n[EX4] --- Suspend / Resume ---");

        // ------------------------------------------------------
        // Spawn a worker that needs 50 ns of RUNNING time
        // ------------------------------------------------------
        fork
            begin
                worker_p = process::self();
                $display("[%0t]   [W] started (needs 50ns)", $time);
                #50;
                $display("[%0t]   [W] finished", $time);
            end
        join_none

        // ------------------------------------------------------
        // Let the worker run for 10 ns, then freeze it
        // ------------------------------------------------------
        #10;
        $display("[%0t] Suspending worker.", $time);
        worker_p.suspend();

        // ------------------------------------------------------
        // Parent's #20 advances simulation time, but the worker
        // is frozen. Its internal #50 count does NOT decrement
        // during this window.
        // ------------------------------------------------------
        #20;
        $display("[%0t] Resuming worker.", $time);
        worker_p.resume();

        // ------------------------------------------------------
        // Worker still needs 40 ns of active time (50 - 10 spent).
        // Total absolute completion:
        //   10 (before suspend) + 20 (suspended) + 40 (after) = 70 ns
        // ------------------------------------------------------
        worker_p.await();
        $display("[%0t] Worker confirmed done.", $time);
    endtask

    initial begin
        run_exercise_4();
        $finish;
    end

endmodule

          // Code your design here
// ============================================================
// Day 016: DMA watchdog with process handles
// File: day016_dma_watchdog.sv
// Purpose: Race transfer vs timeout via handles. Kill the loser
//          precisely — no blunt `disable fork`.
// ============================================================

`timescale 1ns/1ps

module day016_dma_watchdog;

    task automatic execute_dma_scenario(
        input int dma_delay,        // how long the DMA needs
        input int timeout_limit,    // watchdog threshold
        input string title
    );
        process dma_h, watchdog_h;

        $display("\n  Scenario: %s", title);

        // ------------------------------------------------------
        // Spawn DMA (transfer) and watchdog (timeout) in parallel.
        // Each captures its own handle.
        // ------------------------------------------------------
        fork
            begin
                dma_h = process::self();
                #(dma_delay);
                $display("[%0t]     DMA finished (delay=%0d)",
                         $time, dma_delay);
            end
            begin
                watchdog_h = process::self();
                #(timeout_limit);
                $display("[%0t]     WATCHDOG fired (timeout=%0d)",
                         $time, timeout_limit);
            end
        join_any

        // ------------------------------------------------------
        // Determine which one finished first and kill the loser.
        // Compare the delays — that's how we know which is which.
        // (A more robust version would use status() checks, but
        // for a fixed-delay demo the comparison is exact.)
        // ------------------------------------------------------
        if (dma_delay < timeout_limit) begin
            // DMA finished first — kill the still-waiting watchdog
            $display("[%0t]     Killing watchdog handle...", $time);
            if (watchdog_h != null) watchdog_h.kill();
        end
        else begin
            // Watchdog fired first — kill the still-waiting DMA
            $display("[%0t]     Killing DMA handle...", $time);
            if (dma_h != null) dma_h.kill();
        end

        #10;   // settle
    endtask

    initial begin
        $display("===== DMA Watchdog with Handles =====");

        // Case A: DMA (30) < timeout (80) -> DMA wins, watchdog killed
        execute_dma_scenario(30, 80, "Fast completion");

        // Case B: DMA (120) > timeout (80) -> timeout wins, DMA killed
        execute_dma_scenario(120, 80, "Watchdog expiry");

        $finish;
    end

endmodule 

          // ============================================================
// Day 016: N-channel process control matrix
// File: day016_dma_matrix.sv
// Purpose: Four parallel channels, kill one specific by handle,
//          wait for survivors. The capstone for Day 016.
// ============================================================

`timescale 1ns/1ps

module day016_dma_matrix;

    task automatic run_exercise_6();
        // ------------------------------------------------------
        // Array of handles — one per channel
        // ------------------------------------------------------
        process ch_handles[4];

        $display("\n[EX6] --- Four-Channel DMA Matrix ---");

        // ------------------------------------------------------
        // Spawn four channels, each capturing its own handle
        // ------------------------------------------------------
        fork
            begin ch_handles[0] = process::self(); #25;
                  $display("[%0t]   [CH0] done", $time); end
            begin ch_handles[1] = process::self(); #45;
                  $display("[%0t]   [CH1] done", $time); end
            begin ch_handles[2] = process::self(); #15;
                  $display("[%0t]   [CH2] done", $time); end
            begin ch_handles[3] = process::self(); #35;
                  $display("[%0t]   [CH3] done", $time); end
        join_none

        // ------------------------------------------------------
        // Yield so all handles are populated
        // ------------------------------------------------------
        #5;

        // ------------------------------------------------------
        // Kill channel 2 (was going to finish at t=15, but we
        // kill at t=5). Channel 2 never prints.
        // ------------------------------------------------------
        $display("[%0t] Killing CH2", $time);
        if (ch_handles[2] != null) ch_handles[2].kill();

        // ------------------------------------------------------
        // Wait for all remaining forks (CH0, CH1, CH3)
        // ------------------------------------------------------
        $display("[%0t] Waiting for survivors...", $time);
        wait fork;

        $display("[%0t] All settled.", $time);
        $display("[%0t] Final statuses:", $time);
        foreach (ch_handles[i])
            $display("    CH%0d = %s", i,
                     ch_handles[i].status().name());
    endtask

    initial begin
        run_exercise_6();
        $finish;
    end

endmodule
