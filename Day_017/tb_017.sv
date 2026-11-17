// ============================================================
// Day 017: Semaphore as a mutex
// File: day017_mutex.sv
// Purpose: semaphore new(1) = classic mutex. Only one thread
//          can hold the single key at a time.
//
// Framing note: EX1 and EX4 in the file are the same pattern
// with different names (thread vs. bus master). This module
// demonstrates both — the "bus arbiter" is just the mutex
// renamed to reflect the shared-resource it protects.
// ============================================================

`timescale 1ns/1ps

module day017_mutex;

    task automatic run_exercise_1();

        // ------------------------------------------------------
        // new(1) = single-key semaphore = mutex
        // Only ONE thread may hold the key at a time.
        // ------------------------------------------------------
        semaphore sem_lock = new(1);
		semaphore bus_lock = new(1);

        $display("\n[EX1] --- Mutex: one holder at a time ---");

        fork
            // Thread X — acquires first
            begin : thread_x
                $display("[%0t] Thread X requesting key...", $time);
                sem_lock.get(1);   // blocks if key not free
                $display("[%0t]   X acquired key (hold 20ns)", $time);
                #20;
                $display("[%0t]   X releasing key", $time);
                sem_lock.put(1);
            end

            // Thread Y — starts 2ns later, must wait for X
            begin : thread_y
                #2;
                $display("[%0t] Thread Y requesting key...", $time);
                sem_lock.get(1);   // blocks until X releases
                $display("[%0t]   Y acquired key (hold 10ns)", $time);
                #10;
                $display("[%0t]   Y releasing key", $time);
                sem_lock.put(1);
            end
        join

        // ------------------------------------------------------
        // Bus-arbiter framing: the SAME semaphore pattern,
        // protecting a shared APB bus. Each "master" holds the
        // lock for its transaction duration.
        // ------------------------------------------------------
        $display("\n[EX1b] --- Bus arbiter: same pattern, new names ---");


        fork
            execute_bus_master(0, 32'hA000_0000, 25, bus_lock);
            execute_bus_master(1, 32'hB000_0000, 15, bus_lock);
        join
    endtask

    task automatic execute_bus_master(
        input int           master_id,
        input logic [31:0]  base_addr,
        input int           cycles,
        input semaphore     arb
    );
        $display("[%0t] [M%0d] planning burst to 0x%0h",
                 $time, master_id, base_addr);
        arb.get(1);   // serialize bus access
        $display("[%0t]   [M%0d] LOCK acquired", $time, master_id);
        #(cycles);
        $display("[%0t]   [M%0d] LOCK releasing", $time, master_id);
        arb.put(1);
    endtask

    initial begin
        run_exercise_1();
        $finish;
    end

endmodule

// ============================================================
// Day 017: Semaphore as an N-key resource pool
// File: day017_pool.sv
// Purpose: new(N) = N concurrent users allowed. N+1th waits.
//
// Framing note: EX2 (3-key, 5 workers) and EX5 (2-key, 4 DMA
// channels) are the same pattern with different numbers. This
// module uses N=3 with 5 contenders, plus a dual-port RAM
// framing at the end.
// ============================================================

`timescale 1ns/1ps

module day017_pool;

    task automatic run_exercise_2();

        // ------------------------------------------------------
        // new(3) = at most 3 threads may hold keys concurrently
        // ------------------------------------------------------
        semaphore triple_sem = new(3);
		semaphore mem_ports = new(2);


        $display("\n[EX2] --- Pool: 3 keys, 5 contenders ---");

        fork
            spawn_worker(0, 15, triple_sem);
            spawn_worker(1, 25, triple_sem);
            spawn_worker(2, 10, triple_sem);
            spawn_worker(3, 20, triple_sem);
            spawn_worker(4, 15, triple_sem);
        join

        // ------------------------------------------------------
        // Dual-port RAM framing: N=2, 4 DMA channels contend
        // ------------------------------------------------------
        $display("\n[EX2b] --- Dual-port RAM: 2 ports, 4 channels ---");
    
        fork
            dma_channel_mem_access(0, 30, mem_ports);
            dma_channel_mem_access(1, 10, mem_ports);
            dma_channel_mem_access(2, 20, mem_ports);
            dma_channel_mem_access(3, 15, mem_ports);
        join
    endtask

    // ----------------------------------------------------------
    // Generic worker — grabs one key, holds for `duration`, frees
    // ----------------------------------------------------------
    task automatic spawn_worker(
        input int       id,
        input int       duration,
        input semaphore sem
    );
        $display("[%0t]   [W%0d] requesting", $time, id);
        sem.get(1);   // blocks if all 3 keys are taken
        $display("[%0t]     >>> [W%0d] ENTERED (hold %0dns)",
                 $time, id, duration);
        #(duration);
        $display("[%0t]     <<< [W%0d] LEAVING", $time, id);
        sem.put(1);
    endtask

    // ----------------------------------------------------------
    // DMA channel — grabs one of 2 memory-port keys
    // ----------------------------------------------------------
    task automatic dma_channel_mem_access(
        input int       ch,
        input int       duration,
        input semaphore ports
    );
        $display("[%0t] [CH%0d] queueing", $time, ch);
        ports.get(1);
        $display("[%0t]   [CH%0d] PORT captured", $time, ch);
        #(duration);
        $display("[%0t]   [CH%0d] PORT freed", $time, ch);
        ports.put(1);
    endtask

    initial begin
        run_exercise_2();
        $finish;
    end

endmodule  

// ============================================================
// Day 017: try_get — non-blocking poll
// File: day017_try_get.sv
// Purpose: try_get returns immediately — 1 if key taken,
//          0 if unavailable. Caller decides what to do.
// ============================================================

`timescale 1ns/1ps

module day017_try_get;

    task automatic run_exercise_3();

        semaphore mutex = new(1);

        $display("\n[EX3] --- try_get: non-blocking poll ---");

        fork
            // ------------------------------------------------------
            // Process A — takes the key first, holds 30ns
            // ------------------------------------------------------
            begin : proc_a
                mutex.get(1);
                $display("[%0t] A locked (hold 30ns)", $time);
                #30;
                mutex.put(1);
                $display("[%0t] A released", $time);
            end

            // ------------------------------------------------------
            // Process B — polls twice
            // First at t=10 (A holds key) -> try_get returns 0
            // Second at t=35 (A released) -> try_get returns 1
            // ------------------------------------------------------
            begin : proc_b
                #10;
                $display("[%0t] B: poll #1...", $time);
                if (mutex.try_get(1) > 0) begin
                    $display("[%0t]   B: got key (unexpected!)", $time);
                    mutex.put(1);
                end
                else begin
                    $display("[%0t]   B: busy — alternate logic",
                             $time);
                end

                #25;   // now t=35, A has released

                $display("[%0t] B: poll #2...", $time);
                if (mutex.try_get(1) > 0) begin
                    $display("[%0t]   B: got key", $time);
                    #5;
                    mutex.put(1);
                end
                else begin
                    $display("[%0t]   B: still busy", $time);
                end
            end
        join
    endtask

    initial begin
        run_exercise_3();
        $finish;
    end

endmodule 

// ============================================================
// Day 017: The kill-deadlock trap and its recovery
// File: day017_kill_recovery.sv
// Purpose: Prove that killing a thread holding a semaphore key
//          LEAKS the key forever. Demonstrate the mandatory
//          recovery pattern: manually put() the key back.
//
// WARNING: without the recovery block, the second contender
//          HANGS FOREVER at get(1).
// ============================================================

`timescale 1ns/1ps

module day017_kill_recovery;

    task automatic run_exercise_6();

        semaphore critical_resource = new(1);
        process   worker_process;

        $display("\n[EX6] --- Kill-cancellation deadlock + recovery ---");

        fork
            // ==================================================
            // BRANCH 1 — spawn worker, then kill it, then recover
            // ==================================================
            begin
                // ------------------------------------------------
                // Spawn worker as a background process so we can
                // kill it from this branch after a delay.
                // ------------------------------------------------
                fork
                    begin
                        worker_process = process::self();
                        $display("[%0t]   [Worker] requesting", $time);
                        critical_resource.get(1);    // acquires key
                        $display("[%0t]   [Worker] LOCK held", $time);

                        #100;   // long critical section

                        // If not killed, this would release. But we
                        // WILL kill before this runs.
                        critical_resource.put(1);
                    end
                join_none

                // ------------------------------------------------
                // Wait until worker is firmly holding the key
                // ------------------------------------------------
                #20;
                $display("[%0t] [ENV] Killing worker (key still held!)",
                         $time);
                if (worker_process != null) worker_process.kill();

                // ------------------------------------------------
                // CRITICAL RECOVERY STEP
                // kill() does NOT return the key. The semaphore
                // counter is now permanently 0. Without this
                // put(), the next contender would HANG FOREVER.
                // ------------------------------------------------
                $display("[%0t] [ENV] RECOVERY: forcing put(1) to restore key",
                         $time);
                critical_resource.put(1);
            end

            // ==================================================
            // BRANCH 2 — contender tries to acquire the resource
            // ==================================================
            begin
                #30;   // arrives after kill + recovery
                $display("[%0t]   [Contender] requesting key", $time);
                critical_resource.get(1);
                // If the recovery put() is missing, this line
                // NEVER executes — simulation hangs.
                $display("[%0t]   [Contender] ACQUIRED — no deadlock",
                         $time);
                #5;
                critical_resource.put(1);
            end
        join
    endtask

    initial begin
        run_exercise_6();
        $finish;
    end

endmodule 

  
