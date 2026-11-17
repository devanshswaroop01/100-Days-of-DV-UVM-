// ============================================================
// Day 014: FIFO interface — DRIVER / MONITOR / DUT views
// File: day014_fifo_if.sv
// Purpose: Foundation. Three modports, one interface. Same
//          structure as Day 012, now the context for learning
//          virtual-interface passing into UVM.
// ============================================================

`timescale 1ns/1ps

interface fifo_if (input logic clk, input logic rst_n);

    logic        wr_en;
    logic        rd_en;
    logic [7:0]  data_in;
    logic [7:0]  data_out;
    logic        full;
    logic        empty;

    // ----------------------------------------------------------
    // DRIVER clocking block — drive stimulus, sample status
    // ----------------------------------------------------------
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output wr_en, rd_en, data_in;
        input  full, empty;
    endclocking

    // ----------------------------------------------------------
    // MONITOR clocking block — passive, all inputs
    // ----------------------------------------------------------
    clocking mon_cb @(posedge clk);
        default input #1step output #1ns;
        input wr_en, rd_en, data_in, data_out, full, empty;
    endclocking

    // ----------------------------------------------------------
    // MODPORTS — one per role. DUT is raw (synthesis-friendly).
    // ----------------------------------------------------------
    modport DRIVER  (clocking drv_cb);
    modport MONITOR (clocking mon_cb);
    modport DUT (
        input  wr_en, rd_en, data_in,
        output data_out, full, empty
    );

endinterface : fifo_if 

// ============================================================
// Day 014: FIFO driver + monitor (plain classes, not UVM yet)
// File: day014_fifo_classes.sv
// Purpose: First prove the pattern without UVM. A driver holds
//          virtual if.DRIVER; a monitor holds virtual if.MONITOR.
//          Same code shape as UVM, less plumbing.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// DRIVER — drives wr_en/data_in, samples full/empty
// ------------------------------------------------------------
class fifo_driver;

    virtual fifo_if.DRIVER vif;

    function new(virtual fifo_if.DRIVER vif);
        this.vif = vif;
    endfunction

    task automatic drive_write(input logic [7:0] data);
        $display("[FIFO_DRV] Driving data=0x%0h", data);
        @(vif.drv_cb);
        vif.drv_cb.wr_en   <= 1'b1;
        vif.drv_cb.data_in <= data;
        @(vif.drv_cb);
        vif.drv_cb.wr_en   <= 1'b0;
        // vif.data_out = 8'h00;  // COMPILE ERROR: data_out is
        //                           not in DRIVER modport
    endtask

endclass : fifo_driver


// ------------------------------------------------------------
// MONITOR — passive, watches wr_en/data_in
// ------------------------------------------------------------
class fifo_monitor;

    virtual fifo_if.MONITOR vif;

    function new(virtual fifo_if.MONITOR vif);
        this.vif = vif;
    endfunction

    task automatic run();
        fork
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.wr_en)
                    $display("[FIFO_MON] WRITE data=0x%0h",
                             vif.mon_cb.data_in);
            end
        join_none
    endtask

endclass : fifo_monitor

      // ============================================================
// Day 014: APB interface + full UVM agent
// File: day014_uvm_apb_agent.sv
// Purpose: The day's real goal — build a UVM 1.2 driver,
//          monitor, sequencer, and env using virtual interfaces.
//          Uses uvm_config_db for the vif hand-off.
// ============================================================

`timescale 1ns/1ps

// ----------------------------------------------------------
// UVM imports — MUST be at the top of the UVM-bearing file
// ----------------------------------------------------------
import uvm_pkg::*;
`include "uvm_macros.svh"


// ------------------------------------------------------------
// APB interface — DRIVER + MONITOR modports
// ------------------------------------------------------------
interface apb_if (input logic pclk, input logic presetn);

    logic [31:0] paddr;
    logic        psel, penable, pwrite;
    logic [31:0] pwdata, prdata;
    logic        pready;

    clocking drv_cb @(posedge pclk);
        default input #1step output #1ns;
        output paddr, psel, penable, pwrite, pwdata;
        input  prdata, pready;
    endclocking

    clocking mon_cb @(posedge pclk);
        default input #1step output #1ns;
        input  paddr, psel, penable, pwrite, pwdata, prdata, pready;
    endclocking

    modport DRIVER  (clocking drv_cb);
    modport MONITOR (clocking mon_cb);

endinterface : apb_if


// ------------------------------------------------------------
// SEQUENCE ITEM — the "transaction" flowing through the agent
// ------------------------------------------------------------
class apb_seq_item extends uvm_sequence_item;
    `uvm_object_utils(apb_seq_item)

    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand bit        write;

    function new(string name = "apb_seq_item");
        super.new(name);
    endfunction

endclass : apb_seq_item


// ------------------------------------------------------------
// DRIVER — pulls items from sequencer, drives APB protocol
// ------------------------------------------------------------
class uvm_apb_driver extends uvm_driver #(apb_seq_item);
    `uvm_component_utils(uvm_apb_driver)

    virtual apb_if.DRIVER vif;

    function new(string name = "uvm_apb_driver",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ----------------------------------------------------------
    // build_phase — retrieve the virtual interface from config DB
    // The path "vif" is set by the test (see Part 4).
    // ----------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if.DRIVER)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF",
                {"Virtual interface not found for: ", get_full_name()})
        end
    endfunction

    // ----------------------------------------------------------
    // run_phase — pull items forever, drive protocol
    // ----------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        // Start idle
        vif.drv_cb.psel    <= 1'b0;
        vif.drv_cb.penable <= 1'b0;

        forever begin
            seq_item_port.get_next_item(req);
            $display("[UVM_APB_DRV] Addr=0x%0h Data=0x%0h Wr=%0b",
                     req.addr, req.data, req.write);

            // SETUP
            @(vif.drv_cb);
            vif.drv_cb.paddr  <= req.addr;
            vif.drv_cb.pwrite <= req.write;
            vif.drv_cb.psel   <= 1'b1;
            if (req.write) vif.drv_cb.pwdata <= req.data;

            // ACCESS
            @(vif.drv_cb);
            vif.drv_cb.penable <= 1'b1;

            // WAIT — safe X-handling
            do begin
                @(vif.drv_cb);
            end while (vif.drv_cb.pready !== 1'b1);

            // IDLE
            vif.drv_cb.psel    <= 1'b0;
            vif.drv_cb.penable <= 1'b0;

            seq_item_port.item_done();
        end
    endtask

endclass : uvm_apb_driver


// ------------------------------------------------------------
// MONITOR — passive sampling, publish transactions
// ------------------------------------------------------------
class uvm_apb_monitor extends uvm_monitor;
    `uvm_component_utils(uvm_apb_monitor)

    virtual apb_if.MONITOR vif;

    // Analysis port would publish here in a real agent;
    // we'll wire a stub for Day 014.
    uvm_analysis_port #(apb_seq_item) ap;

    function new(string name = "uvm_apb_monitor",
                 uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if.MONITOR)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF",
                {"Virtual interface not found for: ", get_full_name()})
        end
    endfunction

    // ----------------------------------------------------------
    // Real sampling loop — the file's version had #10ns no-op
    // ----------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        apb_seq_item txn;
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.psel    === 1'b1 &&
                vif.mon_cb.penable === 1'b1 &&
                vif.mon_cb.pready  === 1'b1) begin

                txn      = apb_seq_item::type_id::create("txn");
                txn.addr = vif.mon_cb.paddr;
                txn.write= vif.mon_cb.pwrite;
                txn.data = vif.mon_cb.pwrite ? vif.mon_cb.pwdata
                                             : vif.mon_cb.prdata;
                $display("[UVM_APB_MON] Captured Wr=%0b A=0x%0h D=0x%0h",
                         txn.write, txn.addr, txn.data);
                ap.write(txn);
            end
        end
    endtask

endclass : uvm_apb_monitor


// ------------------------------------------------------------
// SEQUENCER — standard UVM component, no customization needed
// ------------------------------------------------------------
class uvm_apb_sequencer extends uvm_sequencer #(apb_seq_item);
    `uvm_component_utils(uvm_apb_sequencer)

    function new(string name = "uvm_apb_sequencer",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass


// ------------------------------------------------------------
// ENV — container that wires driver, monitor, sequencer
// ------------------------------------------------------------
class uvm_apb_env extends uvm_env;
    `uvm_component_utils(uvm_apb_env)

    uvm_apb_driver    drv;
    uvm_apb_monitor   mon;
    uvm_apb_sequencer sqr;

    function new(string name = "uvm_apb_env",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        drv = uvm_apb_driver   ::type_id::create("drv", this);
        mon = uvm_apb_monitor  ::type_id::create("mon", this);
        sqr = uvm_apb_sequencer::type_id::create("sqr", this);
    endfunction

    // ----------------------------------------------------------
    // connect_phase — wire sequencer to driver
    // UVM 1.2 port name is `seq_item_port` (not prod_if)
    // ----------------------------------------------------------
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass : uvm_apb_env

// ============================================================
// Day 014: UVM test + tb_top — the FULL plumbing
// File: day014_uvm_tb.sv
// Purpose: Complete the day. Show the config DB set/get dance
//          from uvm_test and the run_test() call in tb_top.
// ============================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"


// ------------------------------------------------------------
// MOCK SEQUENCE — sends one write to exercise the driver
// ------------------------------------------------------------
class mock_apb_sequence extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(mock_apb_sequence)

    function new(string name = "mock_apb_sequence");
        super.new(name);
    endfunction

    task body();
        apb_seq_item item;
        item = apb_seq_item::type_id::create("item");

        start_item(item);
        item.addr  = 32'h5000_1234;
        item.data  = 32'hA5A5_5A5A;
        item.write = 1'b1;
        finish_item(item);
    endtask

endclass


// ------------------------------------------------------------
// BASE TEST — sets the virtual interfaces into config DB,
// then launches a sequence.
// ------------------------------------------------------------
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    uvm_apb_env env;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uvm_apb_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        mock_apb_sequence seq;

        phase.raise_objection(this);

        seq = mock_apb_sequence::type_id::create("seq");
        seq.start(env.sqr);

        #50ns;
        phase.drop_objection(this);
    endtask

endclass : base_test


// ------------------------------------------------------------
// TB TOP — the actual simulation entry point
// ------------------------------------------------------------
module tb_top;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;
    initial begin
        #15 rst_n = 1;
    end

    // ----------------------------------------------------------
    // PHYSICAL interface instances (only exist here, in tb_top)
    // ----------------------------------------------------------
    fifo_if inst_fifo_if (.clk(clk), .rst_n(rst_n));
    apb_if  inst_apb_if  (.pclk(clk), .presetn(rst_n));

    // ----------------------------------------------------------
    // MOCK SLAVE RESPONSES — self-contained demo only
    // (real DUT drives these)
    // ----------------------------------------------------------
    assign inst_apb_if.pready = 1'b1;
    assign inst_apb_if.prdata = 32'hDEAD_CAFE;

    // ----------------------------------------------------------
    // NON-UVM DRIVER/MONITOR demo (Exercises 1-3)
    // ----------------------------------------------------------
    initial begin
        fifo_driver  f_drv;
        fifo_monitor f_mon;

        f_drv = new(inst_fifo_if.DRIVER);
        f_mon = new(inst_fifo_if.MONITOR);
        f_mon.run();

        wait (rst_n == 1'b1);
        @(posedge clk);
        f_drv.drive_write(8'h8C);
    end

    // ----------------------------------------------------------
    // UVM PLUMBING — the file's missing piece
    //
    // ORDER MATTERS:
    //   1. uvm_config_db::set(...)    -- must happen BEFORE run_test
    //   2. run_test()                 -- starts the UVM framework
    //
    // If you call run_test() first, the config DB is empty when
    // build_phase runs, and the driver's get() returns 0 -> fatal.
    // ----------------------------------------------------------
    initial begin
        // Set both interfaces BEFORE the framework starts
        uvm_config_db#(virtual apb_if.DRIVER)::set(
            null, "uvm_test_top.env.drv", "vif", inst_apb_if.DRIVER);

        uvm_config_db#(virtual apb_if.MONITOR)::set(
            null, "uvm_test_top.env.mon", "vif", inst_apb_if.MONITOR);

        // Launch UVM
        run_test("base_test");
    end

endmodule : tb_top 

        
