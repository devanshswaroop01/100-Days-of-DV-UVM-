// ============================================================
// Day 024: Abstract base class + pure virtual methods
// File: day024_abstract_dma.sv
// Purpose: The canonical abstract-class demo. `virtual class`
//          cannot be instantiated. `pure virtual execute()`
//          forces every concrete subclass to provide a body.
// ============================================================

`timescale 1ns/1ps

// ============================================================
// ABSTRACT BASE — cannot be instantiated
// ============================================================
virtual class dma_transaction;

    // ------------------------------------------------------
    // SHARED FIELDS — every DMA transaction has these
    // ------------------------------------------------------
    int unsigned transaction_id;
    int unsigned channel_id;
    bit [31:0]   address;
    int unsigned length;

    // ------------------------------------------------------
    // CONSTRUCTOR — callable via super.new() by subclasses
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
    endfunction

    // ------------------------------------------------------
    // SHARED CONCRETE METHOD — no override needed
    // All subclasses inherit this body as-is.
    // ------------------------------------------------------
    function void display_common();
        $display("--------------------------------");
        $display("Transaction ID = %0d", transaction_id);
        $display("Channel ID     = %0d", channel_id);
        $display("Address        = 0x%0h", address);
        $display("Length         = %0d", length);
    endfunction

    // ------------------------------------------------------
    // PURE VIRTUAL — no body
    // Every concrete subclass MUST provide its own.
    // Any class that doesn't becomes abstract.
    // ------------------------------------------------------
    pure virtual function void execute();

endclass


// ============================================================
// CONCRETE SUBCLASS 1 — READ
// ============================================================
class dma_read_transaction extends dma_transaction;

    bit [31:0] read_data;

    function new(
        int unsigned id,
        int unsigned ch,
        bit [31:0]   addr,
        int unsigned len,
        bit [31:0]   data
    );
        super.new(id, ch, addr, len);
        read_data = data;
    endfunction

    // ------------------------------------------------------
    // MUST implement — otherwise this subclass is also abstract
    // ------------------------------------------------------
    virtual function void execute();
        $display("[DMA READ]");
        $display("  Reading from address = 0x%0h", address);
        $display("  Read data = 0x%0h", read_data);
    endfunction

endclass


// ============================================================
// CONCRETE SUBCLASS 2 — WRITE
// ============================================================
class dma_write_transaction extends dma_transaction;

    bit [31:0] write_data;

    function new(
        int unsigned id,
        int unsigned ch,
        bit [31:0]   addr,
        int unsigned len,
        bit [31:0]   data
    );
        super.new(id, ch, addr, len);
        write_data = data;
    endfunction

    virtual function void execute();
        $display("[DMA WRITE]");
        $display("  Writing data = 0x%0h", write_data);
        $display("  To address   = 0x%0h", address);
    endfunction

endclass


// ============================================================
// CONCRETE SUBCLASS 3 — BURST
// ============================================================
class dma_burst_transaction extends dma_transaction;

    int unsigned burst_size;
    bit [31:0]   burst_data[];

    function new(
        int unsigned id,
        int unsigned ch,
        bit [31:0]   addr,
        int unsigned len,
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
            $display("  Burst data[%0d] = 0x%0h", i, burst_data[i]);
    endfunction

endclass


// ============================================================
// TESTBENCH
// ============================================================
module day024_abstract_dma_tb;

    dma_read_transaction  read_tx;
    dma_write_transaction write_tx;
    dma_burst_transaction burst_tx;
    dma_transaction       tx;    // base handle

    initial begin
        // ------------------------------------------------------
        // ILLEGAL: cannot instantiate abstract class
        // Uncomment to see the compile error:
        //   tx = new();   // ERROR: dma_transaction is abstract
        // ------------------------------------------------------

        $display("\n===== READ =====");
        read_tx = new(1, 0, 32'h1000, 4, 32'hABCD);
        tx = read_tx;
        tx.display_common();
        tx.execute();

        $display("\n===== WRITE =====");
        write_tx = new(2, 1, 32'h2000, 4, 32'h1234);
        tx = write_tx;
        tx.display_common();
        tx.execute();

        $display("\n===== BURST =====");
        burst_tx = new(3, 2, 32'h3000, 4, 4);
        tx = burst_tx;
        tx.display_common();
        tx.execute();
    end

endmodule

// ============================================================
// Day 024: Generic processor — why abstract classes matter
// File: day024_generic_processor.sv
// Purpose: One class that processes ANY subclass of
//          dma_transaction without modification. This is the
//          entire point of an abstract base class.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// (Reuse the abstract hierarchy from Part 1 — abbreviated here)
// ------------------------------------------------------------
virtual class dma_transaction;
    pure virtual function void execute();
    virtual function void display_common();
        $display("[common display]");
    endfunction
endclass

class dma_read_transaction extends dma_transaction;
    virtual function void execute();
        $display("[READ]");
    endfunction
endclass

class dma_write_transaction extends dma_transaction;
    virtual function void execute();
        $display("[WRITE]");
    endfunction
endclass

class dma_burst_transaction extends dma_transaction;
    virtual function void execute();
        $display("[BURST]");
    endfunction
endclass


// ============================================================
// GENERIC PROCESSOR — accepts any dma_transaction subclass
// ============================================================
class dma_processor;

    // ------------------------------------------------------
    // `process` accepts the ABSTRACT base handle.
    // It can be called with any concrete subclass object.
    // ------------------------------------------------------
    function void process(dma_transaction tx);

        // --------------------------------------------------
        // Null-check — abstract handles can be null
        // --------------------------------------------------
        if (tx == null) begin
            $display("ERROR: null transaction handle");
            return;
        end

        // --------------------------------------------------
        // Polymorphic dispatch:
        // - display_common is the base implementation
        // - execute dispatches to the concrete subclass
        // --------------------------------------------------
        tx.display_common();
        tx.execute();
    endfunction

endclass


// ============================================================
// TESTBENCH
// ============================================================
module day024_generic_processor_tb;

    dma_processor          processor;
    dma_read_transaction   read_tx;
    dma_write_transaction  write_tx;
    dma_burst_transaction  burst_tx;

    initial begin
        processor = new();

        read_tx  = new();
        write_tx = new();
        burst_tx = new();

        // ------------------------------------------------------
        // Same processor method, three different concrete types
        // ------------------------------------------------------
        $display("--- Process read ---");
        processor.process(read_tx);

        $display("--- Process write ---");
        processor.process(write_tx);

        $display("--- Process burst ---");
        processor.process(burst_tx);
    end

endmodule

      // ============================================================
// Day 024: Abstract APB transactions — pattern generalization
// File: day024_abstract_apb.sv
// Purpose: Same abstract-class pattern as Part 1, but with
//          APB vocabulary. Demonstrates that the pattern is
//          protocol-independent.
// ============================================================

`timescale 1ns/1ps

// ============================================================
// ABSTRACT APB BASE
// ============================================================
virtual class apb_transaction;

    rand bit [31:0] addr;
    rand bit [31:0] data;
    bit             pwrite;

    function new(bit [31:0] a, bit [31:0] d, bit w);
        addr   = a;
        data   = d;
        pwrite = w;
    endfunction

    pure virtual function void execute();

endclass


// ============================================================
// CONCRETE READ
// ============================================================
class apb_read_tx extends apb_transaction;

    function new(bit [31:0] a);
        super.new(a, 32'h0, 1'b0);    // pwrite = 0
    endfunction

    virtual function void execute();
        $display("[APB READ]  addr = 0x%0h", addr);
    endfunction

endclass


// ============================================================
// CONCRETE WRITE
// ============================================================
class apb_write_tx extends apb_transaction;

    function new(bit [31:0] a, bit [31:0] d);
        super.new(a, d, 1'b1);         // pwrite = 1
    endfunction

    virtual function void execute();
        $display("[APB WRITE] addr = 0x%0h data = 0x%0h",
                 addr, data);
    endfunction

endclass


// ============================================================
// GENERIC PROCESSOR — identical shape to Part 2
// ============================================================
class generic_apb_processor;

    task process_tx(apb_transaction tx);
        if (tx == null) begin
            $display("ERROR: null APB transaction");
            return;
        end
        tx.execute();
    endtask

endclass


// ============================================================
// TESTBENCH
// ============================================================
module day024_abstract_apb_tb;

    generic_apb_processor proc;
    apb_read_tx           read_tx;
    apb_write_tx          write_tx;

    initial begin
        proc     = new();
        read_tx  = new(32'h4000_0000);
        write_tx = new(32'h4000_0004, 32'h5555_AAAA);

        proc.process_tx(read_tx);
        proc.process_tx(write_tx);
    end

endmodule


// ============================================================
// Day 024: Debugging — incomplete pure-virtual implementation
// File: day024_debug_abstract.sv
// Purpose: Two versions of a subclass:
//          (A) buggy — forgot to implement execute()
//          (B) fixed — implements execute()
// See what the compiler says.
// ============================================================

`timescale 1ns/1ps

// ============================================================
// ABSTRACT BASE (same as Part 1)
// ============================================================
virtual class transaction;
    int unsigned id;
    bit [31:0]   address;

    function new(int unsigned i, bit [31:0] a);
        id      = i;
        address = a;
    endfunction

    function void display_common();
        $display("ID = %0d, addr = 0x%0h", id, address);
    endfunction

    pure virtual function void execute();
endclass


// ============================================================
// VERSION A: BUGGY — no execute() implementation
// ============================================================
class dma_transaction_buggy extends transaction;

    function new();
        super.new(0, 0);
    endfunction

    // BUG: execute() NOT implemented.
    // Because execute() is pure virtual in the base and this
    // class doesn't implement it, this class is ALSO abstract.
    // Uncommenting the `new()` in the TB below will be a
    // compile error: "cannot instantiate dma_transaction_buggy"
endclass


// ============================================================
// VERSION B: FIXED — implements execute()
// ============================================================
class dma_transaction_fixed extends transaction;

    function new();
        super.new(0, 0);
    endfunction

    // FIX: implement the mandatory pure virtual method
    virtual function void execute();
        $display("DMA execution routine triggered");
    endfunction

endclass


// ============================================================
// TESTBENCH — show both
// ============================================================
module day024_debug_abstract_tb;

    // ------------------------------------------------------
    // BUGGY: cannot instantiate — would be compile error
    // ------------------------------------------------------
    // dma_transaction_buggy buggy = new();   // COMPILE ERROR
    // dma_transaction       buggy = new();   // ERROR: abstract base

    // ------------------------------------------------------
    // FIXED: legal
    // ------------------------------------------------------
    dma_transaction_fixed fixed = new();

    initial begin
        $display("--- Fixed version ---");
        fixed.execute();
    end

endmodule

      
      
