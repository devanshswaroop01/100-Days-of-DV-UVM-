// ============================================================
// Day 005: Associative Arrays — Core API (integer keys)
// File: day005_assoc_integer_tb.sv
// Purpose: Insert on-the-fly, count, look up, existence-check,
//          delete one entry, delete all.
// ============================================================

`timescale 1ns/1ps

module day005_assoc_integer_tb;

    // ----------------------------------------------------------
    // DECLARATION
    //   int memory [int];
    //   ^value       ^key type
    // No `new[]` — associative arrays auto-allocate per key.
    // ----------------------------------------------------------
    int memory [int];

    initial begin
        $display("===== ASSOCIATIVE ARRAY (int keys) =====");

        // ------------------------------------------------------
        // INSERT — each write creates the key if absent
        // Keys deliberately sparse: 10, 50, 100, 1000
        // ------------------------------------------------------
        memory[10]   = 100;
        memory[50]   = 500;
        memory[100]  = 1000;
        memory[1000] = 5000;

        // ------------------------------------------------------
        // COUNT — .num() returns live element count (4 here)
        // ------------------------------------------------------
        $display("Total entries = %0d", memory.num());

        // ------------------------------------------------------
        // LOOKUP — direct index; returns 0 if key missing
        // (silent — the classic trap; use .exists() first)
        // ------------------------------------------------------
        $display("memory[10] = %0d", memory[10]);
        $display("memory[50] = %0d", memory[50]);

        // ------------------------------------------------------
        // EXISTENCE — .exists(k) -> 1/0, O(1)
        // ------------------------------------------------------
        if (memory.exists(100))
            $display("Key 100 exists");
        if (!memory.exists(200))
            $display("Key 200 does not exist");

        // ------------------------------------------------------
        // DELETE ONE — .delete(k) removes just that key
        // ------------------------------------------------------
        memory.delete(50);
        $display("After deletion = %0d entries", memory.num());

        // ------------------------------------------------------
        // DELETE ALL — .delete() with no argument wipes everything
        // ------------------------------------------------------
        memory.delete();
        $display("After delete-all = %0d entries", memory.num());

        $finish;
    end
 
endmodule 

// ============================================================
// Day 005: Associative Arrays — String keys + traversal
// File: day005_assoc_string_tb.sv
// Purpose: String-keyed map; iterate with foreach (preferred)
//          and with first/next/last (when manual control needed).
// ============================================================

`timescale 1ns/1ps

module day005_assoc_string_tb;

    // String key -> int value
    int student_marks [string];

    // Iterator variable for first/next/last traversal
    string name;

    initial begin
        $display("===== ASSOCIATIVE ARRAY (string keys) =====");

        // ------------------------------------------------------
        // INSERT — sparse map, order of writes does NOT matter
        // ------------------------------------------------------
        student_marks["Rahul"] = 85;
        student_marks["Aman"]  = 92;
        student_marks["Ravi"]  = 78;
        student_marks["Neha"]  = 95;

        // ------------------------------------------------------
        // DIRECT LOOKUP
        // ------------------------------------------------------
        $display("Rahul's Marks = %0d", student_marks["Rahul"]);
        $display("Neha's Marks  = %0d", student_marks["Neha"]);

        // ------------------------------------------------------
        // EXISTENCE CHECK
        // ------------------------------------------------------
        if (student_marks.exists("Aman"))
            $display("Record for 'Aman' exists.");

        $display("Total students registered = %0d", student_marks.num());

        // ------------------------------------------------------
        // TRAVERSAL #1 — foreach (PREFERRED)
        // - Auto-iterates every live key
        // - s_name is declared implicitly with the key's type
        // - ORDER IS NOT GUARANTEED by the LRM. Most simulators
        //   sort string keys alphabetically, but do NOT rely on
        //   it for portable code — use first/next for that.
        // ------------------------------------------------------
        $display("\n--- Roster (foreach) ---");
        foreach (student_marks[s_name]) begin
            $display("Student: %-6s | Marks: %0d",
                     s_name, student_marks[s_name]);
        end

        // ------------------------------------------------------
        // TRAVERSAL #2 — manual first/next (USE ONLY WHEN NEEDED)
        // Required when you must:
        //   * inspect/stop on a specific key (early exit)
        //   * call prev() to walk backwards
        //   * rely on a defined iteration order (first/next is
        //     typically sorted for int/string keys, but still
        //     simulator-dependent)
        // NOTE: must use do-while, because first() already seeds
        // a valid key before the loop.
        // ------------------------------------------------------
        $display("\n--- Roster (first/next) ---");
        if (student_marks.first(name)) begin
            do begin
                $display("Student: %-6s | Marks: %0d",
                         name, student_marks[name]);
            end while (student_marks.next(name));
        end

        // ------------------------------------------------------
        // last() — jump straight to the final key in the order
        // ------------------------------------------------------
        if (student_marks.last(name))
            $display("\nLast key = %s", name);

        // ------------------------------------------------------
        // DELETE a single entry, then confirm the new count
        // ------------------------------------------------------
        $display("\nDeleting 'Ravi' from database...");
        student_marks.delete("Ravi");
        $display("Total students after deletion = %0d",
                 student_marks.num());

        $finish;
    end

endmodule 

// ============================================================
// Day 005: 2-D Associative Array — Scoreboard Sketch
// File: day005_dma_scoreboard_tb.sv
// Purpose: Model a per-channel scoreboard keyed by transaction
//          ID. This is the exact shape used in UVM scoreboards.
// ============================================================

`timescale 1ns/1ps

module day005_dma_scoreboard_tb;

    // ----------------------------------------------------------
    // DECLARATION: expected_data[channel][txn_id] = data
    // Two unpacked associative dimensions = nested maps.
    // Reading expected_data[ch] yields an inner associative
    // array; methods like .num(), .exists(), .delete() can be
    // called on that inner array.
    // ----------------------------------------------------------
    int expected_data [int][int];

    initial begin
        $display("===== DMA SCOREBOARD =====");

        // ------------------------------------------------------
        // INSERT — channel 0 gets two transactions, channel 1
        // gets two, channel 2 gets one.
        // ------------------------------------------------------
        expected_data[0][101] = 1000;
        expected_data[0][102] = 2000;
        expected_data[1][201] = 3000;
        expected_data[1][202] = 4000;
        expected_data[2][301] = 5000;

        // ------------------------------------------------------
        // PER-CHANNEL COUNT — inner-array method
        // ------------------------------------------------------
        $display("Channel 0 entries = %0d", expected_data[0].num());
        $display("Channel 1 entries = %0d", expected_data[1].num());
        $display("Channel 2 entries = %0d", expected_data[2].num());

        // ------------------------------------------------------
        // LOOKUP + EXISTENCE — per-channel again
        // ------------------------------------------------------
        if (expected_data[0].exists(101)) begin
            $display("Transaction 101 found on channel 0");
            $display("Expected data = %0d", expected_data[0][101]);
        end

        // ------------------------------------------------------
        // DELETE on match — remove a completed transaction so
        // the map only holds OUTSTANDING work.
        // ------------------------------------------------------
        expected_data[0].delete(101);
        $display("Remaining channel 0 entries = %0d",
                 expected_data[0].num());

        // ------------------------------------------------------
        // BONUS — full sweep across all outstanding entries
        // This is the "check every still-pending txn" loop.
        // ------------------------------------------------------
        $display("\nOutstanding transactions:");
        foreach (expected_data[ch]) begin
            foreach (expected_data[ch][id]) begin
                $display("  ch=%0d id=%0d data=%0d",
                         ch, id, expected_data[ch][id]);
            end
        end

        $finish;
    end

endmodule 
