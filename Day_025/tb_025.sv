// ============================================================
// Day 025: Encapsulation capstone — validated getters/setters
// File: day025_dma_encapsulation.sv
// Purpose: Every field is hidden. Every write goes through a
//          validating setter. Every read goes through a getter.
//          Invalid writes are rejected AND leave state unchanged.
//
// Design note: fields are `protected`, not `local`, because a
// subclass of dma_transaction should be able to access them.
// `local` would block inheritance. (Day 022's `extends` extends
// the fields but not the `local` protection.)
// ============================================================

`timescale 1ns/1ps

class dma_transaction;

    // ------------------------------------------------------
    // PROTECTED FIELDS — hidden from external code, visible
    // to subclasses
    // ------------------------------------------------------
    protected int unsigned transaction_id;
    protected int unsigned channel_id;
    protected bit [31:0]   address;
    protected int unsigned transfer_length;

    // ------------------------------------------------------
    // CONSTRUCTOR
    // Uses setters for all validation — invalid args are
    // rejected, and the object retains defaults.
    // ------------------------------------------------------
    function new(
        int unsigned id   = 0,
        int unsigned ch   = 0,
        bit [31:0]   addr = 0,
        int unsigned len  = 1
    );
        transaction_id = id;

        if (!set_channel(ch))
            $display("WARNING: default channel selected");
        if (!set_address(addr))
            $display("WARNING: default address selected");
        if (!set_length(len))
            $display("WARNING: default length selected");
    endfunction

    // ======================================================
    // VALIDATING SETTERS
    // Each returns 1 on success, 0 on rejection.
    // Rejection leaves the previous value unchanged.
    // ======================================================

    // ------------------------------------------------------
    // CHANNEL: valid range 0..3
    // ------------------------------------------------------
    function bit set_channel(int unsigned ch);
        if (ch <= 3) begin
            channel_id = ch;
            return 1;
        end
        $display("ERROR: invalid channel %0d (valid: 0..3)", ch);
        return 0;
    endfunction

    // ------------------------------------------------------
    // ADDRESS: must be 4-byte aligned (low 2 bits zero)
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
    // LENGTH: valid range 1..1024
    // ------------------------------------------------------
    function bit set_length(int unsigned len);
        if (len >= 1 && len <= 1024) begin
            transfer_length = len;
            return 1;
        end
        $display("ERROR: length %0d out of range (1..1024)", len);
        return 0;
    endfunction

    // ======================================================
    // GETTERS — read-only access to hidden fields
    // ======================================================
    function int unsigned get_id();      return transaction_id; endfunction
    function int unsigned get_channel(); return channel_id;     endfunction
    function bit [31:0]   get_address(); return address;        endfunction
    function int unsigned get_length();  return transfer_length;endfunction

    // ------------------------------------------------------
    // DISPLAY
    // ------------------------------------------------------
    function void display();
        $display("----------------------------------");
        $display("Transaction ID = %0d", transaction_id);
        $display("Channel ID     = %0d", channel_id);
        $display("Address        = 0x%0h", address);
        $display("Length         = %0d", transfer_length);
        $display("----------------------------------");
    endfunction

endclass


// ============================================================
// TESTBENCH
// ============================================================
module day025_dma_encapsulation_tb;

    dma_transaction dma;

    initial begin

        // ------------------------------------------------------
        // 1. Construct with valid args
        // ------------------------------------------------------
        dma = new(100, 2, 32'h1000, 16);
        $display("\n===== INITIAL =====");
        dma.display();

        // ------------------------------------------------------
        // 2. Valid updates — all succeed
        // ------------------------------------------------------
        $display("\n===== VALID UPDATES =====");
        if (!dma.set_channel(3))   $error("set_channel(3) rejected");
        if (!dma.set_address(32'h2000)) $error("set_address rejected");
        if (!dma.set_length(64))    $error("set_length rejected");
        dma.display();

        // ------------------------------------------------------
        // 3. Invalid updates — all rejected, old values retained
        // ------------------------------------------------------
        $display("\n===== INVALID UPDATES =====");
        if (dma.set_channel(5))   $error("channel 5 accepted!");
        if (dma.set_address(32'h2003)) $error("misaligned addr accepted!");
        if (dma.set_length(0))    $error("length 0 accepted!");

        // ------------------------------------------------------
        // 4. Prove the failed updates left state unchanged
        // ------------------------------------------------------
        $display("\n===== FINAL (state unchanged from valid updates) =====");
        dma.display();
        $display("Channel via getter = %0d", dma.get_channel());
        $display("Address via getter = 0x%0h", dma.get_address());
    end

endmodule

// ============================================================
// Day 025: Access modifier comparison
// File: day025_access_modifiers.sv
// Purpose: The one place in the file where public / protected
//          / local are compared side by side. Proves the
//          compile-time visibility rules.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// PARENT — three access levels
// ------------------------------------------------------------
class parent_class;
    int 		  public_val;
    protected int protected_val;
    local     int local_val;

    function new();
        public_val    = 10;
        protected_val = 20;
        local_val     = 30;
    endfunction

    // ------------------------------------------------------
    // Public getter for the local field — the only way out
    // ------------------------------------------------------
    function int get_local_val();
        return local_val;
    endfunction
endclass


// ------------------------------------------------------------
// CHILD — access check from a subclass
// ------------------------------------------------------------
class child_class extends parent_class;

    function void test_access();
        // LEGAL: public is globally visible
        this.public_val = 11;

        // LEGAL: protected is visible in subclasses
        this.protected_val = 21;

        // ILLEGAL (compile error if uncommented):
        //   this.local_val = 31;

        $display("Child access: public=%0d, protected=%0d",
                 public_val, protected_val);

        // Even a subclass must go through the getter for local:
        $display("Child local via getter: %0d", get_local_val());
    endfunction

endclass


// ============================================================
// TESTBENCH
// ============================================================
module day025_access_modifiers_tb;

    child_class child;

    initial begin
        child = new();

        $display("\n=== Subclass access ===");
        child.test_access();

        $display("\n=== External access ===");
        // LEGAL: public field accessible from anywhere
        child.public_val = 100;
        $display("public_val = %0d", child.public_val);

        // ILLEGAL (compile error if uncommented):
        //   child.protected_val = 200;
        //   child.local_val     = 300;

        $display("protected_val via getter: (no getter — would need one)");
        $display("local_val via getter: %0d", child.get_local_val());
    end

endmodule

// ============================================================
// Day 025: The hybrid pattern — local rand + constraints
// File: day025_rand_encapsulation.sv
// Purpose: The UVM-transaction pattern. Fields are `local`
//          AND `rand`, with constraints inside the class.
//          `randomize()` produces guaranteed-valid values.
//          External code can only read via getters.
// ============================================================

`timescale 1ns/1ps

class randomized_dma_tx;

    // ------------------------------------------------------
    // `local rand` — the randomizer can set them, external
    // code cannot. Best of both worlds.
    // ------------------------------------------------------
    local rand int unsigned channel_id;
    local rand bit [31:0]   address;
    local rand int unsigned length;

    // ------------------------------------------------------
    // CONSTRAINTS — the validation rules, enforced automatically
    // ------------------------------------------------------
    constraint c_dma_rules {
        channel_id inside {[0:3]};
        address[1:0] == 2'b00;                    // 4-byte aligned
        address inside {[32'h1000 : 32'h2FFF]};   // bounded range
        length inside {[1:128]};
    }

    // ------------------------------------------------------
    // GETTERS — the only way to read the fields externally
    // ------------------------------------------------------
    function int unsigned get_channel(); return channel_id; endfunction
    function bit [31:0]   get_address(); return address;    endfunction
    function int unsigned get_length();  return length;     endfunction

    // ------------------------------------------------------
    // Print via getters (proves external access works)
    // ------------------------------------------------------
    function void print_profile(int iter);
        $display("Iter %2d -> Ch=%0d Addr=0x%08h Len=%0d",
                 iter, channel_id, address, length);
    endfunction

endclass


// ============================================================
// TESTBENCH
// ============================================================
module day025_rand_encapsulation_tb;

    randomized_dma_tx tx;

    initial begin
        tx = new();

        $display("\n=== 20 constrained randomization iterations ===");

        for (int i = 1; i <= 20; i++) begin
            // --------------------------------------------------
            // randomize() enforces the constraints
            // A failure (return 0) means the constraints are
            // unsatisfiable — treat as a bug.
            // --------------------------------------------------
            if (!tx.randomize()) begin
                $error("randomize() failed at iteration %0d", i);
                break;
            end
            tx.print_profile(i);

            // --------------------------------------------------
            // Prove external write is ILLEGAL:
            // Uncomment to see the compile error:
            //   tx.channel_id = 5;
            // --------------------------------------------------
        end

        // ------------------------------------------------------
        // Read via getters after randomization
        // ------------------------------------------------------
        $display("\nFinal via getters: ch=%0d addr=0x%08h len=%0d",
                 tx.get_channel(), tx.get_address(), tx.get_length());
    end

endmodule
