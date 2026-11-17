// ============================================================
// Day 023: Polymorphism capstone — virtual methods + queue
// File: day023_dma_poly.sv
// Purpose: Base class with virtual `execute` + `display`.
//          Three subclasses override both. A queue of base
//          handles holds mixed subtypes. Polymorphic dispatch
//          calls the correct method per element.
//
// Merged from EX1 (DMA hierarchy) + EX4 (mixed queue).
// ============================================================

`timescale 1ns/1ps

// ============================================================
// BASE CLASS
// ============================================================
class dma_transaction;

    int unsigned id;
    int unsigned channel;
    bit [31:0]   address;

    function new(int unsigned i = 0, int unsigned ch = 0,
                 bit [31:0] addr = 0);
        id      = i;
        channel = ch;
        address = addr;
    endfunction

    // ------------------------------------------------------
    // VIRTUAL execute — the polymorphism hook
    // ------------------------------------------------------
    virtual function void execute();
        $display("Generic DMA transaction");
    endfunction

    virtual function void display();
        $display("ID      = %0d", id);
        $display("Channel = %0d", channel);
        $display("Address = 0x%0h", address);
    endfunction

endclass


// ============================================================
// SUBCLASS 1 — READ
// ============================================================
class dma_read_transaction extends dma_transaction;

    bit [31:0] read_data;

    function new(int unsigned i, int unsigned ch,
                 bit [31:0] addr, bit [31:0] data);
        super.new(i, ch, addr);
        read_data = data;
    endfunction

    virtual function void execute();
        $display("[READ] reading from address 0x%0h", address);
    endfunction

    virtual function void display();
        super.display();
        $display("Read Data = 0x%0h", read_data);
    endfunction

endclass


// ============================================================
// SUBCLASS 2 — WRITE
// (file had `virtual function vod execute` — typo, fixed here)
// ============================================================
class dma_write_transaction extends dma_transaction;

    bit [31:0] write_data;

    function new(int unsigned i, int unsigned ch,
                 bit [31:0] addr, bit [31:0] data);
        super.new(i, ch, addr);
        write_data = data;
    endfunction

    virtual function void execute();   // was `vod` in file
        $display("[WRITE] writing 0x%0h to address 0x%0h",
                 write_data, address);
    endfunction

    virtual function void display();
        super.display();
        $display("Write Data = 0x%0h", write_data);
    endfunction

endclass


// ============================================================
// SUBCLASS 3 — BURST
// ============================================================
class dma_burst_transaction extends dma_transaction;

    int unsigned burst_length;

    function new(int unsigned i, int unsigned ch,
                 bit [31:0] addr, int unsigned len);
        super.new(i, ch, addr);
        burst_length = len;
    endfunction

    virtual function void execute();
        $display("[BURST] burst length = %0d", burst_length);
    endfunction

    virtual function void display();
        super.display();
        $display("Burst Length = %0d", burst_length);
    endfunction

endclass


// ============================================================
// TESTBENCH — direct calls, polymorphic dispatch, queue
// ============================================================
module day023_dma_poly_tb;

    // Handles
    dma_transaction        tx;
    dma_read_transaction   read_tx;
    dma_write_transaction  write_tx;
    dma_burst_transaction  burst_tx;

    // Heterogeneous queue of base handles
    dma_transaction        exec_queue[$];

    initial begin

        // ------------------------------------------------------
        // 1. Direct instantiation + direct method calls
        // ------------------------------------------------------
        read_tx  = new(1, 0, 32'h1000, 32'hABCD);
        write_tx = new(2, 1, 32'h2000, 32'h1234);
        burst_tx = new(3, 2, 32'h3000, 8);

        // ------------------------------------------------------
        // 2. Polymorphic dispatch via base handle
        // ------------------------------------------------------
        $display("\n===== POLYMORPHIC DISPATCH =====");

        tx = read_tx;  tx.execute();  tx.display();
        tx = write_tx; tx.execute();  tx.display();
        tx = burst_tx; tx.execute();  tx.display();

        // ------------------------------------------------------
        // 3. Queue of mixed subtypes (from EX4)
        // push_back each derived object via its base type
        // ------------------------------------------------------
        $display("\n===== MIXED-TYPE QUEUE =====");

        exec_queue.push_back(read_tx);
        exec_queue.push_back(write_tx);
        exec_queue.push_back(burst_tx);

        foreach (exec_queue[i]) begin
            $write("Slot %0d -> ", i);
            exec_queue[i].execute();   // dynamic dispatch
        end

        // ------------------------------------------------------
        // 4. Downcast — recover a specific subtype from base handle
        // ------------------------------------------------------
        $display("\n===== DOWNCAST WITH $cast =====");
        tx = read_tx;   // base handle pointing to read object

        if ($cast(read_tx, tx)) begin
            $display("Recovered read transaction");
            $display("read_data = 0x%0h", read_tx.read_data);
        end
        else begin
            $display("Downcast failed (should not happen here)");
        end
    end

endmodule 

// ============================================================
// Day 023: Static vs dynamic binding — empirical proof
// File: day023_binding.sv
// Purpose: Run the SAME code with `virtual` on/off and observe
//          the different outputs. This proves that dynamic
//          binding depends on the `virtual` keyword.
//
// Usage: Uncomment exactly one of the two `define lines below
//        and re-run. Compare the printed result.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// CHOOSE ONE:
// ------------------------------------------------------------
`define USE_VIRTUAL
// `define USE_STATIC

// ------------------------------------------------------------
// BASE CLASS — conditionally virtual
// ------------------------------------------------------------
class base_tx;

    `ifdef USE_VIRTUAL
        virtual
    `endif
    function void display();
        $display("Executing: BASE transaction display method");
    endfunction

endclass


// ------------------------------------------------------------
// EXTENDED CLASS — same conditional
// ------------------------------------------------------------
class extended_tx extends base_tx;

    `ifdef USE_VIRTUAL
        virtual
    `endif
    function void display();
        $display("Executing: EXTENDED transaction display method");
    endfunction

endclass


// ------------------------------------------------------------
// TESTBENCH — upcast then call
// ------------------------------------------------------------
module day023_binding_tb;

    base_tx     b_handle;
    extended_tx ext_obj;

    initial begin

        // Report which mode is active (replaces UVM_STRINGIFY
        // from the file, which requires UVM imports)
        `ifdef USE_VIRTUAL
            $display("--- Mode: VIRTUAL (dynamic binding) ---");
        `else
            $display("--- Mode: STATIC  (compile-time binding) ---");
        `endif

        ext_obj = new();
        b_handle = ext_obj;   // upcast

        // --------------------------------------------------
        // The critical call:
        // - VIRTUAL mode: prints "EXTENDED" (dynamic dispatch)
        // - STATIC  mode: prints "BASE"     (compile-time from
        //                                     b_handle's type)
        // --------------------------------------------------
        b_handle.display();
    end

endmodule

// ============================================================
// Day 023: Upcast vs downcast, and the failed-cast guard
// File: day023_casting.sv
// Purpose: Demonstrate the three cast scenarios side by side:
//            1. Upcast          — always safe
//            2. Successful $cast — types match, returns 1
//            3. Failed $cast    — types differ, returns 0, dest
//                                 set to null
//
// Note: file used `uvm_info`/`uvm_error` — those require UVM
// imports. Replaced with $display/$error for standalone use.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// Package — for encapsulation
// ------------------------------------------------------------
package casting_pkg;

    class transaction;
        int id;
        function new(int id);
            this.id = id;
        endfunction
        virtual function void identify();
            $display("Type: BASE transaction, ID=%0d", id);
        endfunction
    endclass


    class dma_read_transaction extends transaction;
        bit [31:0] src_addr;
        function new(int id, bit [31:0] src);
            super.new(id);
            this.src_addr = src;
        endfunction
        virtual function void identify();
            $display("Type: DMA READ, ID=%0d, Src=0x%0h", id, src_addr);
        endfunction
    endclass


    class dma_write_transaction extends transaction;
        bit [31:0] dst_addr;
        function new(int id, bit [31:0] dst);
            super.new(id);
            this.dst_addr = dst;
        endfunction
        virtual function void identify();
            $display("Type: DMA WRITE, ID=%0d, Dst=0x%0h", id, dst_addr);
        endfunction
    endclass

endpackage : casting_pkg


// ============================================================
// TESTBENCH
// ============================================================
module day023_casting_tb;

    import casting_pkg::*;

    transaction           p_handle;
    dma_read_transaction  read_obj,  recovered_read;
    dma_write_transaction write_obj, recovered_write;

    initial begin

        $display("\n=== CASTING DEMO ===");

        // ------------------------------------------------------
        // Create two derived-type objects
        // ------------------------------------------------------
        read_obj  = new(101, 32'h1000);
        write_obj = new(102, 32'h2000);

        // ======================================================
        // CASE 1: UPCAST — implicit, always safe
        // ======================================================
        $display("\n[CASE 1] Upcast:");
        p_handle = read_obj;     // implicit upcast
        $display("  inherited id = %0d", p_handle.id);   // legal

        // ======================================================
        // CASE 2: SUCCESSFUL DOWNCAST
        // p_handle currently holds a read object → cast succeeds
        // ======================================================
        $display("\n[CASE 2] Downcast to correct type:");
        if ($cast(recovered_read, p_handle)) begin
            $display("  SUCCESS — cast returned 1");
            recovered_read.identify();
        end
        else begin
            $error("  DOWNCAST FAILED — should not happen");
        end

        // ======================================================
        // CASE 3: FAILED DOWNCAST
        // p_handle now points to a WRITE object. Casting to
        // READ will fail at runtime ($cast returns 0).
        // ======================================================
        $display("\n[CASE 3] Downcast to WRONG type:");
        p_handle = write_obj;

        if ($cast(recovered_read, p_handle)) begin
            // This line should NOT execute
            $error("  BUG: illegal cross-type cast succeeded!");
        end
        else begin
            $display("  CORRECTLY REJECTED — cast returned 0");
            // recovered_read is now null:
            if (recovered_read == null)
                $display("  recovered_read is null (safe)");
        end

        // ======================================================
        // CASE 4: Correct cast of the same object
        // ======================================================
        $display("\n[CASE 4] Downcast to correct type:");
        if ($cast(recovered_write, p_handle)) begin
            $display("  SUCCESS");
            recovered_write.identify();
        end
        else begin
            $error("  Should not happen");
        end
    end

endmodule 

// ============================================================
// Day 023: Debugging challenge — the missing `virtual`
// File: day023_debug_virtual.sv
// Purpose: Show the classic bug — missing `virtual` on the
//          base method causes static binding, and the derived
//          method is silently not called.
// ============================================================

`timescale 1ns/1ps

// ============================================================
// VERSION A: BUGGY — missing `virtual`
// ============================================================
class parent_buggy;
    // BUG: no `virtual` keyword — static binding
    function void display();
        $display("Parent (buggy version)");
    endfunction
endclass

class child_buggy extends parent_buggy;
    function void display();   // OVERRIDE
        $display("Child (buggy version)");
    endfunction
endclass


// ============================================================
// VERSION B: FIXED — `virtual` on base
// ============================================================
class parent_fixed;
    // FIX: `virtual` enables dynamic binding
    virtual function void display();
        $display("Parent (fixed version)");
    endfunction
endclass

class child_fixed extends parent_fixed;
    function void display();   // OVERRIDE
        $display("Child (fixed version)");
    endfunction
endclass


// ============================================================
// TESTBENCH — show both versions
// ============================================================
module day023_debug_virtual_tb;

    parent_buggy  p_buggy;
    child_buggy   c_buggy;

    parent_fixed  p_fixed;
    child_fixed   c_fixed;

    initial begin
        // ------------------------------------------------------
        // BUGGY: upcast + call -> calls BASE (wrong)
        // ------------------------------------------------------
        c_buggy = new();
        p_buggy = c_buggy;

        $display("--- BUGGY version (missing virtual) ---");
        $display("Expected: 'Child', Actual: ");
        p_buggy.display();   // prints "Parent (buggy)" — wrong

        // ------------------------------------------------------
        // FIXED: upcast + call -> calls CHILD (correct)
        // ------------------------------------------------------
        c_fixed = new();
        p_fixed = c_fixed;

        $display("\n--- FIXED version (with virtual) ---");
        $display("Expected: 'Child', Actual: ");
        p_fixed.display();   // prints "Child (fixed)" — correct
    end

endmodule
