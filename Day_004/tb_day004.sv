// ============================================================
// Day 004: Dynamic Arrays — Basic Allocation
// File: day004_dynamic_array_tb.sv
// Purpose: Declare, allocate, fill, display, and size-query
//          a dynamic array.
// ============================================================

`timescale 1ns/1ps

module day004_dynamic_array_tb;

    // ----------------------------------------------------------
    // DECLARATION
    //   int data[];
    //   ^type ^name ^empty brackets = DYNAMIC
    // At this point data.size() == 0; no storage is allocated.
    // ----------------------------------------------------------
    int data[];

    initial begin
        $display("===== DYNAMIC ARRAY =====");

        // ------------------------------------------------------
        // Step 1: ALLOCATE 5 elements
        // `new[N]` allocates N elements, zero-initialized for int.
        // Old contents (none here) are NOT preserved.
        // ------------------------------------------------------
        data = new[5];

        // ------------------------------------------------------
        // Step 2: Initialize via foreach
        // i is auto-bounded 0..4 from the CURRENT size.
        // ------------------------------------------------------
        foreach (data[i]) begin
            data[i] = (i + 1) * 10;    // 10,20,30,40,50
        end

        // ------------------------------------------------------
        // Step 3: Display
        // ------------------------------------------------------
        foreach (data[i]) begin
            $display("data[%0d] = %0d", i, data[i]);
        end

        // ------------------------------------------------------
        // Step 4: Size query
        // .size() returns the runtime element count.
        // ------------------------------------------------------
        $display("Array size = %0d", data.size());   // 5

        $finish;
    end

endmodule 

// ============================================================
// Day 004: Dynamic Array Lifecycle
// File: day004_resize_tb.sv
// Purpose: Walk through the full lifecycle of a dynamic array:
//          allocate -> grow -> shrink -> delete -> reallocate.
// Shows that `new[N](old)` is the ONLY resize that preserves.
// ============================================================

`timescale 1ns/1ps

module day004_resize_tb;

    int data[];

    initial begin

        // ------------------------------------------------------
        // STAGE 1: Allocate 3 and fill
        // ------------------------------------------------------
        data = new[3];
        data[0] = 100;
        data[1] = 200;
        data[2] = 300;

        $display("===== Before resizing =====");
        foreach (data[i]) $display("data[%0d] = %0d", i, data[i]);

        // ------------------------------------------------------
        // STAGE 2: GROW to 5 while PRESERVING
        //   data = new[5](data);
        // - New size = 5
        // - First min(5,3)=3 elements copied verbatim
        // - Elements [3] and [4] are freshly zero-initialized
        // This is the safe resize. `new[5]` alone would WIPE all.
        // ------------------------------------------------------
        data = new[5](data);
        data[3] = 400;    // fill the new slots
        data[4] = 500;

        $display("\n===== After resizing to 5 (preserving) =====");
        foreach (data[i]) $display("data[%0d] = %0d", i, data[i]);

        // ------------------------------------------------------
        // STAGE 3: SHRINK to 2 — TRUNCATES beyond index 1
        // min(2,5)=2 elements are kept; indices 2..4 are LOST.
        // There is no "un-truncate" — the old data is gone.
        // ------------------------------------------------------
        data = new[2](data);

        $display("\n===== After resizing to 2 (truncating) =====");
        foreach (data[i]) $display("data[%0d] = %0d", i, data[i]);

        // ------------------------------------------------------
        // STAGE 4: DELETE — free all memory, size becomes 0
        // .delete() is the only method to release storage.
        // After this, data is an empty array; no access is legal.
        // ------------------------------------------------------
        data.delete();
        $display("\nAfter delete: size = %0d", data.size());

        // ------------------------------------------------------
        // STAGE 5: REALLOCATE — a fresh array, old contents gone
        // ------------------------------------------------------
        data = new[3];
        foreach (data[i]) data[i] = (i + 1) * 50;

        $display("After reallocation:");
        foreach (data[i]) $display("data[%0d] = %0d", i, data[i]);

        $finish;
    end

endmodule


// ============================================================
// Day 004: Dynamic Array in a Transaction Class
// File: day004_packet_tb.sv
// Purpose: First class with a variable-length payload array.
//          Models the shape of every future UVM transaction.
// ============================================================

`timescale 1ns/1ps

class packet;

    int           packet_id;
    byte unsigned payload[];      // dynamic payload, size set per object

    // ----------------------------------------------------------
    // CONSTRUCTOR
    // - Called once per `new(id, length)` invocation
    // - Allocates a FRESH payload per object; no shared storage
    // - Fills with a predictable pattern for easy debugging
    // ----------------------------------------------------------
    function new(int id, int length);
        packet_id = id;
        payload   = new[length];           // per-object allocation
        foreach (payload[i]) begin
            payload[i] = i + 8'h10;        // 0x10, 0x11, ...
        end
    endfunction

    // ----------------------------------------------------------
    // DISPLAY
    // - Uses .size() (not a cached constant) so it always
    //   reflects the object's actual payload at call time.
    // - %02h guarantees 2 hex digits with leading zero.
    // ----------------------------------------------------------
    function void display();
        $display("Packet ID = %0d", packet_id);
        $display("Payload size = %0d", payload.size());
        foreach (payload[i]) begin
            $display("Payload[%0d] = %02h", i, payload[i]);
        end
    endfunction

endclass

module day004_packet_tb;

    packet pkt;

    initial begin
        // Construct with id=1, length=5
        pkt = new(1, 5);
        pkt.display();
        $finish;
    end

endmodule
