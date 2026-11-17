// ============================================================
// Day 018: Basic mailbox producer/consumer
// File: day018_basic_mailbox.sv
// Purpose: Unbounded mailbox, two threads at different rates.
//          Producer never blocks; consumer occasionally starves.
// ============================================================

`timescale 1ns/1ps

module day018_basic_mailbox;

    task automatic run_exercise_1();

        // ------------------------------------------------------
        // UNBOUNDED mailbox — new() with no arg
        // Producer can put infinitely; never blocks.
        // Consumer blocks when empty (initially).
        // ------------------------------------------------------
        mailbox raw_mb = new();

        $display("\n[EX1] --- Unbounded producer/consumer ---");

        fork
            // --------------------------------------------------
            // PRODUCER — puts 5 items, 5ns apart
            // --------------------------------------------------
            begin : producer
                for (int i = 1; i <= 5; i++) begin
                    #5;
                    $display("[%0t] [PROD] put item=%0d", $time, i * 10);
                    raw_mb.put(i * 10);    // never blocks (unbounded)
                end
            end

            // --------------------------------------------------
            // CONSUMER — gets 5 items, 12ns apart
            // At t=0 mailbox is empty -> consumer blocks
            // At t=5 first put -> consumer wakes
            // Consumer is slower than producer, so it lags
            // --------------------------------------------------
            begin : consumer
                int rx_data;
                for (int j = 1; j <= 5; j++) begin
                    #12;
                    raw_mb.get(rx_data);   // blocks when empty
                    $display("[%0t]   [CONS] got item=%0d (FIFO)",
                             $time, rx_data);
                end
            end
        join
    endtask

    initial begin
        run_exercise_1();
        $finish;
    end

endmodule

// ============================================================
// Day 018: Bounded mailbox = backpressure
// File: day018_backpressure.sv
// Purpose: new(2) means producer blocks when 2 items are queued.
//          Shows the canonical fast-producer/slow-consumer stall.
//
// Merged from EX2 (new(3), fill-and-drain) and EX7
// (new(2), fast producer + slow consumer). The EX7 shape is
// kept because it makes the "producer blocked" state visible
// via num() printing.
// ============================================================

`timescale 1ns/1ps

module day018_backpressure;

    task automatic run_exercise_2();

        // ------------------------------------------------------
        // BOUNDED mailbox — new(2) means at most 2 queued items
        // ------------------------------------------------------
        mailbox #(int) pipeline_mb = new(2);

        $display("\n[EX2] --- Bounded mailbox (capacity=2) backpressure ---");

        fork
            // --------------------------------------------------
            // FAST PRODUCER — 5 items, 5ns apart
            // Will block once num() reaches 2
            // --------------------------------------------------
            begin : fast_producer
                for (int i = 1; i <= 5; i++) begin
                    $display("[%0t] [PROD] pre-put num=%0d",
                             $time, pipeline_mb.num());
                    pipeline_mb.put(i * 100);   // BLOCKS when full
                    $display("[%0t] [PROD] put #%0d ok, num=%0d",
                             $time, i, pipeline_mb.num());
                    #5;
                end
            end

            // --------------------------------------------------
            // SLOW CONSUMER — 5 items, 25ns apart
            // Slowly drains, letting producer unblock
            // --------------------------------------------------
            begin : slow_consumer
                int rx;
                for (int j = 1; j <= 5; j++) begin
                    #25;
                    pipeline_mb.get(rx);
                    $display("[%0t]   [CONS] got %0d, num=%0d",
                             $time, rx, pipeline_mb.num());
                end
            end
        join
    endtask

    initial begin
        run_exercise_2();
        $finish;
    end

endmodule

// ============================================================
// Day 018: try_put / try_get — non-blocking mailbox
// File: day018_try.sv
// Purpose: try_* return 1 if operation succeeded, 0 if not.
//          Never block — safe to use for polling.
// ============================================================

`timescale 1ns/1ps

module day018_try;

    task automatic run_exercise_3();

        mailbox #(int) test_mb = new(1);   // tiny, easy to saturate
        int data_out;

        $display("\n[EX3] --- try_put / try_get ---");

        // ------------------------------------------------------
        // Step A: try_get on empty -> returns 0 (no data)
        // ------------------------------------------------------
        if (test_mb.try_get(data_out) == 0)
            $display("[%0t]   try_get on empty -> 0 (expected)",
                     $time);
        else
            $display("[%0t]   ERROR: try_get returned 1 on empty!",
                     $time);

        // ------------------------------------------------------
        // Step B: put one item — mailbox now full (capacity=1)
        // ------------------------------------------------------
        test_mb.put(99);
        $display("[%0t]   put(99), num=%0d", $time, test_mb.num());

        // ------------------------------------------------------
        // Step C: try_put on full -> returns 0 (no space)
        // ------------------------------------------------------
        if (test_mb.try_put(88) == 0)
            $display("[%0t]   try_put on full -> 0 (expected)",
                     $time);
        else
            $display("[%0t]   ERROR: try_put returned 1 on full!",
                     $time);

        // ------------------------------------------------------
        // Step D: drain
        // ------------------------------------------------------
        void'(test_mb.try_get(data_out));
        $display("[%0t]   try_get -> %0d, num=%0d",
                 $time, data_out, test_mb.num());
    endtask

    initial begin
        run_exercise_3();
        $finish;
    end

endmodule 

// ============================================================
// Day 018: peek vs get
// File: day018_peek.sv
// Purpose: peek reads without removing; get reads and removes.
//          num() is the proof.
// ============================================================

`timescale 1ns/1ps

module day018_peek;

    task automatic run_exercise_4();

        mailbox #(int) peek_mb = new();
        int peek_val, get_val;

        $display("\n[EX4] --- peek vs get ---");

        // Load 3 items
        peek_mb.put(101);
        peek_mb.put(202);
        peek_mb.put(303);
        $display("[%0t] Loaded 3 items, num=%0d",
                 $time, peek_mb.num());

        // ------------------------------------------------------
        // peek — read the front WITHOUT removing
        // num() unchanged after
        // ------------------------------------------------------
        peek_mb.peek(peek_val);
        $display("[%0t]   peek()  -> %0d, num=%0d (unchanged)",
                 $time, peek_val, peek_mb.num());

        // Peek again — same item
        peek_mb.peek(peek_val);
        $display("[%0t]   peek()  -> %0d (same front item)",
                 $time, peek_val);

        // ------------------------------------------------------
        // get — read the front AND remove
        // num() decreases
        // ------------------------------------------------------
        peek_mb.get(get_val);
        $display("[%0t]   get()   -> %0d, num=%0d (decreased)",
                 $time, get_val, peek_mb.num());

        // ------------------------------------------------------
        // get again — now the NEXT item is on top
        // ------------------------------------------------------
        peek_mb.get(get_val);
        $display("[%0t]   get()   -> %0d, num=%0d (decreased again)",
                 $time, get_val, peek_mb.num());
    endtask

    initial begin
        run_exercise_4();
        $finish;
    end

endmodule  

// ============================================================
// Day 018: Typed mailbox #(dma_transaction)
// File: day018_typed_mb.sv
// Purpose: Strong-typed mailbox — the compiler enforces that
//          only dma_transaction handles pass through.
//          This is the UVM TLM pattern.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// Transaction class — the payload type
// ------------------------------------------------------------
class dma_transaction;
    rand bit [31:0] src_addr;
    rand bit [31:0] dst_addr;
    rand bit [15:0] transfer_len;
    int             channel_id;

    constraint c_align {
        src_addr[1:0] == 2'b00;     // 4-byte aligned
        dst_addr[1:0] == 2'b00;
        transfer_len  > 0;
        transfer_len  <= 1024;
    }

    function void display(string prefix = "DMA_TX");
        $display("[%s] Ch:%0d Src:0x%0h Dst:0x%0h Len:%0d",
                 prefix, channel_id,
                 src_addr, dst_addr, transfer_len);
    endfunction
endclass : dma_transaction


module day018_typed_mb;

    task automatic run_exercise_5();

        // ------------------------------------------------------
        // TYPED mailbox — only dma_transaction handles allowed
        // Compile error if you try to put an int or a string.
        // ------------------------------------------------------
        mailbox #(dma_transaction) typed_mb = new();

        $display("\n[EX5] --- Typed mailbox ---");

        fork
            // --------------------------------------------------
            // PRODUCER — randomize & put 5 transactions
            // --------------------------------------------------
            begin : producer
                for (int i = 0; i < 5; i++) begin
                    dma_transaction tx = new();
                    void'(tx.randomize());
                    tx.channel_id = 0;
                    #5;
                    typed_mb.put(tx);
                    tx.display("PROD");
                end
            end

            // --------------------------------------------------
            // CONSUMER — get 5, 8ns apart
            // --------------------------------------------------
            begin : consumer
                dma_transaction rx;
                for (int j = 0; j < 5; j++) begin
                    typed_mb.get(rx);
                    #8;
                    rx.display("CONS");
                end
            end
        join
    endtask

    initial begin
        run_exercise_5();
        $finish;
    end

endmodule

// ============================================================
// Day 018: Multi-channel mailboxes — independent channels
// File: day018_multichannel.sv
// Purpose: Two completely independent producer/consumer pairs.
//          Channel 0 traffic cannot interfere with channel 1.
//          The channel_id check is a defensive assertion.
// ============================================================

`timescale 1ns/1ps

class dma_transaction;   // (assumes Part 5's class; re-declared for standalone)
    rand bit [31:0] src_addr, dst_addr;
    rand bit [15:0] transfer_len;
    int             channel_id;
    function void display(string prefix = "TX");
        $display("[%s] Ch:%0d Src:0x%0h Dst:0x%0h Len:%0d",
                 prefix, channel_id, src_addr, dst_addr, transfer_len);
    endfunction
endclass


module day018_multichannel;

    task automatic run_exercise_6();

        // ------------------------------------------------------
        // One mailbox per channel — NO sharing between them
        // ------------------------------------------------------
        mailbox #(dma_transaction) ch0_mb = new();
        mailbox #(dma_transaction) ch1_mb = new();

        $display("\n[EX6] --- Multi-channel independent mailboxes ---");

        // ------------------------------------------------------
        // Four threads: 2 producers + 2 consumers, fully parallel
        // ------------------------------------------------------
        fork
            generate_channel_traffic(0, ch0_mb);
            generate_channel_traffic(1, ch1_mb);
            consume_channel_traffic(0, ch0_mb);
            consume_channel_traffic(1, ch1_mb);
        join
    endtask

    // ----------------------------------------------------------
    // Producer: random delays, 3 transactions per channel
    // ----------------------------------------------------------
    task automatic generate_channel_traffic(
        input int                          ch_id,
        input mailbox #(dma_transaction)   mb
    );
        for (int i = 0; i < 3; i++) begin
            dma_transaction tx = new();
            void'(tx.randomize());
            tx.channel_id = ch_id;
            #($urandom_range(5, 15));
            mb.put(tx);
        end
    endtask

    // ----------------------------------------------------------
    // Consumer: 3 transactions per channel, with sanity check
    // ----------------------------------------------------------
    task automatic consume_channel_traffic(
        input int                          ch_id,
        input mailbox #(dma_transaction)   mb
    );
        dma_transaction rx;
        for (int i = 0; i < 3; i++) begin
            mb.get(rx);
            rx.display($sformatf("RCV_CH%0d", ch_id));

            // --------------------------------------------------
            // Defensive assertion: channel isolation must hold
            // If this fires, something is cross-contaminating
            // the mailboxes (a real bug).
            // --------------------------------------------------
            if (rx.channel_id != ch_id) begin
                $display("[ERROR] Cross-channel! Expected CH%0d, got CH%0d",
                         ch_id, rx.channel_id);
            end
        end
    endtask

    initial begin
        run_exercise_6();
        $finish;
    end

endmodule 

 
