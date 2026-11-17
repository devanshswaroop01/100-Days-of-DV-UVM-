 // ============================================================
// Day 003: Static Arrays — Basic Operations
// File: day003_static_array_tb.sv
// Purpose: Declare, fill, modify, and query a fixed-size array.
// ============================================================

`timescale 1ns/1ps

module day003_static_array_tb;

    // ----------------------------------------------------------
    // STATIC ARRAY DECLARATION
    //   logic [7:0]  data [0:7];
    //   ^packed(8bits)  ^name  ^unpacked (8 elements)
    // This is a "vector array" — an array of 8-bit vectors.
    // Size (8) is fixed at compile time -> it's a STATIC array.
    // ----------------------------------------------------------
    logic [7:0] data [0:7];
    integer i;                     // loop counter (signed 32-bit)

    initial begin
        $display("===== STATIC ARRAY =====");

        // ------------------------------------------------------
        // Fill via explicit index
        // data[i] = i * 10  -> 0,10,20,...,70
        // Note: i*10 is 32-bit int; assignment auto-truncates
        // to 8 bits. Since max 70 < 255, no loss here.
        // ------------------------------------------------------
        for (i = 0; i < 8; i++) begin
            data[i] = i * 10;
        end

        // ------------------------------------------------------
        // foreach() iterates the array's OWN bounds.
        // No need to know 0:7 — derived from declaration.
        // `i` here shadows the outer integer i (same var, reused).
        // ------------------------------------------------------
        foreach (data[i]) begin
            $display("data[%0d] = %0d", i, data[i]);
        end

        // ------------------------------------------------------
        // Modify one element — arrays are mutable per-element
        // ------------------------------------------------------
        data[3] = 8'hFF;
        $display("Modified data[3] = %h", data[3]);   // ff

        // ------------------------------------------------------
        // $size() — number of ELEMENTS (unpacked dim), not bits.
        // $size(data) = 8 (elements), not 64 (bits).
        // Use $bits(data) if you want total bit count.
        // ------------------------------------------------------
        $display("Array size = %0d", $size(data));    // 8
        $finish;
    end

endmodule 


// ============================================================
// Day 003: Packed vs Unpacked Arrays
// File: day003_packed_unpacked_tb.sv
// Purpose: Show memory layout, $bits() difference, and access
//          syntax for packed (bit-select) vs unpacked (index).
// ============================================================

`timescale 1ns/1ps

module day003_packed_unpacked_tb;

    // ----------------------------------------------------------
    // PACKED ARRAY
    // - [7:0] is to the LEFT of the name -> packed
    // - Stored as ONE 8-bit contiguous word
    // - Can be bit-sliced: packed_data[3:0] is legal
    // ----------------------------------------------------------
    logic [7:0] packed_data;

    // ----------------------------------------------------------
    // UNPACKED ARRAY
    // - [0:3] is to the RIGHT of the name -> unpacked
    // - 4 independent elements, each 8 bits
    // - packed_data[3:0] equivalent does NOT exist for this
    //   array — you access elements, not bit-ranges of the whole.
    // ----------------------------------------------------------
    logic [7:0] unpacked_data [0:3];

    initial begin
        // ------------------------------------------------------
        // Packed demo
        // ------------------------------------------------------
        $display("===== PACKED ARRAY =====");
        packed_data = 8'b10101010;
        $display("Packed data = %b", packed_data);
        $display("Packed width = %0d bits", $bits(packed_data));  // 8

        // ------------------------------------------------------
        // Unpacked demo — each element written individually
        // ------------------------------------------------------
        $display("\n===== UNPACKED ARRAY =====");
        unpacked_data[0] = 8'h11;
        unpacked_data[1] = 8'h22;
        unpacked_data[2] = 8'h33;
        unpacked_data[3] = 8'h44;

        // foreach over unpacked dim — idx auto-bounded 0..3
        foreach (unpacked_data[idx]) begin
            $display("Element[%0d] = 0x%0h", idx, unpacked_data[idx]);
        end

        // ------------------------------------------------------
        // $bits() on unpacked array = element_width * num_elements
        // = 8 bits * 4 elements = 32 bits total.
        // This is the "total storage", not the "per-element width".
        // ------------------------------------------------------
        $display("Total unpacked bits = %0d bits", $bits(unpacked_data)); // 32

        $finish;
    end

endmodule

// ============================================================
// Day 003: 2D Unpacked Arrays
// File: day003_multidimensional_tb.sv
// Purpose: Declare a 4x4 memory, fill with computed values,
//          dump every element, and inspect total bit count.
// ============================================================

`timescale 1ns/1ps

module day003_multidimensional_tb;

    // ----------------------------------------------------------
    // 4x4 array of 8-bit elements.
    // Dimensions are UNPACKED (to the right of the name).
    // Total storage = 4*4*8 = 128 bits.
    // Element access requires BOTH indices: memory[i][j]
    // ----------------------------------------------------------
    logic [7:0] memory [0:3][0:3];
    integer i, j;

    initial begin
        $display("===== 2D ARRAY =====");

        // ------------------------------------------------------
        // foreach with two indices iterates all (i,j) pairs.
        // Order is row-major: (0,0),(0,1),...,(3,3)
        // Value chosen: (i*4)+j  -> 0..15, unique per cell.
        // ------------------------------------------------------
        foreach (memory[i,j]) begin
            memory[i][j] = (i * 4) + j;
        end

        // ------------------------------------------------------
        // Dump every cell to confirm fill
        // ------------------------------------------------------
        foreach (memory[i,j]) begin
            $display("memory[%0d][%0d] = %0d", i, j, memory[i][j]);
        end

        // ------------------------------------------------------
        // $bits on multi-dim unpacked = product of all dims * width
        // = 4 * 4 * 8 = 128 bits
        // ------------------------------------------------------
        $display("Total bits = %0d", $bits(memory));  // 128
        $finish;
    end

endmodule 

// ============================================================
// Day 003: Register File DUT
// File: day003_register_file.sv
// Purpose: 8 x 8-bit register file with sync write + async read.
// Demonstrates: unpacked array as storage, array assignment
// pattern for reset, always_ff vs always_comb.
// ============================================================

`timescale 1ns/1ps

module register_file (
    input  logic       clk,
    input  logic       rst_n,      // active-low async reset
    input  logic       wr_en,
    input  logic [2:0] wr_addr,    // 3 bits -> 8 registers
    input  logic [2:0] rd_addr,
    input  logic [7:0] wr_data,
    output logic [7:0] rd_data
);

    // ----------------------------------------------------------
    // TODO 1: Storage — unpacked array, 8 x 8-bit registers
    // Unpacked (not packed) because each element is written
    // independently by the clocked block — a memory, not a vector.
    // ----------------------------------------------------------
    logic [7:0] registers [0:7];

    // ----------------------------------------------------------
    // TODO 2: Synchronous write, ASYNC active-low reset
    // - always_ff: SV construct that asserts the block models
    //   sequential (flip-flop) behavior. Tool warns if you
    //   accidentally create a latch or race.
    // - `registers <= '{default: 8'h00};` uses an assignment
    //   pattern to clear EVERY element in one line.
    // - else-if ensures write only when enabled.
    // ----------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            registers <= '{default: 8'h00};
        end
        else if (wr_en) begin
            registers[wr_addr] <= wr_data;
        end
    end

    // ----------------------------------------------------------
    // TODO 3: Combinational (async) read
    // - always_comb: intent-revealing; tools check you don't
    //   infer latches or create multiple drivers.
    // - Read is a pure mux of the array -> no clock needed.
    // ----------------------------------------------------------
    always_comb begin
        rd_data = registers[rd_addr];
    end

endmodule 
