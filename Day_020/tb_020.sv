// ============================================================
// Day 020: SystemVerilog Fundamentals — DMA Verification Capstone
// File: day020_dma_capstone.sv
// Purpose: Integrate every SystemVerilog primitive learned in
//          Days 001-019 into a working multi-channel DMA TB:
//            - classes, dynamic arrays, queues (via mailbox)
//            - tasks (generators, consumers, watchdog)
//            - interfaces, clocking blocks
//            - fork-join variants, semaphores, mailboxes, events
// ============================================================

`timescale 1ns/1ps

// ============================================================
// 1. DMA TRANSACTION CLASS
// ============================================================
class dma_transaction;

    // ------------------------------------------------------
    // FIELDS — rand for future randomization
    // ------------------------------------------------------
    rand int unsigned channel_id;
    rand int unsigned transaction_id;
    rand bit   [31:0] source_addr;
    rand bit   [31:0] destination_addr;
    rand bit   [15:0] transfer_length;
    rand bit   [31:0] data;

    // ------------------------------------------------------
    // CONSTRAINT — aligned addresses, bounded length
    // ------------------------------------------------------
    constraint c_sane {
        source_addr[1:0]      == 2'b00;   // 4-byte aligned
        destination_addr[1:0] == 2'b00;
        transfer_length       inside {[1:1024]};
    }

    // ------------------------------------------------------
    // DISPLAY — for debug logs
    // ------------------------------------------------------
    function void display();
        $display("[TX] CH=%0d ID=%0d SRC=0x%h DST=0x%h LEN=%0d DATA=0x%h",
                 channel_id, transaction_id,
                 source_addr, destination_addr,
                 transfer_length, data);
    endfunction

endclass : dma_transaction


// ============================================================
// 2. DMA TESTBENCH INTERFACE
// ============================================================
interface dma_tb_if;

    // ------------------------------------------------------
    // Clock and reset signals
    // ------------------------------------------------------
    logic clk;
    logic rst_n;

    // ------------------------------------------------------
    // CLOCK GENERATOR — 100 MHz
    // ------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------
    // CLOCKING BLOCK — TB side, all signals
    // Skews chosen per Day 013: input #1step, output #1ns
    // (For this simple TB, only rst_n is sampled by the TB —
    // but the clocking block is in place for future expansion.)
    // ------------------------------------------------------
    clocking cb @(posedge clk);
        default input #1step output #1ns;
        input rst_n;
    endclocking

endinterface : dma_tb_if


// ============================================================
// 3. TOP-LEVEL TESTBENCH
// ============================================================
module dma_capstone_tb;

    // ------------------------------------------------------
    // INTERFACE INSTANCE
    // ------------------------------------------------------
    dma_tb_if intf();

    // ------------------------------------------------------
    // SYNCHRONIZATION PRIMITIVES
    // - per-channel mailbox for data
    // - single semaphore for shared-memory arbitration
    // - events for completion signaling
    // ------------------------------------------------------
    mailbox #(dma_transaction) channel_mbx[2];
    semaphore                  shared_mem_lock;

    event ch0_done;
    event ch1_done;
    event all_dma_done;

    // ------------------------------------------------------
    // COMPLETION FLAGS (persistent, per Day 019)
    // - channel_done[i] is the level-sensitive equivalent of
    //   the per-channel event. Used by the coordinator.
    // - completion_seen is set by the listener; used by the
    //   watchdog.
    // ------------------------------------------------------
    bit channel_done[2];
    bit completion_seen;
    bit listener_ready_flag;
    bit timeout_flag;

    // ------------------------------------------------------
    // PER-CHANNEL COUNTERS
    // ------------------------------------------------------
    int processed_count[2];

    // ------------------------------------------------------
    // TEST PARAMETERS
    // ------------------------------------------------------
    localparam int NUM_TRANSACTIONS = 3;
    localparam time TIMEOUT_LIMIT   = 500ns;

    // ======================================================
    // 4. RESET GENERATION
    // ======================================================
    initial begin : reset_generation
        intf.rst_n = 0;
        repeat (2) @(posedge intf.clk);
        intf.rst_n = 1;
        $display("[RESET] Reset released at %0t", $time);
    end

    // ======================================================
    // 5. DMA TRANSACTION GENERATOR (one task, parameterized)
    // ======================================================
    task automatic dma_generator(
        input int channel_id,
        input int transaction_count
    );
        dma_transaction tx;
        for (int i = 0; i < transaction_count; i++) begin
            tx = new();
            tx.channel_id      = channel_id;
            tx.transaction_id  = i;
            tx.source_addr     = 32'h1000
                               + (channel_id * 32'h100)
                               + (i * 4);
            tx.destination_addr= 32'h8000
                               + (channel_id * 32'h100)
                               + (i * 4);
            tx.transfer_length = 4 + i;
            tx.data            = 32'hA500_0000
                               | (channel_id << 8)
                               | i;

            // Mailbox is unbounded -> put() never blocks.
            // (If bounded, this would be where the producer
            //  stalls for backpressure.)
            channel_mbx[channel_id].put(tx);
            $display("[GEN] CH=%0d generated TX=%0d at %0t",
                     channel_id, i, $time);
        end
    endtask

    // ======================================================
    // 6. DMA TRANSACTION CONSUMER
    // ======================================================
    task automatic dma_consumer(
        input int channel_id,
        input int transaction_count
    );
        dma_transaction rx;

        for (int i = 0; i < transaction_count; i++) begin
            // --------------------------------------------
            // Receive transaction (blocks until available)
            // --------------------------------------------
            channel_mbx[channel_id].get(rx);
            $display("[DRV] CH=%0d received TX=%0d at %0t",
                     channel_id, rx.transaction_id, $time);

            // --------------------------------------------
            // Acquire shared-memory lock
            // (Semaphore ensures mutual exclusion between
            //  the two channels.)
            // --------------------------------------------
            shared_mem_lock.get(1);
            $display("[MEM] CH=%0d acquired memory lock",
                     channel_id);

            // --------------------------------------------
            // Simulated memory operation
            // NOTE: if this task could be killed while
            // holding the lock, we'd need put(1) at the
            // kill site (Day 017 lesson). This TB has no
            // kill, so the put() below is sufficient.
            // --------------------------------------------
            #10;

            $display("[MEM] CH=%0d released memory lock at %0t",
                     channel_id, $time);
            shared_mem_lock.put(1);

            rx.display();

            // --------------------------------------------
            // Per-channel counter increment
            // (Not actually racy — each channel owns its
            //  own index — but += 1 is the cleaner style.)
            // --------------------------------------------
            processed_count[channel_id] += 1;
        end

        // --------------------------------------------
        // Per-channel completion: set persistent flag,
        // then fire the event (Day 019 pattern)
        // --------------------------------------------
        channel_done[channel_id] = 1'b1;

        if (channel_id == 0) -> ch0_done;
        else                 -> ch1_done;

        $display("[DONE] Channel %0d completed at %0t",
                 channel_id, $time);
    endtask

    // ======================================================
    // 7. INDIVIDUAL CHANNEL COMPLETION MONITORS
    // ======================================================
    initial begin : ch0_listener
        @ch0_done;
        $display("[EVENT] DMA channel 0 completed");
    end

    initial begin : ch1_listener
        @ch1_done;
        $display("[EVENT] DMA channel 1 completed");
    end

    // ======================================================
    // 8. GLOBAL COMPLETION COORDINATOR
    // Uses level-sensitive wait (not @), so channel
    // finishes that happen before this block runs are not
    // missed.
    // ======================================================
    initial begin : completion_coordinator
        wait (channel_done[0] && channel_done[1]);
        $display("[COORDINATOR] Both channels completed at %0t",
                 $time);
        -> all_dma_done;
    end

    // ======================================================
    // 9. GLOBAL COMPLETION LISTENER
    // Sets a persistent flag when the global event fires.
    // The flag is what the watchdog waits on.
    // ======================================================
    initial begin : completion_listener
        listener_ready_flag = 1'b1;
        @all_dma_done;
        completion_seen = 1'b1;
        $display("[EVENT] All DMA channels completed at %0t",
                 $time);
    end

    // ======================================================
    // 10. TIMEOUT WATCHDOG
    // Races: completion vs timeout. First one wins.
    // Loser is disabled by the named block.
    // ======================================================
    task automatic dma_watchdog(input time timeout_limit);
        fork : watchdog_process
            // Completion path
            begin
                wait (completion_seen == 1'b1);
                $display("[WATCHDOG] Completion detected at %0t",
                         $time);
            end

            // Timeout path
            begin
                #timeout_limit;
                timeout_flag = 1'b1;
                $display("[WATCHDOG] TIMEOUT at %0t", $time);
            end
        join_any

        // Kill the loser
        disable watchdog_process;
    endtask

    // ======================================================
    // 11. MAIN TEST CONTROLLER
    // ======================================================
    initial begin : main_test

        // ------------------------------------------------
        // Initialize resources
        // ------------------------------------------------
        shared_mem_lock = new(1);
        foreach (channel_mbx[i]) begin
            channel_mbx[i]   = new();   // unbounded mailbox
            channel_done[i]  = 0;
            processed_count[i] = 0;
        end
        completion_seen = 0;
        timeout_flag    = 0;

        $display("====================================");
        $display(" DMA TWO-CHANNEL CAPSTONE STARTED");
        $display("====================================");

        // ------------------------------------------------
        // Wait for listener readiness (fragile but correct:
        // the listener initial block sets this flag at t=0)
        // ------------------------------------------------
        wait (listener_ready_flag == 1'b1);

        // ------------------------------------------------
        // Wait for reset release
        // ------------------------------------------------
        wait (intf.rst_n === 1'b1);

        // ------------------------------------------------
        // Launch all four concurrent processes
        // (generators + consumers, both channels)
        // join_none so main_test continues to the watchdog.
        // ------------------------------------------------
        fork
            dma_generator(0, NUM_TRANSACTIONS);
            dma_consumer (0, NUM_TRANSACTIONS);
            dma_generator(1, NUM_TRANSACTIONS);
            dma_consumer (1, NUM_TRANSACTIONS);
        join_none

        // ------------------------------------------------
        // Run the watchdog (blocks until completion or
        // timeout — whichever comes first)
        // ------------------------------------------------
        dma_watchdog(TIMEOUT_LIMIT);

        // ------------------------------------------------
        // Check the result
        // ------------------------------------------------
        if (timeout_flag) begin
            $fatal(1, "DMA CAPSTONE FAILED: TIMEOUT");
        end
        if (processed_count[0] != NUM_TRANSACTIONS ||
            processed_count[1] != NUM_TRANSACTIONS) begin
            $fatal(1, "DMA CAPSTONE FAILED: COUNT MISMATCH");
        end

        $display("------------------------------------");
        $display(" Channel 0 processed = %0d", processed_count[0]);
        $display(" Channel 1 processed = %0d", processed_count[1]);
        $display("------------------------------------");
        $display("DMA CAPSTONE PASSED at %0t", $time);

        // ------------------------------------------------
        // Wait for all background workers to finish,
        // then end simulation (Day 015 lesson: join_none
        // requires wait fork before $finish).
        // ------------------------------------------------
        wait fork;
        $finish;
    end

endmodule : dma_capstone_tb
