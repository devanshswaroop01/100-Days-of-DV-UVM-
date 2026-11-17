// ============================================================
// Day 010: Pure Functions — zero-time, no side effects
// File: day010_ex1_functions.sv
// Purpose: Four functions, no delays, composable in expressions.
// ============================================================

`timescale 1ns/1ps

module day010_ex1_functions;

    // ----------------------------------------------------------
    // Functions MUST execute in zero time — no #, @, or wait.
    // `automatic`: per-call locals (defensive; recommended).
    // ----------------------------------------------------------
    function automatic logic [31:0] add(input logic [31:0] a, b);
        return a + b;
    endfunction

    function automatic logic [31:0] sub(input logic [31:0] a, b);
        return a - b;
    endfunction

    // ----------------------------------------------------------
    // Widened return type: a*b for two 32-bit operands can need
    // up to 64 bits. Returning [31:0] would silently truncate.
    // ----------------------------------------------------------
    function automatic logic [63:0] mult(input logic [31:0] a, b);
        return a * b;
    endfunction

    // ----------------------------------------------------------
    // Reduction XOR: ^data returns 1 if odd number of 1s.
    // ----------------------------------------------------------
    function automatic logic xor_parity(input logic [31:0] data);
        return ^data;
    endfunction

    initial begin
        logic [31:0] x = 32'd50;
        logic [31:0] y = 32'd10;

        $display("===== EXERCISE 1: ARITHMETIC FUNCTIONS =====");
        $display("Inputs: X = %0d, Y = %0d", x, y);
        $display("Addition       = %0d", add(x, y));
        $display("Subtraction    = %0d", sub(x, y));
        $display("Multiplication = %0d", mult(x, y));
        $display("XOR Parity of X= %0b", xor_parity(x));
    end

endmodule

// ============================================================
// Day 010: input / output / inout directions
// File: day010_ex2_directions.sv
// Purpose: Show that `input` is a read-only copy, `output` is
//          a copy out, and `inout` is read-then-write-back.
// ============================================================

`timescale 1ns/1ps

module day010_ex2_directions;

    task automatic control_signals(
        input  logic       in_a, in_b,     // copies in
        output logic       out_y,          // copy out
        inout  logic [3:0] bidir_bus       // read AND write
    );
        // Inputs are read-only copies at invocation time
        out_y = in_a & in_b;

        // Inout: read the current bus value, add 1, write back
        bidir_bus = bidir_bus + 4'd1;
    endtask

    initial begin
        logic a = 1, b = 1, y = 0;
        logic [3:0] bus = 4'b1010;

        $display("===== EXERCISE 2: ARGUMENT DIRECTIONS =====");
        $display("Before: Y = %0b, Bus = %0b", y, bus);

        control_signals(a, b, y, bus);

        $display("After:  Y = %0b, Bus = %0b (bus updated via inout)",
                 y, bus);
    end

endmodule


// ============================================================
// Day 010: input (pass-by-value) vs ref (pass-by-reference)
// File: day010_ex3_passing.sv
// Purpose: The classic. `input` gets a copy; `ref` aliases
//          the caller's variable so writes are visible.
// ============================================================

`timescale 1ns/1ps

module day010_ex3_passing;

    // ----------------------------------------------------------
    // Pass by value: a COPY of `val` lives on the task's stack.
    // Modifying it has NO effect on the caller.
    // ----------------------------------------------------------
    task automatic modify_by_value(input int val);
        val = val + 100;
    endtask

    // ----------------------------------------------------------
    // Pass by reference: `val` aliases the caller's storage.
    // Modifying it DIRECTLY updates the caller's variable.
    // ----------------------------------------------------------
    task automatic modify_by_ref(ref int val);
        val = val + 100;
    endtask

    initial begin
        int local_var = 50;

        $display("===== EXERCISE 3: PASS BY VALUE VS REFERENCE =====");

        modify_by_value(local_var);
        $display("After modify_by_value: %0d (unchanged — copy)", local_var);

        modify_by_ref(local_var);
        $display("After modify_by_ref:   %0d (updated — reference)", local_var);
    end

endmodule


// ============================================================
// Day 010: static vs automatic lifetimes
// File: day010_ex4_lifetimes.sv
// Purpose: Prove the storage lifetime difference. STATIC keeps
//          one copy across calls; AUTOMATIC makes a fresh copy
//          per call.
// NOTE: in a module, tasks are STATIC by default. Declaring
//       `automatic` gives you per-call locals — always do this
//       unless you specifically want a persistent variable.
// ============================================================

`timescale 1ns/1ps

module day010_ex4_lifetimes;

    // ----------------------------------------------------------
    // STATIC task — `count` is one storage location, allocated
    // once at time 0. Three calls yield 1, 2, 3.
    //
    // PORTABILITY NOTE: whether `int count = 0;` inside a static
    // task re-initializes each call is TOOL-DEPENDENT in classic
    // Verilog. Declaring the variable explicitly `static` makes
    // the persistent behavior spec-guaranteed.
    // ----------------------------------------------------------
    task static_counter();
        static int count = 0;     // ONE copy, init once at t=0
        count++;
        $display("  Static call:    count = %0d", count);
    endtask

    // ----------------------------------------------------------
    // AUTOMATIC task — `count` is allocated per call, initialized
    // to 0 each time. Three calls yield 1, 1, 1.
    // ----------------------------------------------------------
    task automatic automatic_counter();
        int count = 0;            // fresh copy each call
        count++;
        $display("  Automatic call: count = %0d", count);
    endtask

    initial begin
        $display("===== EXERCISE 4: STATIC VS AUTOMATIC LIFETIMES =====");

        $display("Static task, 3 calls:");
        static_counter();
        static_counter();
        static_counter();

        $display("Automatic task, 3 calls:");
        automatic_counter();
        automatic_counter();
        automatic_counter();
    end

endmodule

// ============================================================
// Day 010: DMA Transaction Class — functions + time-consuming task
// File: day010_ex5_dma_class.sv
// Purpose: The smallest possible "UVM-transaction-shaped" object:
//          - constructor (function new)
//          - zero-time helpers (functions)
//          - time-consuming behavior (task)
// This is the pattern every UVM sequence_item follows.
// ============================================================

`timescale 1ns/1ps

class dma_transaction;

    rand bit [2:0]  channel_id;
    rand bit [31:0] src_addr;
    rand bit [31:0] dst_addr;
    rand bit [15:0] transfer_count;

    // ----------------------------------------------------------
    // CONSTRUCTOR (function, zero-time)
    // `this.x = x` disambiguates the member from the arg.
    // ----------------------------------------------------------
    function new(bit [2:0]  id,
                 bit [31:0] src,
                 bit [31:0] dst,
                 bit [15:0] cnt);
        this.channel_id     = id;
        this.src_addr       = src;
        this.dst_addr       = dst;
        this.transfer_count = cnt;
    endfunction

    // ----------------------------------------------------------
    // Zero-time helper — 4 bytes per transfer count unit
    // ----------------------------------------------------------
    function int get_transfer_bytes();
        return this.transfer_count * 4;
    endfunction

    // ----------------------------------------------------------
    // Zero-time display helper
    // ----------------------------------------------------------
    function void display();
        $display("[DMA TX] Ch:%0d | Src:0x%8h | Dst:0x%8h | Count:%0d (%0d Bytes)",
                 channel_id, src_addr, dst_addr,
                 transfer_count, get_transfer_bytes());
    endfunction

    // ----------------------------------------------------------
    // Time-consuming task — models a #50 streaming delay.
    // This MUST be a task: a function cannot consume time.
    // ----------------------------------------------------------
    task wait_for_completion();
        $display("[DMA TX] Starting simulated streaming...");
        #50;     // data-streaming time
        $display("[DMA TX] Transfer complete on channel %0d.",
                 channel_id);
    endtask

endclass


module day010_ex5_dma_class;
    initial begin
        dma_transaction tx;

        $display("===== EXERCISE 5: DMA TRANSACTION CLASS =====");

        tx = new(3'd2, 32'h1000_0000, 32'h2000_0000, 16'd50);
        tx.display();
        tx.wait_for_completion();
    end
endmodule

// ============================================================
// Day 010: APB Master Write Driver — the final goal
// File: day010_ex6_apb_driver.sv
// Purpose: A real protocol driver, built from one task that
//          walks SETUP -> ACCESS -> WAIT -> IDLE, consuming
//          multiple clock edges via @(posedge pclk).
//
// WHY A TASK: each @(posedge pclk) is a simulation-time event.
// A function cannot contain these — only tasks can drive a bus.
//
// NOTE ON INTERFACES: production UVM uses an `interface` to
// bundle the bus signals (as Exercise 2 showed). We inline the
// signals here for a self-contained demo.
// ============================================================

`timescale 1ns/1ps

module day010_ex6_apb_driver;

    // ----------------------------------------------------------
    // APB bus signals (would normally live in an interface)
    // ----------------------------------------------------------
    logic        pclk;
    logic        presetn;
    logic [31:0] paddr;
    logic        pwrite;
    logic        psel;
    logic        penable;
    logic [31:0] pwdata;
    logic        pready;
    logic        pslverr;

    // 100 MHz clock
    initial pclk = 0;
    always #5 pclk = ~pclk;

    // ----------------------------------------------------------
    // APB WRITE TASK
    // Phases:
    //   SETUP    - assert PSEL, PADDR, PWDATA, PWRITE; PENABLE=0
    //   ACCESS   - assert PENABLE on next clock
    //   WAIT     - loop until PREADY; check PSLVERR on completion
    //   IDLE     - deassert PSEL/PENABLE/PWRITE
    // ----------------------------------------------------------
    task automatic apb_write(input logic [31:0] addr,
                             input logic [31:0] data);
        $display("[APB][%0t] --- Write begin ---", $time);

        // SETUP phase — sample addr/data on rising edge
        @(posedge pclk);
        paddr  <= addr;
        pwdata <= data;
        pwrite <= 1'b1;
        psel   <= 1'b1;
        penable <= 1'b0;
        $display("[APB][%0t] SETUP: PADDR=0x%8h PWDATA=0x%8h",
                 $time, addr, data);

        // ACCESS phase — assert PENABLE on next rising edge
        @(posedge pclk);
        penable <= 1'b1;
        $display("[APB][%0t] ACCESS: PENABLE=1", $time);

        // WAIT-STATE loop — sample PREADY every clock
        forever begin
            @(posedge pclk);
            if (pready === 1'b1) begin
                if (pslverr === 1'b1)
                    $display("[APB][%0t] ERROR: PSLVERR asserted", $time);
                else
                    $display("[APB][%0t] SUCCESS: write captured", $time);
                break;
            end
            $display("[APB][%0t] WAIT: PREADY=0, stalling", $time);
        end

        // IDLE — deassert
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    endtask

    // ----------------------------------------------------------
    // SIMPLE SLAVE EMULATOR — injects two wait states, then ready
    // ----------------------------------------------------------
    initial begin
        pready  = 1'b0;
        pslverr = 1'b0;
        #25; pready = 1'b0;    // wait state 1
        #10; pready = 1'b0;    // wait state 2
        #10; pready = 1'b1;    // ready
    end

    // ----------------------------------------------------------
    // MAIN STIMULUS
    // ----------------------------------------------------------
    initial begin
        #2 presetn = 0;
        #5 presetn = 1;

        $display("===== EXERCISE 6: APB MASTER WRITE DRIVER =====");
        apb_write(32'h0000_A0F0, 32'hDEAD_BEEF);

        #20;
        $finish;
    end

endmodule


