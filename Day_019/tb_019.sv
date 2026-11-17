// ============================================================
// Day 019: Basic event — one trigger, many waiters
// File: day019_basic_event.sv
// Purpose: The minimum viable event demo. Proves that a single
//          event trigger wakes ALL waiters, not just one.
// ============================================================

`timescale 1ns/1ps

module day019_basic_event;

    task automatic run_exercise_1();

        event basic_ev;

        $display("\n[EX1] --- Basic event, multiple waiters ---");

        fork
            // --------------------------------------------------
            // TRIGGER — fires at t=20
            // --------------------------------------------------
            begin
                #20;
                $display("[%0t] [TRIGGER] -> basic_ev", $time);
                -> basic_ev;
            end

            // --------------------------------------------------
            // WAITER 1 — arrives at t=0, waits for trigger
            // --------------------------------------------------
            begin
                $display("[%0t]   [W1] @basic_ev", $time);
                @basic_ev;
                $display("[%0t]   [W1] woke up", $time);
            end

            // --------------------------------------------------
            // WAITER 2A — same, concurrent with W1
            // --------------------------------------------------
            begin
                $display("[%0t]   [W2A] @basic_ev", $time);
                @basic_ev;
                $display("[%0t]   [W2A] woke up", $time);
            end

            // --------------------------------------------------
            // WAITER 2B — same, concurrent
            // --------------------------------------------------
            begin
                $display("[%0t]   [W2B] @basic_ev", $time);
                @basic_ev;
                $display("[%0t]   [W2B] woke up", $time);
            end
        join
    endtask

    initial begin
        run_exercise_1();
        $finish;
    end

endmodule 

// ============================================================
// Day 019: The missed-event trap
// File: day019_missed_event.sv
// Purpose: Prove that an event triggered with no waiter is LOST
//          FOREVER. The waiter will block indefinitely.
//
// Restructured from EX3: the file commented out the blocking
// @raw_ev to avoid hanging the simulation. This version uses
// fork...join_any with a timeout so the hang is visible
// WITHOUT freezing the sim. The student sees the hang actually
// happen, with a clean exit path.
// ============================================================

`timescale 1ns/1ps

module day019_missed_event;

    task automatic run_exercise_3();

        event raw_ev;

        $display("\n[EX3] --- Missed event hazard (with timeout) ---");

        // ------------------------------------------------------
        // STEP 1: trigger the event with NO waiter present
        // This is the classic bug setup.
        // ------------------------------------------------------
        -> raw_ev;
        $display("[%0t] Triggered raw_ev (no waiters present)",
                 $time);

        // ------------------------------------------------------
        // STEP 2: waiter arrives 10ns later
        // In the file's version, this would block forever.
        // Here, we wrap it in a race with a 50ns timeout so the
        // demonstration completes cleanly.
        // ------------------------------------------------------
        fork : waiter_or_timeout
            // The naive waiter — will block forever
            begin
                $display("[%0t]   Waiter @raw_ev (will block)",
                         $time);
                @raw_ev;   // MISSED — the trigger is GONE
                $display("[%0t]   Waiter woke up (impossible)", $time);
            end

            // Timeout — the "proof" that the waiter is stuck
            begin
                #50;
                $display("[%0t] TIMEOUT: waiter never woke up — event lost",
                         $time);
            end
        join_any

        // Kill the still-blocked waiter so the task can return
        disable waiter_or_timeout;

        $display("[%0t] Demo cleanly resolved.\n", $time);
    endtask

    initial begin
        run_exercise_3();
        $finish;
    end

endmodule

// ============================================================
// Day 019: The persistent-flag pattern — fixing the missed event
// File: day019_persistent_flag.sv
// Purpose: The canonical solution to the missed-event bug.
//          Combine an event with a persistent flag:
//            wait (flag || ev.triggered);
//          - flag covers "arrived late"
//          - .triggered covers "arrived in the same step"
//
// Merged from EX4 (raw_ev + persistent_flag) and EX5 (DMA
// worker + monitor). The DMA framing is used as the final
// integration example.
// ============================================================

`timescale 1ns/1ps

module day019_persistent_flag;

    task automatic run_exercise_4();

        event raw_ev;
        bit   persistent_flag = 0;

        $display("\n[EX4] --- Persistent flag + .triggered ---");

        // ------------------------------------------------------
        // SCENARIO 1: waiter arrives in the SAME time step as
        // the trigger. `wait(ev.triggered)` catches it.
        // ------------------------------------------------------
        $display("\n  [Scenario 1] Same-step waiter via .triggered:");

        fork
            // Trigger
            begin
                #5;
                $display("[%0t]   [TRIGGER] setting flag + triggering",
                         $time);
                persistent_flag = 1;
                -> raw_ev;
                #0;   // end of current time slot
                $display("[%0t]   [TRIGGER] end of time slot", $time);
            end

            // Same-step waiter — arrives at exact same time
            begin
                #5;
                $display("[%0t]   [W] checking .triggered", $time);
                wait (raw_ev.triggered);   // catches same-step
                $display("[%0t]   [W] caught via .triggered", $time);
            end
        join

        // ------------------------------------------------------
        // SCENARIO 2: waiter arrives LATE (well after trigger)
        // .triggered is now false, but persistent_flag is 1.
        // ------------------------------------------------------
        $display("\n  [Scenario 2] Late waiter via persistent flag:");

        fork
            // Trigger (fires at t=15, once flag already set)
            begin
                #10;
                $display("[%0t]   [TRIGGER] re-triggering (already set)",
                         $time);
                persistent_flag = 1;
                -> raw_ev;
            end

            // Late waiter — arrives 5ns after the trigger
            begin
                #15;
                $display("[%0t]   [W] arriving late, checking state",
                         $time);

                if (raw_ev.triggered) begin
                    $display("[ERROR] .triggered persisted past its slot!");
                end
                else begin
                    $display("[%0t]   [W] .triggered is false, trying flag",
                             $time);
                    wait (persistent_flag == 1'b1);
                    $display("[%0t]   [W] caught via persistent flag", $time);
                end
            end
        join

        // ------------------------------------------------------
        // INTEGRATION: DMA worker + monitor
        // EX5 uses the SAME pattern with DMA vocabulary.
        // Shown here as the canonical "real use" example.
        // ------------------------------------------------------
        $display("\n  [Integration] DMA worker with persistent flag:");

        begin
            event dma_done;
            bit   dma_complete_flag = 0;

            fork
                // DMA worker
                begin
                    $display("[%0t]   [DMA] starting transfer", $time);
                    #45;
                    dma_complete_flag = 1;
                    -> dma_done;
                    $display("[%0t]   [DMA] complete, flag set, event fired",
                             $time);
                end

                // Monitor — catches both "early" and "late" arrival
                begin
                    $display("[%0t]   [TEST] waiting for DMA", $time);
                    wait (dma_complete_flag || dma_done.triggered);
                    $display("[%0t]   [TEST] caught DMA completion",
                             $time);
                end
            join
        end
    endtask

    initial begin
        run_exercise_4();
        $finish;
    end

endmodule

// ============================================================
// Day 019: APB bus handshake notification
// File: day019_apb_event.sv
// Purpose: Event as a bus transaction broadcast. The bus
//          monitor detects a completed handshake and fires the
//          event; the scoreboard wakes up and processes it.
//
// This is the shape of an interrupt handler in real UVM.
// ============================================================

`timescale 1ns/1ps

module day019_apb_event;

    // ----------------------------------------------------------
    // Clock and bus signals
    // ----------------------------------------------------------
    logic pclk = 0;
    always #5 pclk = ~pclk;

    logic psel    = 0;
    logic penable = 0;
    logic pready  = 0;
    logic pwrite  = 0;

    task automatic run_exercise_6();

        event apb_transfer_complete;

        $display("\n[EX6] --- APB bus transfer notification ---");

        fork
            // --------------------------------------------------
            // MASTER — drives a SETUP -> ACCESS -> IDLE cycle
            // --------------------------------------------------
            begin : master
                @(posedge pclk);
                psel   <= 1'b1;
                pwrite <= 1'b1;
                $display("[%0t] MASTER: SETUP", $time);

                @(posedge pclk);
                penable <= 1'b1;
                pready  <= 1'b1;
                $display("[%0t] MASTER: ACCESS", $time);

                @(posedge pclk);
                psel    <= 1'b0;
                penable <= 1'b0;
                pready  <= 1'b0;
                $display("[%0t] MASTER: IDLE", $time);
            end

            // --------------------------------------------------
            // MONITOR — detects the handshake, fires the event
            // --------------------------------------------------
            begin : monitor
                forever begin
                    @(posedge pclk);
                    if (psel && penable && pready) begin
                        $display("[%0t]   MONITOR: handshake, firing event",
                                 $time);
                        -> apb_transfer_complete;
                        break;
                    end
                end
            end

            // --------------------------------------------------
            // SCOREBOARD — waits for the event
            // --------------------------------------------------
            begin : scoreboard
                $display("[%0t] SCOREBOARD: waiting", $time);
                @apb_transfer_complete;
                $display("[%0t] SCOREBOARD: caught, updating metrics",
                         $time);
            end
        join
    endtask

    initial begin
        run_exercise_6();
        $finish;
    end

endmodule  

// ============================================================
// Day 019: Event + mailbox — the "wake up and check" pattern
// File: day019_event_mailbox.sv
// Purpose: An event is often paired with a mailbox: the event
//          says "data is ready", the mailbox delivers the data.
//          This is the shape of UVM TLM ready/valid signaling.
// ============================================================

`timescale 1ns/1ps

class apb_transaction;
    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand bit        write;

    function void display(string prefix = "APB_TX");
        $display("[%s] Addr=0x%0h Data=0x%0h Op=%s",
                 prefix, addr, data, write ? "WRITE" : "READ");
    endfunction
endclass : apb_transaction


module day019_event_mailbox;

    task automatic run_exercise_7();

        mailbox #(apb_transaction) comm_mb = new();
        event                      data_pushed_ev;

        $display("\n[EX7] --- Event + mailbox integration ---");

        fork
            // --------------------------------------------------
            // PRODUCER — puts data, then fires event
            // --------------------------------------------------
            begin : producer
                apb_transaction tx = new();
                void'(tx.randomize());
                tx.addr = 32'h4000_DEAD;

                #15;
                comm_mb.put(tx);         // data goes into mailbox first
                -> data_pushed_ev;        // then the event notifies
                tx.display("PRODUCER_PUSH");
            end

            // --------------------------------------------------
            // CONSUMER — waits for event, then reads mailbox
            // --------------------------------------------------
            begin : consumer
                apb_transaction rx;
                $display("[%0t] CONSUMER: waiting for event", $time);
                @data_pushed_ev;

                // Now that we know data is ready, try_get it.
                // Using try_get (not get) because we already
                // know the data is present — no need to block.
                if (comm_mb.try_get(rx) > 0)
                    rx.display("CONSUMER_POP");
                else
                    $display("[ERROR] Event fired but mailbox empty!");
            end
        join
    endtask

    initial begin
        run_exercise_7();
        $finish;
    end

endmodule  
