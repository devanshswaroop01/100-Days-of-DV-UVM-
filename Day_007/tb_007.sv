// ============================================================
// Day 007: Locator Methods — find, find_index, first, last
// File: day007_locator_tb.sv
// Purpose: Exhaustively exercise all 6 locator methods using
//          one predicate (> 30) for side-by-side comparison.
// ============================================================

`timescale 1ns/1ps

module day007_locator_tb;

    // ----------------------------------------------------------
    // Source array — literal init with '{...}
    // Note the leading apostrophe: it's an assignment pattern,
    // not a concatenation. This is SV's array-literal syntax.
    // ----------------------------------------------------------
    int data[] = '{10, 20, 30, 40, 50, 60, 70};

    // Locator methods return QUEUES, always
    int result[$];
    int indexes[$];

    initial begin
        $display("===== LOCATOR METHODS =====");

        // ------------------------------------------------------
        // find() — all matching ELEMENTS as a queue
        // ------------------------------------------------------
        result = data.find() with (item > 30);
        $display("find()              = %p", result);   // 40,50,60,70

        // ------------------------------------------------------
        // find_index() — all matching INDEXES
        // ------------------------------------------------------
        indexes = data.find_index() with (item > 30);
        $display("find_index()        = %p", indexes);  // 3,4,5,6

        // ------------------------------------------------------
        // find_first() — first matching ELEMENT (queue of 1)
        // ------------------------------------------------------
        result = data.find_first() with (item > 30);
        $display("find_first()        = %p", result);   // {40}

        // ------------------------------------------------------
        // find_last() — last matching ELEMENT
        // ------------------------------------------------------
        result = data.find_last() with (item > 30);
        $display("find_last()         = %p", result);   // {70}

        // ------------------------------------------------------
        // find_first_index() — index of first match
        // ------------------------------------------------------
        indexes = data.find_first_index() with (item > 30);
        $display("find_first_index()  = %p", indexes);  // {3}

        // ------------------------------------------------------
        // find_last_index() — index of last match
        // ------------------------------------------------------
        indexes = data.find_last_index() with (item > 30);
        $display("find_last_index()   = %p", indexes);  // {6}

        $finish;
    end

endmodule

// ============================================================
// Day 007: Mutating Array Methods — sort, rsort, reverse, shuffle
// File: day007_sort_tb.sv
// Purpose: Demonstrate all four IN-PLACE methods, which change
//          the array itself (no return value to capture).
// ============================================================

`timescale 1ns/1ps

module day007_sort_tb;

    int data[] = '{50, 10, 40, 20, 30};

    initial begin
        $display("===== ARRAY MANIPULATION & SORTING =====");
        $display("Original array   = %p", data);

        // ------------------------------------------------------
        // sort() — ascending, IN PLACE
        // The original ordering is LOST — there is no undo.
        // ------------------------------------------------------
        data.sort();
        $display("Ascending sort   = %p", data);   // 10,20,30,40,50

        // ------------------------------------------------------
        // rsort() — descending, IN PLACE
        // ------------------------------------------------------
        data.rsort();
        $display("Descending sort  = %p", data);   // 50,40,30,20,10

        // ------------------------------------------------------
        // reverse() — flip current order, IN PLACE
        // Note: after an rsort, reverse == sort.
        // ------------------------------------------------------
        data.reverse();
        $display("Reversed order   = %p", data);   // 10,20,30,40,50

        // ------------------------------------------------------
        // shuffle() — random permutation, IN PLACE
        // Not seeded here; output varies run-to-run.
        // For reproducibility: use $urandom with seed or
        // `+ntb_random_seed=...` on the simulator command line.
        // ------------------------------------------------------
        data.shuffle();
        $display("Shuffled array   = %p", data);

        $finish;
    end

endmodule

// ============================================================
// Day 007: DMA Latency Analysis — every method in one script
// File: day007_dma_analysis_tb.sv
// Purpose: Realistic use case combining locators, reductions,
//          uniqueness, and sorting. Includes unique_index().
// ============================================================

`timescale 1ns/1ps

module day007_dma_analysis_tb;

    // ----------------------------------------------------------
    // Realistic DMA latency trace (in clock cycles)
    // Two 25s are present to demo unique().
    // ----------------------------------------------------------
    int latency[] = '{12, 25, 8, 19, 25, 14, 30, 5};

    // Locator / reduction outputs (queues)
    int high_latency[$];
    int high_indexes[$];
    int minimum[$];
    int maximum[$];
    int unique_latency[$];
    int unique_idx[$];

    // Scalar aggregation
    int  total = 0;
    real average;

    initial begin
        $display("===== DMA LATENCY ANALYSIS =====");
        $display("Original: %p", latency);

        // ------------------------------------------------------
        // 1. LOCATOR — all transactions over threshold
        // ------------------------------------------------------
        high_latency = latency.find() with (item > 15);
        $display("Latency > 15          = %p", high_latency);

        // ------------------------------------------------------
        // 2. LOCATOR — their positions in the original array
        // ------------------------------------------------------
        high_indexes = latency.find_index() with (item > 15);
        $display("Their indexes         = %p", high_indexes);

        // ------------------------------------------------------
        // 3. REDUCTION — min / max return QUEUES (of size 1)
        // Index [0] to extract the scalar.
        // ------------------------------------------------------
        minimum = latency.min();
        maximum = latency.max();
        $display("Min latency           = %0d", minimum[0]);
        $display("Max latency           = %0d", maximum[0]);

        // ------------------------------------------------------
        // 4. UNIQUE — first occurrence of each distinct value
        // unique_index() gives the same info as indexes.
        // Order of results is NOT guaranteed by the LRM.
        // ------------------------------------------------------
        unique_latency = latency.unique();
        unique_idx     = latency.unique_index();
        $display("Unique values         = %p", unique_latency);
        $display("Unique first-indexes  = %p", unique_idx);

        // ------------------------------------------------------
        // 5. SORT — IN PLACE
        // WARNING: this destroys the original ordering. Any
        // locator queries that depended on position must run
        // BEFORE this line. (We already did — good.)
        // ------------------------------------------------------
        latency.sort();
        $display("Sorted (ascending)    = %p", latency);

        // ------------------------------------------------------
        // 6. SUM & AVERAGE
        // Note the real'() cast: total is int, size is int, so
        // total/size would truncate. Cast one operand to real.
        // ------------------------------------------------------
        foreach (latency[i]) total += latency[i];

        if (latency.size() > 0) begin
            average = real'(total) / latency.size();
            $display("Total latency         = %0d cycles", total);
            $display("Average latency       = %0.2f cycles", average);
        end
        else begin
            $display("Average latency       = 0.00 cycles (empty)");
        end

        $finish;
    end

endmodule



 
