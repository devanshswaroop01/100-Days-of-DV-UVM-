// ============================================================
// Day 021: OOP fundamentals — the DMA transaction capstone
// File: day021_dma_oop.sv
// Purpose: One class that demonstrates every SV OOP concept:
//            - instance fields (per-object)
//            - static field (per-class)
//            - parameterized constructor with defaults
//            - `this` keyword
//            - instance methods
//            - static method
//            - local / protected access control
// ============================================================

`timescale 1ns/1ps

class dma_transaction;

    // ------------------------------------------------------
    // INSTANCE FIELDS — one copy per object
    // `private` prevents external modification — the getters
    // and setters below are the only legal access points.
    // ------------------------------------------------------
    local int        channel_id;
    local int        transaction_id;
    local bit [31:0] source_addr;
    local bit [31:0] destination_addr;
    local bit [31:0] data;
    local int        transfer_length;

    // ------------------------------------------------------
    // STATIC FIELD — ONE copy for the entire class
    // Counts every object ever created (never decremented).
    // ------------------------------------------------------
    static int object_count = 0;

    // ------------------------------------------------------
    // CONSTRUCTOR
    // Parameterized with default values → `new()` and
    // `new(0)` and `new(0, 32'h1000)` are all legal.
    // `this.field = field` disambiguates from the argument.
    // ------------------------------------------------------
    function new(
        int        ch  = 0,
        int        tx  = 0,
        bit [31:0] src = 32'h1000,
        bit [31:0] dst = 32'h8000,
        int        len = 4
    );
        this.channel_id       = ch;
        this.transaction_id   = tx;
        this.source_addr      = src;
        this.destination_addr = dst;
        this.transfer_length  = len;
        this.data             = 32'h0;

        object_count++;   // static — one global counter
    endfunction : new

    // ------------------------------------------------------
    // INSTANCE METHODS — called via object handle
    // ------------------------------------------------------
    function void set_data(bit [31:0] new_data);
        this.data = new_data;
    endfunction : set_data

    function bit [31:0] get_data();
        return this.data;
    endfunction : get_data

    function void display();
        $display("--------------------------------");
        $display("Channel ID   = %0d", channel_id);
        $display("Transaction  = %0d", transaction_id);
        $display("Source       = 32'h%8h", source_addr);
        $display("Destination  = 32'h%8h", destination_addr);
        $display("Data         = 32'h%8h", data);
        $display("Length       = %0d bytes", transfer_length);
        $display("--------------------------------");
    endfunction : display

    // ------------------------------------------------------
    // STATIC METHOD — called via ClassName::method()
    // Cannot access instance members (no `this`).
    // ------------------------------------------------------
    static function int get_object_count();
        return object_count;
    endfunction : get_object_count

endclass : dma_transaction 


// ============================================================
// Day 021: Handle vs object — the #1 SV OOP confusion
// File: day021_handles.sv
// Purpose: Prove that (a) handle assignment aliases, not copies,
//          (b) object lifetime is automatic (no explicit delete).
// ============================================================

`timescale 1ns/1ps

class simple_tx;
    int data;
endclass


module day021_handles;

    initial begin
        simple_tx tx0;
        simple_tx tx1;
        simple_tx tx2;

        $display("\n=== Handle vs object ===");

        // ------------------------------------------------------
        // STEP 1: create object on heap, tx0 points to it
        // ------------------------------------------------------
        tx0 = new();
        tx0.data = 100;
        $display("tx0.data = %0d", tx0.data);      // 100

        // ------------------------------------------------------
        // STEP 2: handle assignment — ALIAS, not copy
        // tx0 and tx1 now point to the SAME object.
        // ------------------------------------------------------
        tx1 = tx0;
        $display("After tx1 = tx0:");
        $display("  tx0.data = %0d", tx0.data);    // 100
        $display("  tx1.data = %0d", tx1.data);    // 100 (same object)

        // ------------------------------------------------------
        // STEP 3: modify through tx1 — tx0 sees it too
        // ------------------------------------------------------
        tx1.data = 500;
        $display("After tx1.data = 500:");
        $display("  tx0.data = %0d (proves aliasing)", tx0.data);
        $display("  tx1.data = %0d", tx1.data);

        // ------------------------------------------------------
        // STEP 4: null handle
        // Setting to null disconnects; the object still exists
        // until the last handle is nulled (then it's GC'd).
        // ------------------------------------------------------
        tx2 = null;
        if (tx2 == null)
            $display("tx2 is null — safe to check before use");

        // ------------------------------------------------------
        // STEP 5: accessing a null handle is a runtime error
        // Uncommenting the next line crashes the simulation:
        //   $display("%0d", tx2.data);
        // ------------------------------------------------------
        $display("(skipping tx2.data — would crash: null handle)");
    end

endmodule


// ============================================================
// Day 021: Access control — public / local / protected
// File: day021_access.sv
// Purpose: Show the three access levels and demonstrate that
//          illegal access is a COMPILE error, not a runtime one.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// Base class — three access levels, side by side
// ------------------------------------------------------------
class base_access;

    int 		  public_val;      // anyone can read/write
    local     int local_val;       // ONLY base_access methods
    protected int protected_val;   // base_access AND subclasses

    function new(int p, int l, int pr);
        this.public_val    = p;
        this.local_val     = l;
        this.protected_val = pr;
    endfunction : new

    // ------------------------------------------------------
    // Public getter for the hidden local_val
    // This is the ONLY way to read local_val from outside.
    // ------------------------------------------------------
    function int get_local_val();
        return this.local_val;
    endfunction : get_local_val

endclass : base_access


// ------------------------------------------------------------
// Subclass — shows which inherited members are visible
// ------------------------------------------------------------
class derived_access extends base_access;

    function new(int p, int l, int pr);
        super.new(p, l, pr);
    endfunction

    function void show_inherited();
        // ---------------------------------------------------
        // public_val    — legal (public)
        // ---------------------------------------------------
        $display("derived: public_val    = %0d", public_val);

        // ---------------------------------------------------
        // local_val     — ILLEGAL: local is only visible in base_access
        // ---------------------------------------------------
        // $display("%0d", local_val);  // COMPILE ERROR

        // ---------------------------------------------------
        // protected_val — LEGAL: protected is visible in subclasses
        // ---------------------------------------------------
        $display("derived: protected_val = %0d", protected_val);
    endfunction

endclass : derived_access


module day021_access;

    initial begin
        base_access    b;
        derived_access d;

        $display("\n=== Access control ===");

        b = new(10, 20, 30);

        // ------------------------------------------------------
        // LEGAL: public_val
        // ------------------------------------------------------
        b.public_val = 50;
        $display("public_val = %0d (legal)", b.public_val);

        // ------------------------------------------------------
        // ILLEGAL (compile error if uncommented):
        //   b.local_val     = 40;
        //   b.protected_val = 60;
        // ------------------------------------------------------
        $display("local_val     = %0d (via getter only)",
                 b.get_local_val());

        // ------------------------------------------------------
        // Subclass inherits public and protected, NOT local
        // ------------------------------------------------------
        d = new(100, 200, 300);
        d.show_inherited();
    end

endmodule 
