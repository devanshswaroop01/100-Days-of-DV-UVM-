// ============================================================
// Day 006: Queues — Core Methods and FIFO Encapsulation
// File: day006_queue_basic_tb.sv
// Purpose: First show the 5 queue methods bare, then re-wrap
//          them as fifo_write / fifo_read tasks — the jump
//          from "container" to "driver model".
// ============================================================

`timescale 1ns/1ps

module day006_queue_basic_tb;

    // ----------------------------------------------------------
    // DECLARATION
    //   int q[$];
    //   ^value ^[$] = variable-size queue
    // Starts empty (size 0). No `new[]` needed.
    // ----------------------------------------------------------
    int q[$];
    int value;     // scratch for pop returns

    // ----------------------------------------------------------
    // FIFO WRAPPERS
    // - `automatic`: each call gets its own locals (thread-safe)
    // - `output`: return value via argument, not a global
    // - Both tasks guard against underflow on read
    // ----------------------------------------------------------
    task automatic fifo_write(input int data);
        q.push_back(data);                         // O(1) append
        $display("WRITE: %0d | Size = %0d | Q = %p",
                 data, q.size(), q);
    endtask

    task automatic fifo_read(output int read_data);
        if (q.size() != 0) begin
            read_data = q.pop_front();             // O(1) remove
            $display("READ:  %0d | Size = %0d | Q = %p",
                     read_data, q.size(), q);
        end
        else begin
            read_data = 'x;                        // sentinel
            $display("ERROR: FIFO is EMPTY — read refused");
        end
    endtask

    initial begin
        // ------------------------------------------------------
        // SECTION A: raw methods — show the primitives
        // ------------------------------------------------------
        $display("===== RAW QUEUE METHODS =====");

        q.push_back(10);
        q.push_back(20);
        q.push_back(30);
        $display("After push_back:  Q = %p", q);

        q.push_front(5);
        $display("After push_front: Q = %p", q);

        value = q.pop_front();
        $display("Popped front = %0d | Q = %p", value, q);

        value = q.pop_back();
        $display("Popped back  = %0d | Q = %p", value, q);

        $display("Queue size = %0d", q.size());

        // ------------------------------------------------------
        // SECTION B: same operations, now via tasks
        // This is the abstraction a driver/scoreboard will use.
        // ------------------------------------------------------
        $display("\n===== FIFO WRAPPERS =====");
        q.delete();                                 // clear for clean demo

        fifo_write(100);
        fifo_write(200);
        fifo_write(300);

        fifo_read(value);    // 100 — FIFO order
        fifo_read(value);    // 200

        fifo_write(400);
        fifo_read(value);    // 300
        fifo_read(value);    // 400

        fifo_read(value);    // underflow — refused, value = 'x

        $finish;
    end

endmodule

// ============================================================
// Day 006: Queue Manipulation — insert, delete, index idioms
// File: day006_queue_manipulation_tb.sv
// Purpose: Mid-queue operations and the `$` index idioms.
//          (Size already covered in Part 1 — omitted here.)
// ============================================================

`timescale 1ns/1ps

module day006_queue_manipulation_tb;

    int q[$];

    initial begin
        // ------------------------------------------------------
        // ASSIGN from a literal (note: trailing semicolon!)
        // ------------------------------------------------------
        q = {10, 20, 30, 40, 50};
        $display("Initial queue = %p", q);

        // ------------------------------------------------------
        // INSERT at index 2 — shifts elements >= 2 right
        // O(N) — avoid in hot paths
        // ------------------------------------------------------
        q.insert(2, 99);
        $display("After insert(2,99) = %p", q);

        // ------------------------------------------------------
        // DELETE one element at index 3 (removes 30)
        // ------------------------------------------------------
        q.delete(3);
        $display("After delete(3) = %p", q);

        // ------------------------------------------------------
        // INDEX IDIOMS — the `$` special index
        //   q[0]   -> first element
        //   q[$]   -> last element
        //   q[$-1] -> second-to-last
        // ------------------------------------------------------
        $display("First element  = %0d", q[0]);
        $display("Last element   = %0d", q[$]);
        $display("Second last    = %0d", q[$-1]);

        // ------------------------------------------------------
        // TRAVERSE with foreach — idx auto-bounded
        // ------------------------------------------------------
        $display("Traversal:");
        foreach (q[i])
            $display("  q[%0d] = %0d", i, q[i]);

        // ------------------------------------------------------
        // DELETE ALL — no argument
        // ------------------------------------------------------
        q.delete();
        $display("Final queue size = %0d", q.size());

        $finish;
    end

endmodule 



// ============================================================
// Day 006: DMA Scoreboard using a Queue as Reference Model
// File: day006_dma_scoreboard_tb.sv
// Purpose: First full checker. Expected values are pushed into
//          a queue; actual DUT outputs are popped and compared.
//          This is the smallest possible UVM scoreboard.
// ============================================================

`timescale 1ns/1ps

module day006_dma_scoreboard_tb;

    // ----------------------------------------------------------
    // REFERENCE MODEL — a FIFO of expected values
    // ----------------------------------------------------------
    int expected_data[$];

    // ----------------------------------------------------------
    // DIAGNOSTIC COUNTERS
    // ----------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    // ----------------------------------------------------------
    // PRODUCER — called when a transaction enters the DUT
    // ----------------------------------------------------------
    task automatic add_expected(input int data);
        expected_data.push_back(data);
        $display("[MODEL] Expected added: %0d", data);
    endtask

    // ----------------------------------------------------------
    // CHECKER — called when the monitor captures a DUT output
    // Three failure modes handled:
    //   1. DUT emits output with no expectation -> unexpected
    //   2. DUT output != head of queue       -> mismatch
    //   3. (implicit) queue empty at end      -> missing output
    // ----------------------------------------------------------
    task automatic check_output(input int actual);
        int expected_val;                          // local (automatic)
        if (expected_data.size() == 0) begin
            $display("[ERROR] Unexpected DUT output: %0d (ref model empty)",
                     actual);
            fail_count++;
        end
        else begin
            expected_val = expected_data.pop_front();
            if (actual == expected_val) begin
                $display("[PASS] Expected=%0d | Actual=%0d",
                         expected_val, actual);
                pass_count++;
            end
            else begin
                $display("[FAIL] Mismatch! Expected=%0d | Actual=%0d",
                         expected_val, actual);
                fail_count++;
            end
        end
    endtask

    initial begin
        $display("===== DMA SCOREBOARD =====");

        // ------------------------------------------------------
        // 1. Populate reference model
        // ------------------------------------------------------
        add_expected(100);
        add_expected(200);
        add_expected(300);
        $display("-----------------------------------------------");

        // ------------------------------------------------------
        // 2. Stream DUT outputs (simulated monitor)
        //    - 100, 200 pass
        //    - 350 fails (expected 300)
        //    - 400 triggers "unexpected output" (queue now empty)
        // ------------------------------------------------------
        check_output(100);    // PASS
        check_output(200);    // PASS
        check_output(350);    // FAIL (mismatch)
        check_output(400);    // FAIL (unexpected)

        // ------------------------------------------------------
        // 3. Report
        // ------------------------------------------------------
        $display("-----------------------------------------------");
        $display("===== REPORT =====");
        $display("PASSES    = %0d", pass_count);
        $display("FAILURES  = %0d", fail_count);
        $display("LEFT IN Q = %0d", expected_data.size());
        $display("==================");
        $finish;
    end

endmodule

