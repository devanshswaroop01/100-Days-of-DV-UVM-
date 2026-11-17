// ============================================================
// Day 008: Packed Struct — DMA Channel Description
// File: day008_dma_struct_tb.sv
// Purpose: Demonstrate packed struct, array-of-structs, literal
//          init, bit-select, cast-to-vector, and contrast with
//          the UNPACKED form (same fields, different memory).
// ============================================================

`timescale 1ns/1ps

module day008_dma_struct_tb;

    // ----------------------------------------------------------
    // PACKED STRUCT — fields are contiguous bits
    // Total width = 32 + 32 + 16 + 1 + 1 = 82 bits
    // Field order matters: source_address occupies bits [81:50].
    // ----------------------------------------------------------
    typedef struct packed {
        logic [31:0] source_address;
        logic [31:0] destination_address;
        logic [15:0] transfer_count;
        logic        channel_enable;
        logic        transfer_direction;
    } dma_channel_t;

    // ----------------------------------------------------------
    // ARRAY OF PACKED STRUCTS — 4 channels
    // ----------------------------------------------------------
    dma_channel_t channels[0:3];

    // ----------------------------------------------------------
    // COMPANION UNPACKED STRUCT — same fields, separate storage
    // No bit-select, no cast to vector — but mutable per-field
    // and passable to functions/classes as a unit.
    // ----------------------------------------------------------
    typedef struct {
        logic [31:0] source_address;
        logic [31:0] destination_address;
        logic [15:0] transfer_count;
        logic        channel_enable;
        logic        transfer_direction;
    } dma_channel_u_t;

    dma_channel_u_t unpacked_ch;

    // ----------------------------------------------------------
    // PACKED 82-bit view for cast demo
    // ----------------------------------------------------------
    logic [81:0] packed_view;

    initial begin
        $display("===== DMA CHANNEL MODEL =====");

        // ------------------------------------------------------
        // POSITIONAL INITIALIZATION (concise, fragile)
        // Field order must match the typedef exactly.
        // ------------------------------------------------------
        channels[0] = '{32'h1000, 32'h2000,
                        16'd256, 1'b1, 1'b0};

        // ------------------------------------------------------
        // NAMED INITIALIZATION (preferred, robust)
        // Immune to field reordering in the typedef.
        // ------------------------------------------------------
        channels[1] = '{
            source_address:      32'h3000,
            destination_address: 32'h4000,
            transfer_count:      16'd512,
            channel_enable:      1'b1,
            transfer_direction:  1'b1 };

        // ------------------------------------------------------
        // DISPLAY each channel via .field access
        // ------------------------------------------------------
        foreach (channels[i]) begin
            $display("Channel %0d", i);
            $display("  Source      = %h", channels[i].source_address);
            $display("  Destination = %h", channels[i].destination_address);
            $display("  Count       = %0d", channels[i].transfer_count);
            $display("  Enable      = %b", channels[i].channel_enable);
            $display("  Direction   = %b", channels[i].transfer_direction);
        end

        // ------------------------------------------------------
        // PACKED-ONLY POWERS — the whole reason `packed` matters
        // (a) bit-select into the struct (channel 0, bits [15:0])
        // (b) cast whole struct to a flat 82-bit vector
        // ------------------------------------------------------
        $display("\n--- Packed-struct exclusive features ---");
        $display("channels[0][15:0]     = 0x%h", channels[0][15:0]);
        packed_view = channels[0];
        $display("Cast to 82-bit vector = 0x%h", packed_view);

        // ------------------------------------------------------
        // UNPACKED STRUCT — field access works identically
        // BUT: bit-select and cast-to-vector are ILLEGAL.
        // Uncomment either line below to see the compile error:
        //   $display("%h", unpacked_ch[15:0]);
        //   packed_view = unpacked_ch;
        // ------------------------------------------------------
        unpacked_ch = '{
            source_address:      32'hAAAA,
            destination_address: 32'hBBBB,
            transfer_count:      16'd16,
            channel_enable:      1'b1,
            transfer_direction:  1'b0};
      
        $display("\n--- Unpacked struct (.field still works) ---");
        $display("unpacked_ch.source_address      = 0x%h",
                 unpacked_ch.source_address);
        $display("unpacked_ch.destination_address = 0x%h",
                 unpacked_ch.destination_address);

        $finish;
    end

endmodule 


// ============================================================
// Day 008: Packed Union — Multi-View Instruction Decoder
// File: day008_instruction_tb.sv
// Purpose: One 32-bit word, two views. Write via raw, read via
//          fields (decode). Write via fields, read via raw
//          (encode). No shift/mask code anywhere.
// ============================================================

`timescale 1ns/1ps

module day008_instruction_tb;

    // ----------------------------------------------------------
    // PACKED STRUCT — field layout matches RISC-V I-type exactly
    // Field order (top to bottom) = MSB to LSB of the 32-bit word
    // ----------------------------------------------------------
    typedef struct packed {
        logic [11:0] imm;      // bits [31:20]
        logic [4:0]  rs1;      // bits [19:15]
        logic [2:0]  funct3;   // bits [14:12]
        logic [4:0]  rd;       // bits [11:7]
        logic [6:0]  opcode;   // bits [6:0]
    } instr_fields_s;

    // ----------------------------------------------------------
    // PACKED UNION — two VIEWS over the same 32 bits
    // Both members are 32 bits wide → no padding, no mismatch.
    // ----------------------------------------------------------
    typedef union packed {
        logic [31:0]   raw;       // view #1: flat 32-bit word
        instr_fields_s fields;    // view #2: named subfields
    } instruction_u;

    instruction_u my_instruction;

    initial begin
        $display("===== PACKED UNION INSTRUCTION DECODER =====");

        // ------------------------------------------------------
        // SCENARIO A — DECODE: write raw, read fields
        // Encoded "addi x10, x5, 100"
        //   imm=100, rs1=5, funct3=0, rd=10, opcode=0x13
        // No explicit shift/mask needed — union does it.
        // ------------------------------------------------------
        my_instruction.raw = 32'h06428513;
        $display("\n[Write raw] Loaded: 0x%8h", my_instruction.raw);
        $display("--- Decoded fields ---");
        $display("Opcode (bits [6:0])           = 7'b%7b (0x%0h)",
                 my_instruction.fields.opcode,
                 my_instruction.fields.opcode);
        $display("Destination Reg (bits [11:7]) = 5'd%0d",
                 my_instruction.fields.rd);
        $display("Function 3 (bits [14:12])     = 3'b%3b",
                 my_instruction.fields.funct3);
        $display("Source Reg 1 (bits [19:15])   = 5'd%0d",
                 my_instruction.fields.rs1);
        $display("Immediate (bits [31:20])      = 12'd%0d (0x%0h)",
                 my_instruction.fields.imm,
                 my_instruction.fields.imm);

        // ------------------------------------------------------
        // SCENARIO B — ENCODE: write fields, read raw
        // Set fields to an "addi x15, x2, 45" and verify the
        // resulting raw word matches the expected encoding.
        // ------------------------------------------------------
        $display("\n[Write fields] rd=15, rs1=2, imm=45 ...");
        my_instruction.fields.opcode  = 7'h13;
        my_instruction.fields.rd      = 5'd15;
        my_instruction.fields.funct3  = 3'b000;
        my_instruction.fields.rs1     = 5'd2;
        my_instruction.fields.imm     = 12'd45;

        $display("--- Raw verification ---");
        $display("Resulting raw = 0x%8h", my_instruction.raw);
        $display("Binary        = %32b", my_instruction.raw);

        $finish;
    end

endmodule
