// ============================================================
// Day 012: Minimal handshake modports — no clocking block
// File: day012_basic_hs.sv
// Purpose: The simplest possible modport demo. Shows that a
//          modport is just a directional view of shared signals.
// ============================================================

`timescale 1ns/1ps

interface basic_hs_if;

    logic       valid;
    logic       ready;
    logic [7:0] data;

    // ----------------------------------------------------------
    // MODPORTS — pure direction views, no clocking block
    // MASTER drives valid+data, samples ready
    // SLAVE  samples valid+data, drives ready
    // Same physical wires; opposite directions.
    // ----------------------------------------------------------
    modport MASTER (output valid, data, input  ready);
    modport SLAVE  (input  valid, data, output ready);

endinterface : basic_hs_if


// ------------------------------------------------------------
// MASTER module — plays the MASTER role
// ------------------------------------------------------------
module hs_master (basic_hs_if.MASTER m_if,
                  input logic clk, input logic rst_n);

    initial begin
        m_if.valid <= 1'b0;
        m_if.data  <= 8'h0;

        wait (rst_n == 1'b1);
        @(posedge clk);

        // Assert valid + data
        m_if.valid <= 1'b1;
        m_if.data  <= 8'hA5;

        // Wait for slave to accept (ready=1 on a posedge)
        do begin
            @(posedge clk);
        end while (m_if.ready == 1'b0);

        // Deassert after handshake
        m_if.valid <= 1'b0;
    end

endmodule : hs_master


// ------------------------------------------------------------
// SLAVE module — plays the SLAVE role
// Random backpressure: ready=1 or 0 each cycle
// ------------------------------------------------------------
module hs_slave (basic_hs_if.SLAVE s_if,
                 input logic clk, input logic rst_n);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_if.ready <= 1'b0;
        end
        else begin
            // Randomly accept or stall (0 or 1)
            s_if.ready <= $urandom_range(0, 1);

            // Handshake fires when valid && ready in same cycle
            if (s_if.valid && s_if.ready) begin
                $display("[HS_SLAVE] Handshake OK — data = 0x%0h",
                         s_if.data);
            end
        end
    end

endmodule : hs_slave 

// ============================================================
// Day 012: FIFO interface — DRIVER / MONITOR / DUT views
// File: day012_fifo_if.sv
// Purpose: Three modports for three roles. DRIVER drives +
//          samples; MONITOR is all-inputs (cannot drive);
//          DUT uses raw signals (synthesis-friendly).
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
    // DRIVER clocking block — drives stimulus, samples status
    // ----------------------------------------------------------
    clocking drv_cb @(posedge clk);
        default input #1ns output #1ns;
        output wr_en, rd_en, data_in;
        input  full, empty;
    endclocking

    // ----------------------------------------------------------
    // MONITOR clocking block — purely PASSIVE
    // All signals input — monitor cannot drive even by mistake.
    // This is the passive-observer guarantee.
    // ----------------------------------------------------------
    clocking mon_cb @(posedge clk);
        default input #1ns output #1ns;
        input wr_en, rd_en, data_in, data_out, full, empty;
    endclocking

    // ----------------------------------------------------------
    // MODPORTS — one per role
    // DRIVER, MONITOR: clocking-block views
    // DUT: raw signals for RTL (must be synthesizable)
    // ----------------------------------------------------------
    modport DRIVER  (clocking drv_cb);
    modport MONITOR (clocking mon_cb);
    modport DUT (
        input  wr_en, rd_en, data_in,
        output data_out, full, empty
    );

endinterface : fifo_if

      // ============================================================
// Day 012: Driver class via virtual fifo_if.DRIVER
// File: day012_fifo_driver.sv
// Purpose: First class using a modport-typed virtual interface.
//          Shows the standard "check-full, stall, write" idiom.
// ============================================================

`timescale 1ns/1ps

class fifo_driver;

    // ----------------------------------------------------------
    // Type-safe handle — bound to a SPECIFIC modport.
    // Trying to call monitor methods via this handle is a
    // compile error.
    // ----------------------------------------------------------
    virtual fifo_if.DRIVER vif;

    function new(virtual fifo_if.DRIVER vif);
        this.vif = vif;
    endfunction

    // ----------------------------------------------------------
    // write_data — synchronized write with full-stall
    // - If FIFO full, wait for space before writing
    // - Uses !== 1'b1 for safe X-handling
    // ----------------------------------------------------------
    task automatic write_data(input logic [7:0] data);
        @(vif.drv_cb);

        // FULL-STALL: wait until full is definitively 0
        // Using !== 1'b1 makes an X on full act as "stall",
        // matching the safe interpretation.
        if (vif.drv_cb.full !== 1'b0) begin
            $display("[FIFO_DRV] FIFO full — waiting for space");
            wait (vif.drv_cb.full !== 1'b1);
            @(vif.drv_cb);
        end

        // Drive write for one cycle
        vif.drv_cb.wr_en   <= 1'b1;
        vif.drv_cb.data_in <= data;

        @(vif.drv_cb);
        vif.drv_cb.wr_en   <= 1'b0;
    endtask

endclass : fifo_driver 

      // ============================================================
// Day 012: APB interface — full 3-role matrix + protocol tasks
// File: day012_apb_if.sv
// Purpose: Three clocking blocks, three modports, and reusable
//          bus_write / bus_read tasks.
// ============================================================

`timescale 1ns/1ps

interface apb_if (input logic pclk, input logic presetn);

    logic [31:0] paddr;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    // ----------------------------------------------------------
    // MASTER clocking block — drives request, samples response
    // ----------------------------------------------------------
    clocking mstr_cb @(posedge pclk);
        default input #1ns output #1ns;
        output paddr, psel, penable, pwrite, pwdata;
        input  prdata, pready, pslverr;
    endclocking

    // ----------------------------------------------------------
    // SLAVE clocking block — samples request, drives response
    // ----------------------------------------------------------
    clocking slv_cb @(posedge pclk);
        default input #1ns output #1ns;
        input  paddr, psel, penable, pwrite, pwdata;
        output prdata, pready, pslverr;
    endclocking

    // ----------------------------------------------------------
    // MONITOR clocking block — all inputs (passive)
    // ----------------------------------------------------------
    clocking mon_cb @(posedge pclk);
        default input #1ns output #1ns;
        input  paddr, psel, penable, pwrite, pwdata,
               prdata, pready, pslverr;
    endclocking

	// ----------------------------------------------------------
    // MODPORTS — updated to import protocol tasks for MASTER
    // ----------------------------------------------------------
    modport MASTER  (clocking mstr_cb, import bus_write, import bus_read);
    modport SLAVE   (clocking slv_cb);
    modport MONITOR (clocking mon_cb);

    // ----------------------------------------------------------
    // APB WRITE
    // SETUP -> ACCESS -> WAIT (with !== fix) -> IDLE
    // ----------------------------------------------------------
    task automatic bus_write(input logic [31:0] addr,
                             input logic [31:0] wdata);
        // SETUP
        @(mstr_cb);
        mstr_cb.paddr   <= addr;
        mstr_cb.pwrite  <= 1'b1;
        mstr_cb.psel    <= 1'b1;
        mstr_cb.penable <= 1'b0;
        mstr_cb.pwdata  <= wdata;

        // ACCESS
        @(mstr_cb);
        mstr_cb.penable <= 1'b1;

        // WAIT — safe X-handling
        do begin
            @(mstr_cb);
        end while (mstr_cb.pready !== 1'b1);

        // IDLE
        mstr_cb.psel    <= 1'b0;
        mstr_cb.penable <= 1'b0;
    endtask

    // ----------------------------------------------------------
    // APB READ
    // ----------------------------------------------------------
    task automatic bus_read(input  logic [31:0] addr,
                            output logic [31:0] rdata);
        // SETUP
        @(mstr_cb);
        mstr_cb.paddr   <= addr;
        mstr_cb.pwrite  <= 1'b0;
        mstr_cb.psel    <= 1'b1;
        mstr_cb.penable <= 1'b0;

        // ACCESS
        @(mstr_cb);
        mstr_cb.penable <= 1'b1;

        // WAIT
        do begin
            @(mstr_cb);
        end while (mstr_cb.pready !== 1'b1);

        // CAPTURE
        rdata = mstr_cb.prdata;

        // IDLE
        mstr_cb.psel    <= 1'b0;
        mstr_cb.penable <= 1'b0;
    endtask

endinterface : apb_if 

      // ============================================================
// Day 012: APB driver + monitor as two UVM-shaped classes
// File: day012_apb_drv_mon.sv
// Purpose: Driver holds MASTER virtual interface; Monitor holds
//          MONITOR virtual interface. Runs concurrently.
// ============================================================

`timescale 1ns/1ps

// ------------------------------------------------------------
// DRIVER — composes bus_write via the virtual interface
// ------------------------------------------------------------
class refactored_apb_driver;

    virtual apb_if.MASTER master_vif;

    function new(virtual apb_if.MASTER master_vif);
        this.master_vif = master_vif;
    endfunction

    task automatic execute_configuration(input logic [31:0] addr,
                                         input logic [31:0] payload);
        $display("[DRV_CMD] Config write 0x%0h <- 0x%0h",
                 addr, payload);
        master_vif.bus_write(addr, payload);
    endtask

endclass : refactored_apb_driver


// ------------------------------------------------------------
// MONITOR — passive sniffer, forks a forever loop
// ------------------------------------------------------------
class refactored_apb_monitor;

    virtual apb_if.MONITOR mon_vif;

    function new(virtual apb_if.MONITOR mon_vif);
        this.mon_vif = mon_vif;
    endfunction

    // ----------------------------------------------------------
    // start_sniffing — non-blocking loop
    // fork...join_none: returns immediately, loop runs in bg
    // Each clock, check for a completed APB transaction.
    // ----------------------------------------------------------
    task automatic start_sniffing();
        fork
            forever begin
                @(mon_vif.mon_cb);

                // Completed transaction: PSEL & PENABLE & PREADY
                if (mon_vif.mon_cb.psel    &&
                    mon_vif.mon_cb.penable &&
                    mon_vif.mon_cb.pready) begin

                    if (mon_vif.mon_cb.pwrite)
                        $display("[MON] WRITE  addr=0x%0h data=0x%0h",
                                 mon_vif.mon_cb.paddr,
                                 mon_vif.mon_cb.pwdata);
                    else
                        $display("[MON] READ   addr=0x%0h data=0x%0h",
                                 mon_vif.mon_cb.paddr,
                                 mon_vif.mon_cb.prdata);
                end
            end
        join_none
    endtask

endclass : refactored_apb_monitor 

       // ============================================================
// Day 012: Top-level testbench wiring everything together
// File: day012_tb_root.sv
// ============================================================

`timescale 1ns/1ps

module tb_root;

    logic clk   = 0;
    logic rst_n = 0;

    always #5 clk = ~clk;

    initial begin
        #15 rst_n = 1;
    end

    // ----------------------------------------------------------
    // INTERFACE INSTANCES (physical, at tb_top level)
    // ----------------------------------------------------------
    basic_hs_if inst_hs_if();
    fifo_if     inst_fifo_if (.clk(clk), .rst_n(rst_n));
    apb_if      inst_apb_if  (.pclk(clk), .presetn(rst_n));

    // ----------------------------------------------------------
    // MOCKED DUT RESPONSES — self-contained demo only
    // In real verification the DUT drives these.
    // ----------------------------------------------------------
    assign inst_fifo_if.full     = 1'b0;
    assign inst_fifo_if.empty    = 1'b1;
    assign inst_fifo_if.data_out = inst_fifo_if.data_in;

    assign inst_apb_if.pready    = 1'b1;
    assign inst_apb_if.pslverr   = 1'b0;
    assign inst_apb_if.prdata    = 32'hCAFE_BABE;

    // ----------------------------------------------------------
    // Exercise 1 modules
    // ----------------------------------------------------------
    hs_master master_inst (.m_if(inst_hs_if.MASTER),
                           .clk(clk), .rst_n(rst_n));
    hs_slave  slave_inst  (.s_if(inst_hs_if.SLAVE),
                           .clk(clk), .rst_n(rst_n));

    // ----------------------------------------------------------
    // STIMULUS
    // ----------------------------------------------------------
    initial begin
        fifo_driver            f_drv;
        refactored_apb_driver  apb_drv;
        refactored_apb_monitor apb_mon;

        // Hand each class a virtual interface of the correct modport
        f_drv   = new(inst_fifo_if.DRIVER);
        apb_drv = new(inst_apb_if.MASTER);
        apb_mon = new(inst_apb_if.MONITOR);

        wait (rst_n == 1'b1);
        @(posedge clk);

        $display("\n====== Exercise 1: Handshake Complete ======");
        #20;

        $display("\n====== Exercise 4: Virtual FIFO Driving ======");
        f_drv.write_data(8'h55);
        f_drv.write_data(8'hAA);

        $display("\n====== Exercise 6: Driver/Monitor Interaction ======");
        apb_mon.start_sniffing();
        apb_drv.execute_configuration(32'h1000_0000, 32'h5555_AAAA);

        #20;
        $finish;
    end

endmodule : tb_root  
