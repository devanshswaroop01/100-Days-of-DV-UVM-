// ============================================================
// Day 026: Integrated DMA framework — the OOP capstone
// File: day026_dma_framework.sv
// Purpose: Every OOP concept from Days 021-025 combined:
//          - abstract base class (virtual class)
//          - pure virtual execute()
//          - encapsulated local fields + getters
//          - static object counter
//          - validating setter (from A5)
//          - inheritance + super.new()
//          - queue of base handles + polymorphism
//          - $cast downcast (success AND failure) (from A3)
// ============================================================

`timescale 1ns/1ps

// ============================================================
// ABSTRACT BASE CLASS
// ============================================================
virtual class dma_transaction;

    // ------------------------------------------------------
    // ENCAPSULATED FIELDS — hidden from external code
    // ------------------------------------------------------
    local int unsigned transaction_id;
    local int unsigned channel_id;
    local bit [31:0]   address;
    local int unsigned length;

    // ------------------------------------------------------
    // STATIC COUNTER — one per class, shared across all
    // subclasses (they call super.new())
    // ------------------------------------------------------
    static int unsigned object_count = 0;

    // ------------------------------------------------------
    // CONSTRUCTOR
    // ------------------------------------------------------
    function new(
        int unsigned id,
        int unsigned ch,
        bit [31:0]   addr,
        int unsigned len
    );
        transaction_id = id;
        channel_id     = ch;
        address        = addr;
        length         = len;
        object_count++;
    endfunction

    // ======================================================
    // GETTERS — the only way to read the hidden fields
    // ======================================================
    function int unsigned get_id();      return transaction_id; endfunction
    function int unsigned get_channel(); return channel_id;     endfunction
    function bit [31:0]   get_address(); return address;        endfunction
    function int unsigned get_length();  return length;         endfunction

    // ------------------------------------------------------
    // VALIDATING SETTER (from Assignment 5)
    // Rejects non-aligned addresses; leaves state unchanged.
    // ------------------------------------------------------
    function bit set_address(bit [31:0] addr);
        if (addr[1:0] == 2'b00) begin
            address = addr;
            return 1;
        end
        $display("ERROR: address 0x%0h not 4-byte aligned", addr);
        return 0;
    endfunction

    // ------------------------------------------------------
    // COMMON DISPLAY — shared by all subclasses
    // ------------------------------------------------------
    function void display_common();
        $display("--------------------------------");
        $display("Transaction ID = %0d", transaction_id);
        $display("Channel ID     = %0d", channel_id);
        $display("Address        = 0x%0h", address);
        $display("Length         = %0d", length);
    endfunction

    // ------------------------------------------------------
    // PURE VIRTUAL — must be implemented by every subclass
    // ------------------------------------------------------
    pure virtual function void execute();

    // ------------------------------------------------------
    // STATIC METHOD — query the global counter
    // ------------------------------------------------------
    static function int unsigned get_object_count();
        return object_count;
    endfunction

endclass


// ============================================================
// SUBCLASS 1 — READ
// ============================================================
class dma_read_transaction extends dma_transaction;

    local bit [31:0] read_data;

    function new(
        int unsigned id, int unsigned ch,
        bit [31:0] addr, int unsigned len,
        bit [31:0] data
    );
        super.new(id, ch, addr, len);
        read_data = data;
    endfunction

    function bit [31:0] get_read_data(); return read_data; endfunction

    virtual function void execute();
        $display("[DMA READ]");
        $display("  Reading address = 0x%0h", get_address());
        $display("  Read data       = 0x%0h", read_data);
    endfunction

endclass


// ============================================================
// SUBCLASS 2 — WRITE
// ============================================================
class dma_write_transaction extends dma_transaction;

    local bit [31:0] write_data;

    function new(
        int unsigned id, int unsigned ch,
        bit [31:0] addr, int unsigned len,
        bit [31:0] data
    );
        super.new(id, ch, addr, len);
        write_data = data;
    endfunction

    function bit [31:0] get_write_data(); return write_data; endfunction

    virtual function void execute();
        $display("[DMA WRITE]");
        $display("  Writing data = 0x%0h", write_data);
        $display("  To address   = 0x%0h", get_address());
    endfunction

endclass


// ============================================================
// SUBCLASS 3 — BURST
// ============================================================
class dma_burst_transaction extends dma_transaction;

    local int unsigned burst_size;
    local bit [31:0]   burst_data[];

    function new(
        int unsigned id, int unsigned ch,
        bit [31:0] addr, int unsigned len,
        int unsigned size
    );
        super.new(id, ch, addr, len);
        burst_size = size;
        burst_data = new[size];
        foreach (burst_data[i])
            burst_data[i] = 32'h1000 + i;
    endfunction

    virtual function void execute();
        $display("[DMA BURST]");
        $display("  Burst size = %0d", burst_size);
        foreach (burst_data[i])
            $display("  Data[%0d] = 0x%0h", i, burst_data[i]);
    endfunction

endclass


// ============================================================
// GENERIC PROCESSOR — accepts any dma_transaction subtype
// ============================================================
class dma_processor;

    function void process(dma_transaction tx);
        // --------------------------------------------------
        // Null check — base handles can be null
        // --------------------------------------------------
        if (tx == null) begin
            $display("ERROR: null transaction");
            return;
        end

        // --------------------------------------------------
        // Polymorphic dispatch:
        // - display_common() uses the base implementation
        // - execute() dispatches to the concrete subclass
        // --------------------------------------------------
        tx.display_common();
        tx.execute();
    endfunction

endclass


// ============================================================
// TESTBENCH
// ============================================================
module day026_dma_framework_tb;

    dma_transaction        tx;
    dma_read_transaction   read_tx;
    dma_write_transaction  write_tx;
    dma_burst_transaction  burst_tx;
    dma_processor          processor;

    // ------------------------------------------------------
    // HETEROGENEOUS QUEUE — base handles, mixed subtypes
    // ------------------------------------------------------
    dma_transaction        transaction_queue[$];

    initial begin

        processor = new();

        // ------------------------------------------------------
        // 1. Create derived objects
        // ------------------------------------------------------
        read_tx  = new(1, 0, 32'h1000, 4, 32'hABCD);
        write_tx = new(2, 1, 32'h2000, 4, 32'h1234);
        burst_tx = new(3, 2, 32'h3000, 4, 4);

        // ------------------------------------------------------
        // 2. Store in a queue of base handles (polymorphic)
        // ------------------------------------------------------
        transaction_queue.push_back(read_tx);
        transaction_queue.push_back(write_tx);
        transaction_queue.push_back(burst_tx);

        // ------------------------------------------------------
        // 3. Process the queue polymorphically
        // ------------------------------------------------------
        $display("\n===== POLYMORPHIC PROCESSING =====");
        foreach (transaction_queue[i]) begin
            tx = transaction_queue[i];
            processor.process(tx);
        end

        // ------------------------------------------------------
        // 4. $cast downcast — SUCCESS case (from A3)
        // ------------------------------------------------------
        $display("\n===== $CAST SUCCESS =====");
        tx = transaction_queue[0];   // read object
        if ($cast(read_tx, tx)) begin
            $display("Read transaction recovered");
            $display("read_data = 0x%0h", read_tx.get_read_data());
        end
        else begin
            $display("Unexpected: downcast failed");
        end

        // ------------------------------------------------------
        // 5. $cast downcast — FAILURE case (from A3)
        // Attempt to cast a WRITE object to a READ handle.
        // ------------------------------------------------------
        $display("\n===== $CAST FAILURE =====");
        tx = transaction_queue[1];   // write object
        if ($cast(read_tx, tx)) begin
            $display("BUG: write object cast as read!");
        end
        else begin
            $display("Correctly rejected — type mismatch detected");
            $display("read_tx is now null: %s",
                     (read_tx == null) ? "yes" : "no");
        end

        // ------------------------------------------------------
        // 6. Validating setter from the base class (from A5)
        // ------------------------------------------------------
        $display("\n===== VALIDATING SETTER =====");
        if (read_tx == null) read_tx = new(4, 0, 32'h4000, 4, 32'h0);

        if (read_tx.set_address(32'h5000))
            $display("set_address(0x5000) — accepted");
        if (!read_tx.set_address(32'h5003))
            $display("set_address(0x5003) — rejected (misaligned)");
        $display("Final address = 0x%0h (unchanged from valid set)",
                 read_tx.get_address());

        // ------------------------------------------------------
        // 7. Static object count via BASE and SUBCLASS scopes (from A1)
        // All three return the SAME value — inherited static storage
        // ------------------------------------------------------
        $display("\n===== STATIC OBJECT COUNT =====");
        $display("via base:  %0d", dma_transaction::get_object_count());
        $display("via read:  %0d", dma_read_transaction::get_object_count());
        $display("via write: %0d", dma_write_transaction::get_object_count());

        $display("\n===== COMPLETE =====");
    end

endmodule 

      

// ============================================================
// Day 026: Static members across inheritance — the counter
// File: day026_static_counter.sv
// Purpose: A focused demo that static members are SHARED
//          across the entire inheritance hierarchy. Querying
//          via base or any subclass returns the same value.
// ============================================================

`timescale 1ns/1ps

package static_counter_pkg;

    // ------------------------------------------------------
    // BASE — declares the static counter
    // ------------------------------------------------------
    class base_transaction;
        static int object_count = 0;

        function new();
            object_count++;
        endfunction

        static function int get_count();
            return object_count;
        endfunction
    endclass

    // ------------------------------------------------------
    // SUBCLASSES — inherit the SAME storage location
    // ------------------------------------------------------
    class pci_transaction extends base_transaction;
        function new(); super.new(); endfunction
    endclass

    class axi_transaction extends base_transaction;
        function new(); super.new(); endfunction
    endclass

endpackage : static_counter_pkg


// ============================================================
// TESTBENCH
// ============================================================
module day026_static_counter_tb;

    import static_counter_pkg::*;

    base_transaction b_tx;
    pci_transaction  p_tx;
    axi_transaction  a_tx;

    initial begin
        $display("\n=== Static counter across hierarchy ===");

        // ------------------------------------------------------
        // Instantiate 5 objects of mixed subtypes
        // ------------------------------------------------------
        b_tx = new();   // 1
        p_tx = new();   // 2
        p_tx = new();   // 3
        a_tx = new();   // 4
        a_tx = new();   // 5

        // ------------------------------------------------------
        // Query via base and both subclass scopes
        // All three return the same number
        // ------------------------------------------------------
        $display("via base: %0d", base_transaction::get_count());
        $display("via PCI : %0d", pci_transaction::get_count());
        $display("via AXI : %0d", axi_transaction::get_count());

        if (base_transaction::get_count() == 5)
            $display("PASS: static counter shared across all subclasses");
        else
            $display("FAIL: counter mismatch");
    end

endmodule

      // ============================================================
// Day 026: Debugging — missing `virtual` on base method
// File: day026_debug_virtual.sv
// Purpose: Show the silent bug — a missing `virtual` keyword
//          causes static binding, and the derived method is
//          never called through a base handle.
// ============================================================

`timescale 1ns/1ps

// ============================================================
// BUGGY VERSION — no `virtual`
// ============================================================
class parent_buggy;
    // BUG: missing `virtual`
    function void execute();
        $display("Parent (buggy)");
    endfunction
endclass

class child_buggy extends parent_buggy;
    function void execute();      // override — but no dispatch
        $display("Child (buggy)");
    endfunction
endclass


// ============================================================
// FIXED VERSION — `virtual` on base
// ============================================================
class parent_fixed;
    virtual function void execute();   // FIX
        $display("Parent (fixed)");
    endfunction
endclass

class child_fixed extends parent_fixed;
    function void execute();
        $display("Child (fixed)");
    endfunction
endclass


// ============================================================
// TESTBENCH
// ============================================================
module day026_debug_virtual_tb;

    parent_buggy p_buggy;  child_buggy c_buggy;
    parent_fixed p_fixed;  child_fixed c_fixed;

    initial begin
        $display("\n=== BUGGY (missing virtual) ===");
        c_buggy = new();
        p_buggy = c_buggy;
        $display("Expected: 'Child', Actual: ");
        p_buggy.execute();    // prints "Parent (buggy)" — WRONG

        $display("\n=== FIXED (with virtual) ===");
        c_fixed = new();
        p_fixed = c_fixed;
        $display("Expected: 'Child', Actual: ");
        p_fixed.execute();    // prints "Child (fixed)" — CORRECT
    end

endmodule  
