// ============================================================
// Day 011: FIFO Interface
// File: day011_fifo_if.sv
// Purpose: Bundles FIFO signals, helper tasks/functions, a
//          testbench clocking block, and a tb modport.
// This one type replaces ~10 individual wire ports everywhere.
// ============================================================

`timescale 1ns/1ps

interface fifo_if (input logic clk, input logic rst_n);

    // ----------------------------------------------------------
    // SIGNALS — declared once, used by everyone
    // ----------------------------------------------------------
    logic        wr_en;
    logic        rd_en;
    logic [7:0]  data_in;
    logic [7:0]  data_out;
    logic        full;
    logic        empty;

    // ----------------------------------------------------------
    // INTERFACE METHODS — behavior attached to the signals
    // init(): idle the controls (used from TB after reset)
    // is_write_permitted / is_read_permitted: pure queries
    // ----------------------------------------------------------
    task automatic init();
        wr_en   <= 1'b0;
        rd_en   <= 1'b0;
        data_in <= 8'h0;
    endtask

    function automatic bit is_write_permitted();
        return (wr_en && !full);
    endfunction

    function automatic bit is_read_permitted();
        return (rd_en && !empty);
    endfunction

    // ----------------------------------------------------------
    // CLOCKING BLOCK — TB-side sampling/driving view
    // - input  #1ns: sample inputs 1ns BEFORE posedge clk
    // - output #1ns: drive outputs 1ns AFTER posedge clk
    // Both skews break the zero-time TB/DUT race condition.
    // ----------------------------------------------------------
    clocking tb_cb @(posedge clk);
        default input #1ns output #1ns;
        output wr_en, rd_en, data_in;
        input  data_out, full, empty;
    endclocking

    // ----------------------------------------------------------
    // MODPORT — tb-side direction view.
    // import init: TB may call `if.init()` directly.
    // The clocking block handles the data path.
    // ----------------------------------------------------------
    modport tb (clocking tb_cb, import init);

endinterface : fifo_if 


// ============================================================
// Day 011: APB Interface with reusable write/read tasks
// File: day011_apb_if.sv
// Purpose: Encapsulate the full APB 3-phase handshake in two
//          interface tasks. Any user (TB, driver class,
//          sequence) gets protocol-correct access for free.
// ============================================================

`timescale 1ns/1ps

interface apb_if (input logic pclk, input logic presetn);

    // ----------------------------------------------------------
    // APB bus signals
    // ----------------------------------------------------------
    logic [31:0] paddr;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    // ----------------------------------------------------------
    // MASTER clocking block — posedge aligned, 1ns skew
    // ----------------------------------------------------------
    clocking master_cb @(posedge pclk);
        default input #1ns output #1ns;
        output paddr, psel, penable, pwrite, pwdata;
        input  prdata, pready, pslverr;
    endclocking

   // Import the protocol tasks so they are visible via the modport
    modport master (clocking master_cb, import apb_write, import apb_read);

    // ----------------------------------------------------------
    // APB WRITE
    // SETUP  : PSEL=1, PENABLE=0, drive addr/data/pwrite
    // ACCESS : PENABLE=1
    // WAIT   : hold until PREADY, check PSLVERR
    // IDLE   : PSEL=PENABLE=PWRITE=0
    //
    // FIX vs file version: the wait loop uses !== 1'b1 so an
    // X on PREADY causes the loop to CONTINUE (stall), not
    // exit. Treating X as "not ready" is the safe behavior.
    // ----------------------------------------------------------
    task automatic apb_write(input logic [31:0] addr,
                             input logic [31:0] data);
        // SETUP
        @(master_cb);
        master_cb.paddr   <= addr;
        master_cb.pwrite  <= 1'b1;
        master_cb.psel    <= 1'b1;
        master_cb.penable <= 1'b0;
        master_cb.pwdata  <= data;

        // ACCESS
        @(master_cb);
        master_cb.penable <= 1'b1;

        // WAIT — stall until PREADY is definitively 1
        do begin
            @(master_cb);
        end while (master_cb.pready !== 1'b1);

        // IDLE
        master_cb.psel    <= 1'b0;
        master_cb.penable <= 1'b0;
    endtask

    // ----------------------------------------------------------
    // APB READ — same shape, capture prdata on completion
    // ----------------------------------------------------------
    task automatic apb_read(input  logic [31:0] addr,
                            output logic [31:0] data);
        // SETUP
        @(master_cb);
        master_cb.paddr   <= addr;
        master_cb.pwrite  <= 1'b0;
        master_cb.psel    <= 1'b1;
        master_cb.penable <= 1'b0;

        // ACCESS
        @(master_cb);
        master_cb.penable <= 1'b1;

        // WAIT
        do begin
            @(master_cb);
        end while (master_cb.pready !== 1'b1);

        // CAPTURE
        data = master_cb.prdata;

        // IDLE
        master_cb.psel    <= 1'b0;
        master_cb.penable <= 1'b0;
    endtask

endinterface : apb_if



// ============================================================
// Day 011: Virtual Interface in a Class — two patterns
// File: day011_drivers.sv
// Purpose: Side-by-side comparison:
//   (a) fifo_driver  — drives raw signals via the clocking block
//   (b) apb_driver   — calls the interface's own protocol task
//
// Both use `virtual <if>.<modport>`. This is the UVM pattern.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// (a) LOW-LEVEL DRIVER — drive signals one at a time
// Useful when the class needs to control every wire (e.g.,
// fault injection, protocol violation testing).
// ------------------------------------------------------------
class fifo_driver;

    // Virtual handle — points to a physical fifo_if in tb_top
    virtual fifo_if.tb v_if;

    function new(virtual fifo_if.tb v_if);
        this.v_if = v_if;
    endfunction

    // Drive one synchronous write via the clocking block.
    // Two edges: assert wr_en, then deassert one cycle later.
    task automatic drive_write(input logic [7:0] data);
        @(v_if.tb_cb);
        v_if.tb_cb.wr_en   <= 1'b1;
        v_if.tb_cb.data_in <= data;

        @(v_if.tb_cb);
        v_if.tb_cb.wr_en   <= 1'b0;
    endtask

endclass : fifo_driver


// ------------------------------------------------------------
// (b) HIGH-LEVEL DRIVER — call the interface's protocol task
// Cleaner for ordinary traffic. All APB timing is handled by
// apb_if::apb_write — the class just composes higher-level
// operations.
// ------------------------------------------------------------
class dma_apb_driver;

    virtual apb_if.master apb_vif;

    function new(virtual apb_if.master apb_vif);
        this.apb_vif = apb_vif;
    endfunction

    // Compose one APB write into a DMA register configuration
    task automatic configure_dma_channel(input logic [31:0] ch_addr,
                                         input logic [31:0] config_mask);
        $display("[DMA_DRV] Configuring 0x%0h <- 0x%0h",
                 ch_addr, config_mask);
        apb_vif.apb_write(ch_addr, config_mask);
    endtask

endclass : dma_apb_driver 

      // ============================================================
// Day 011: Top-Level Testbench
// File: day011_tb_top.sv
// Purpose: Instantiate interfaces, wire mocks, build drivers,
//          and run one of each access pattern.
// ============================================================

`timescale 1ns/1ps

module tb_top;

    // ----------------------------------------------------------
    // Clock and reset generation
    // ----------------------------------------------------------
    logic clk;
    logic rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;      // 100 MHz
    end

    initial begin
        rst_n = 0;
        #20 rst_n = 1;
    end

    // ----------------------------------------------------------
    // INSTANTIATE THE INTERFACES (physical, in tb_top only)
    // ----------------------------------------------------------
    fifo_if inst_fifo_if (.clk(clk),   .rst_n(rst_n));
    apb_if  inst_apb_if  (.pclk(clk),  .presetn(rst_n));

    // ----------------------------------------------------------
    // SLAVE MOCKS — keep the demo self-contained. In a real
    // environment, a DUT slave drives these.
    // - pready=1, pslverr=0: no APB wait states, no errors
    // - full=0, empty=1: FIFO starts empty, accepts writes
    // ----------------------------------------------------------
    assign inst_apb_if.pready  = 1'b1;
    assign inst_apb_if.pslverr = 1'b0;
    assign inst_fifo_if.full   = 1'b0;
    assign inst_fifo_if.empty  = 1'b1;

    // ----------------------------------------------------------
    // STIMULUS
    // ----------------------------------------------------------
    initial begin
        fifo_driver     f_drv;
        dma_apb_driver  dma_drv;
        logic [31:0]    readback_data;

        // Hand each driver a virtual handle to the physical interface
        f_drv   = new(inst_fifo_if.tb);
        dma_drv = new(inst_apb_if.master);

        // Wait for reset release, then one aligned edge
        wait (rst_n == 1'b1);
        @(posedge clk);
        $display("--- Starting Interface Verification ---");

        // ------------------------------------------------------
        // FIFO interface: init via modport method + low-level drive
        // ------------------------------------------------------
        inst_fifo_if.init();
        f_drv.drive_write(8'hA5);
        f_drv.drive_write(8'h5A);

        // ------------------------------------------------------
        // APB interface: call its protocol tasks directly
        // ------------------------------------------------------
        $display("[APB_TB] Triggering direct bus writes...");
        inst_apb_if.apb_write(32'h4000_0000, 32'hDEAD_BEEF);
        inst_apb_if.apb_read (32'h4000_0000, readback_data);

        // ------------------------------------------------------
        // High-level driver: config call -> apb_write -> protocol
        // ------------------------------------------------------
        dma_drv.configure_dma_channel(32'h4000_0004, 32'h0000_0001);

        #50;
        $display("--- Interface Verification Completed Successfully ---");
        $finish;
    end

endmodule : tb_top 
        
