// ============================================================
// Day 022: Inheritance fundamentals — DMA transaction family
// File: day022_dma_inheritance.sv
// Purpose: Demonstrate the full inheritance toolkit:
//            - base class with `virtual` method
//            - three derived classes, each with super.new
//            - method override with super.method() extension
//            - polymorphic array of mixed subtypes
// ============================================================

`timescale 1ns/1ps

// ============================================================
// BASE CLASS — common fields + virtual display
// ============================================================
class dma_transaction;

    int unsigned transaction_id;
    int unsigned channel_id;
    bit [31:0]   address;
    int unsigned length;

    // ------------------------------------------------------
    // BASE CONSTRUCTOR — child classes will call super.new()
    // ------------------------------------------------------
    function new(
        int unsigned id   = 0,
        int unsigned ch   = 0,
        bit [31:0]   addr = 0,
        int unsigned len  = 1
    );
        transaction_id = id;
        channel_id     = ch;
        address        = addr;
        length         = len;
        $display("[BASE] created");
    endfunction

    // ------------------------------------------------------
    // VIRTUAL METHOD — the polymorphism hook
    // Must be `virtual` for runtime dispatch when called
    // through a base-class handle.
    // ------------------------------------------------------
    virtual function void display();
        $display("--------------------------------");
        $display("Transaction ID : %0d", transaction_id);
        $display("Channel ID     : %0d", channel_id);
        $display("Address        : 0x%0h", address);
        $display("Length         : %0d", length);
    endfunction

endclass


// ============================================================
// DERIVED CLASS 1 — READ transaction
// ============================================================
class dma_read_transaction extends dma_transaction;

    bit [31:0] source_address;
    bit [31:0] read_data;

    // ------------------------------------------------------
    // CHILD CONSTRUCTOR
    // `super.new(...)` MUST be first — it initializes the
    // base-class fields before the child adds its own.
    // ------------------------------------------------------
    function new(
        int unsigned id,
        int unsigned ch,
        bit [31:0]   addr,
        int unsigned len,
        bit [31:0]   data
    );
        super.new(id, ch, addr, len);   // MUST be first
        source_address = addr;
        read_data      = data;
        $display("[READ] created");
    endfunction

    // ------------------------------------------------------
    // OVERRIDE — call super.display(), then extend
    // ------------------------------------------------------
    virtual function void display();
        super.display();          // reuse base output
        $display("Operation      : READ");
        $display("Source Address : 0x%0h", source_address);
        $display("Read Data      : 0x%0h", read_data);
    endfunction

endclass


// ============================================================
// DERIVED CLASS 2 — WRITE transaction
// ============================================================
class dma_write_transaction extends dma_transaction;

    bit [31:0] destination_address;
    bit [31:0] write_data;

    function new(
        int unsigned id,
        int unsigned ch,
        bit [31:0]   addr,
        int unsigned len,
        bit [31:0]   data
    );
        super.new(id, ch, addr, len);
        destination_address = addr;
        write_data          = data;
        $display("[WRITE] created");
    endfunction

    virtual function void display();
        super.display();
        $display("Operation           : WRITE");
        $display("Destination Address : 0x%0h", destination_address);
        $display("Write Data          : 0x%0h", write_data);
    endfunction

endclass


// ============================================================
// DERIVED CLASS 3 — BURST transaction
// Adds a dynamic array (burst_data[]) — shows that child
// classes can have their own storage.
// ============================================================
class dma_burst_transaction extends dma_transaction;

    int unsigned burst_size;
    bit [31:0]   burst_data[];   // dynamic array

    function new(
        int unsigned id,
        int unsigned ch,
        bit [31:0]   addr,
        int unsigned len,
        int unsigned size
    );
        super.new(id, ch, addr, len);
        burst_size = size;
        burst_data = new[size];   // dynamic array allocation
        foreach (burst_data[i])
            burst_data[i] = 32'h1000 + i;
        $display("[BURST] created");
    endfunction

    virtual function void display();
        super.display();
        $display("Operation  : BURST");
        $display("Burst Size : %0d", burst_size);
        foreach (burst_data[i])
            $display("Burst Data[%0d] = 0x%0h", i, burst_data[i]);
    endfunction

endclass


// ============================================================
// TESTBENCH — polymorphism demonstration
// ============================================================
module day022_dma_inheritance_tb;

    dma_transaction        tx;          // BASE handle
    dma_read_transaction   read_tx;
    dma_write_transaction  write_tx;
    dma_burst_transaction  burst_tx;

    initial begin

        // ------------------------------------------------------
        // 1. Direct instantiation of each derived type
        // ------------------------------------------------------
        $display("\n===== DIRECT CALLS =====");

        read_tx  = new(1, 0, 32'h1000, 4, 32'hABCD);
        read_tx.display();

        write_tx = new(2, 1, 32'h2000, 4, 32'h1234);
        write_tx.display();

        burst_tx = new(3, 2, 32'h3000, 4, 4);
        burst_tx.display();

        // ------------------------------------------------------
        // 2. POLYMORPHISM — base handle points to derived objects
        // The compiler sees dma_transaction::display is virtual,
        // so it schedules a runtime dispatch based on the actual
        // object type, not the handle type.
        // ------------------------------------------------------
        $display("\n===== POLYMORPHIC CALLS =====");

        tx = read_tx;
        tx.display();      // calls dma_read_transaction::display

        tx = write_tx;
        tx.display();      // calls dma_write_transaction::display

        tx = burst_tx;
        tx.display();      // calls dma_burst_transaction::display
    end

endmodule  



// ============================================================
// Day 022: Pure virtual methods — abstract classes
// File: day022_pure_virtual.sv
// Purpose: A class with a `pure virtual` method cannot be
//          instantiated. Every non-abstract subclass MUST
//          implement the pure virtual method.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// PACKAGE — for encapsulation (UVM-style)
// ------------------------------------------------------------
package apb_verification_pkg;

    // ------------------------------------------------------
    // ABSTRACT BASE CLASS
    // Contains `pure virtual function is_write()` — no body.
    // Cannot be instantiated directly.
    // ------------------------------------------------------
    virtual class apb_transaction;

        rand bit [31:0] paddr;
        rand bit [31:0] pdata;

        // --------------------------------------------------
        // PURE VIRTUAL — the contract every subclass must fulfill
        // --------------------------------------------------
        pure virtual function bit is_write();

        function new(bit [31:0] paddr = 0, bit [31:0] pdata = 0);
            this.paddr = paddr;
            this.pdata = pdata;
        endfunction

        virtual function void display();
            $display("APB Access -> Address: 0x%8h", this.paddr);
        endfunction

    endclass : apb_transaction


    // ------------------------------------------------------
    // CONCRETE SUBCLASS 1 — READ
    // Must implement is_write() or compile error.
    // ------------------------------------------------------
    class apb_read_transaction extends apb_transaction;

        function new(bit [31:0] paddr = 0, bit [31:0] pdata = 0);
            super.new(paddr, pdata);
        endfunction

        virtual function bit is_write();   // MUST implement
            return 1'b0;
        endfunction

        virtual function void display();
            super.display();
            $display("  Direction: READ  | Read Data: 0x%8h", pdata);
        endfunction

    endclass


    // ------------------------------------------------------
    // CONCRETE SUBCLASS 2 — WRITE
    // ------------------------------------------------------
    class apb_write_transaction extends apb_transaction;

        function new(bit [31:0] paddr = 0, bit [31:0] pdata = 0);
            super.new(paddr, pdata);
        endfunction

        virtual function bit is_write();   // MUST implement
            return 1'b1;
        endfunction

        virtual function void display();
            super.display();
            $display("  Direction: WRITE | Write Data: 0x%8h", pdata);
        endfunction

    endclass

endpackage : apb_verification_pkg


// ============================================================
// TESTBENCH
// ============================================================
module day022_pure_virtual_tb;

    import apb_verification_pkg::*;

    initial begin
        apb_transaction       tx;         // base handle
        apb_read_transaction  r;
        apb_write_transaction w;

        $display("\n=== Pure virtual demo ===");

        // ------------------------------------------------------
        // ILLEGAL: cannot instantiate abstract base
        // Uncomment to see the compile error:
        //   tx = new();   // ERROR: apb_transaction is abstract
        // ------------------------------------------------------

        // ------------------------------------------------------
        // Legal: instantiate concrete subclasses
        // ------------------------------------------------------
        r = new(32'h4000_0000, 32'h5555_6666);
        w = new(32'h4000_0004, 32'h1111_2222);

        // ------------------------------------------------------
        // Polymorphic dispatch — the base handle can hold either
        // subclass, and display() picks the correct one.
        // ------------------------------------------------------
        tx = r;  tx.display();   // READ
        tx = w;  tx.display();   // WRITE

        // ------------------------------------------------------
        // Polymorphic method call — is_write() defined per subclass
        // ------------------------------------------------------
        tx = r;
        $display("r.is_write() = %0b", tx.is_write());
        tx = w;
        $display("w.is_write() = %0b", tx.is_write());
    end

endmodule 

          // ============================================================
// Day 022: Polymorphic array — the killer app of inheritance
// File: day022_poly_array.sv
// Purpose: One array of `apb_transaction` handles, holding
//          instances of different subclasses. Loop calls
//          display() — each element dispatches correctly.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// Class hierarchy
// ------------------------------------------------------------

// Base class representing a generic APB transaction
class apb_transaction;

    bit [31:0] addr;
    bit [31:0] data;

    // Constructor initializes common base properties
    function new(bit [31:0] a = 0, bit [31:0] d = 0);
        addr = a;  data = d;
    endfunction

    // VIRTUAL KEYWORD: Enables dynamic method dispatch (polymorphism).
    // This allows subclass overrides to be called via base-class handles.
    virtual function void display();
        $display("Address = 0x%0h", addr);
    endfunction

endclass


// Subclass representing a read transaction (inherits from apb_transaction)
class apb_read_transaction extends apb_transaction;

    // Calls base constructor with data fixed to 0
    function new(bit [31:0] a);
        super.new(a, 0);
    endfunction

    // Overrides base display() to add read-specific details
    virtual function void display();
        super.display(); // Calls base class display first
        $display("APB Operation = READ");
    endfunction

endclass


// Subclass representing a write transaction (inherits from apb_transaction)
class apb_write_transaction extends apb_transaction;

    // Calls base constructor passing both address and data
    function new(bit [31:0] a, bit [31:0] d);
        super.new(a, d);
    endfunction

    // Overrides base display() to add write-specific details including data
    virtual function void display();
        super.display(); // Calls base class display first
        $display("APB Operation = WRITE  data=0x%0h", data);
    endfunction

endclass


// ============================================================
// TESTBENCH — one array, multiple subtypes
// ============================================================
module day022_poly_array_tb;

    // ------------------------------------------------------
    // POLYMORPHIC ARRAY: An array of base-class handles.
    // Because of inheritance, a base handle can point to any 
    // object of its own type or any of its derived subclasses.
    // ------------------------------------------------------
    apb_transaction bus_bucket[2];

    initial begin
        // Temporary concrete subclass handles for safe instantiation
        apb_read_transaction  r_tx;
        apb_write_transaction w_tx;

        $display("\n=== Polymorphic array ===");

        // ------------------------------------------------------
        // Step 1: Instantiate concrete subclasses using their 
        // own specific types to ensure parser safety and compatibility.
        // ------------------------------------------------------
        r_tx = new(32'h4000_0000);
        w_tx = new(32'h4000_0004, 32'h1111_2222);

        // ------------------------------------------------------
        // Step 2: Assign subclass handles into the base-class array.
        // This is legal because a read/write transaction *is-a* 
        // transaction (upcasting).
        // ------------------------------------------------------
        bus_bucket[0] = r_tx;
        bus_bucket[1] = w_tx;

        // ------------------------------------------------------
        // Step 3: Iterate through the polymorphic array and invoke
        // the display() method. 
        // 
        // DYNAMIC DISPATCH: Even though the array type is 
        // `apb_transaction`, SystemVerilog looks at the *actual* 
        // object referenced at runtime and executes the correct 
        // overridden version of display() for each element.
        // ------------------------------------------------------
        foreach (bus_bucket[i]) begin
            $display("--- Element %0d ---", i);
            bus_bucket[i].display();   // Dynamic dispatch at work
        end
    end

endmodule

          
