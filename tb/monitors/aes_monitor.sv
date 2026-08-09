// ============================================================================
//  tb/monitors/aes_monitor.sv
//
//  Passive monitor for the AES stream interface.
//
//  Emits one record per accepted input beat (in_valid && in_ready) and one
//  record per accepted output beat (out_valid && out_ready) on separate
//  mailboxes so the scoreboard can pair them in order.
//
//  Each record carries the cycle-accurate timestamp, the data, and a
//  snapshot of bank state (passed in via a virtual interface to key_if).
// ============================================================================
/*`ifndef AES_MONITOR_SV
`define AES_MONITOR_SV

import aes_pkg::*;
class aes_mon_item;
    
    aes_block_t  data;
    aes_mode_e   mode;
    bit          enc_dec;
    aes_block_t  iv_or_ctr;
    realtime     t_evt;
    bit          bank_at_accept;
    bit  [1:0]   bank_valid_at_accept;
    bit  [1:0]   bank_busy_at_accept;
    int unsigned id;             // populated by scoreboard pairing
endclass


import aes_tb_pkg::*;
    
class aes_monitor;

   

    virtual aes_ctrl_if   ctrl_vif;
    virtual aes_stream_if stream_vif;
    virtual key_if        key_vif;

    mailbox #(aes_mon_item) in_mbox;
    mailbox #(aes_mon_item) out_mbox;

    string name;

    function new(string n = "aes_monitor");
        name     = n;
        in_mbox  = new();
        out_mbox = new();
    endfunction

    function string get_name(); return name; endfunction

    task run();
        fork
            sample_inputs();
            sample_outputs();
        join_none
    endtask

    task sample_inputs();
        aes_mon_item it;
        wait (stream_vif.reset == 1'b0);
        forever begin
            @(stream_vif.cb_mon);
            if (stream_vif.cb_mon.in_valid && stream_vif.cb_mon.in_ready) begin
                it = new();
                it.data                 = stream_vif.cb_mon.data_in;
                it.mode                 = ctrl_vif.cb_mon.mode;
                it.enc_dec              = ctrl_vif.cb_mon.enc_dec;
                it.iv_or_ctr            = ctrl_vif.cb_mon.iv_in;
                it.t_evt                = $realtime;
                it.bank_valid_at_accept = key_vif.cb_mon.bank_valid;
                it.bank_busy_at_accept  = key_vif.cb_mon.bank_busy;
                it.bank_at_accept       = (key_vif.cb_mon.bank_valid[1]
                                             && !key_vif.cb_mon.bank_valid[0]) ? 1'b1 : 1'b0;
                in_mbox.put(it);
                `LOG_HIGH($sformatf("IN  d=0x%032h mode=%s enc=%0d",
                                    it.data, mode_name(it.mode), it.enc_dec));
            end
        end
    endtask

    task sample_outputs();
        aes_mon_item it;
        wait (stream_vif.reset == 1'b0);
        forever begin
            @(stream_vif.cb_mon);
            if (stream_vif.cb_mon.out_valid && stream_vif.cb_mon.out_ready) begin
                it = new();
                it.data    = stream_vif.cb_mon.data_out;
                it.mode    = ctrl_vif.cb_mon.mode;
                it.enc_dec = ctrl_vif.cb_mon.enc_dec;
                it.t_evt   = $realtime;
                out_mbox.put(it);
                `LOG_HIGH($sformatf("OUT d=0x%032h", it.data));
            end
        end
    endtask

endclass

`endif


// ============================================================================
//  aes_monitor.sv
//
//  Corrected transaction monitor for the AES verification environment.
//
//  FIXES APPLIED
//  ============================================================================
//
//  FIX-M1
//  Sample ONLY on valid/ready handshake.
//
//  FIX-M2
//  Removes fixed latency assumptions.
//
//  FIX-M3
//  Preserves per-transaction mode metadata.
//
//  FIX-M4
//  Prevents monitor/output desynchronization under backpressure.
//
//  FIX-M5
//  Supports reordered/stalled pipelines safely.
//
//  FIX-M6
//  Compatible with corrected datapath ownership architecture.
//
//  FIX-M7
//  No dependency on internal GCM override traffic.
//
// ============================================================================

`timescale 1ns/1ps

import aes_pkg::*;
import aes_tb_pkg::*;

class aes_monitor;

    // =====================================================================
    // VIRTUAL INTERFACES
    // =====================================================================

virtual aes_ctrl_if   ctrl_vif;
virtual aes_stream_if stream_vif;
virtual key_if        key_vif;

    // =====================================================================
    // MAILBOX TO SCOREBOARD
    // =====================================================================

    mailbox #(aes_transaction) mon2sb;

    // =====================================================================
    // PENDING INPUT QUEUE
    //
    // Inputs are captured on input handshake.
    // Outputs pop the oldest pending transaction.
    // This keeps ordering stable even with stalls/backpressure.
    // =====================================================================

    aes_transaction pending_q[$];

    // =====================================================================
    // STATISTICS
    // =====================================================================

    int unsigned in_count;
    int unsigned out_count;

    // =====================================================================
    // CONSTRUCTOR
    // =====================================================================

    function new(string n = "aes_monitor");

    name = n;

    in_mbox  = new();
    out_mbox = new();

endfunction

        this.stream_vif = stream_vif;
        this.ctrl_vif   = ctrl_vif;
        this.mon2sb     = mon2sb;

        in_count  = 0;
        out_count = 0;

    endfunction

    // =====================================================================
    // RUN
    // =====================================================================

    task run();

        fork
            monitor_inputs();
            monitor_outputs();
        join_none

    endtask

    // =====================================================================
    // INPUT MONITOR
    //
    // Captures ONLY accepted user transactions.
    // =====================================================================

    task monitor_inputs();

        aes_transaction tr;

        forever begin

            @(posedge stream_vif.clk);

            if(stream_vif.reset)
                continue;

            // -------------------------------------------------------------
            // SAMPLE ONLY ON HANDSHAKE
            // -------------------------------------------------------------

            if(
                stream_vif.in_valid &&
                stream_vif.in_ready
            ) begin

                tr = new();

                // ---------------------------------------------------------
                // INPUT DATA
                // ---------------------------------------------------------

                tr.data_in = stream_vif.data_in;

                // ---------------------------------------------------------
                // CONTROL CONTEXT
                // ---------------------------------------------------------

                tr.mode    = ctrl_vif.mode;
                tr.enc_dec = ctrl_vif.enc_dec;

                tr.iv = ctrl_vif.iv_in;

                // ---------------------------------------------------------
                // TIMESTAMP
                // ---------------------------------------------------------

                tr.accept_time = $time;

                // ---------------------------------------------------------
                // PUSH TO PENDING QUEUE
                // ---------------------------------------------------------

                pending_q.push_back(tr);

                in_count++;

                $display(
                    "[MON-IN ] txn=%0d mode=%s enc_dec=%0d data=%h time=%0t",
                    in_count,
                    tr.mode.name(),
                    tr.enc_dec,
                    tr.data_in,
                    $time
                );

            end

        end

    endtask

    // =====================================================================
    // OUTPUT MONITOR
    //
    // Matches outputs to oldest pending input transaction.
    // No fixed latency assumptions.
    // =====================================================================

    task monitor_outputs();

        aes_transaction tr;

        forever begin

            @(posedge stream_vif.clk);

            if(stream_vif.reset)
                continue;

            // -------------------------------------------------------------
            // SAMPLE ONLY ON OUTPUT HANDSHAKE
            // -------------------------------------------------------------

            if(
                stream_vif.out_valid &&
                stream_vif.out_ready
            ) begin

                // ---------------------------------------------------------
                // SAFETY CHECK
                // ---------------------------------------------------------

                if(pending_q.size() == 0) begin

                    $fatal(
                        "[MON] Output observed with empty pending queue"
                    );

                end

                // ---------------------------------------------------------
                // POP OLDEST TRANSACTION
                // ---------------------------------------------------------

                tr = pending_q.pop_front();

                // ---------------------------------------------------------
                // OUTPUT DATA
                // ---------------------------------------------------------

                tr.data_out = stream_vif.data_out;

                tr.complete_time = $time;

                // ---------------------------------------------------------
                // LATENCY
                // ---------------------------------------------------------

                tr.latency_cycles =
                    (tr.complete_time - tr.accept_time) / 10;

                out_count++;

                $display(
                    "[MON-OUT] txn=%0d mode=%s enc_dec=%0d data=%h latency=%0d cyc time=%0t",
                    out_count,
                    tr.mode.name(),
                    tr.enc_dec,
                    tr.data_out,
                    tr.latency_cycles,
                    $time
                );

                // ---------------------------------------------------------
                // SEND TO SCOREBOARD
                // ---------------------------------------------------------

                mon2sb.put(tr);

            end

        end

    endtask

    // =====================================================================
    // STATUS
    // =====================================================================

    task report();

        $display("\n================================================");

        $display("[AES MONITOR REPORT]");

        $display("Inputs  Observed : %0d", in_count);
        $display("Outputs Observed : %0d", out_count);
        $display("Pending Queue    : %0d", pending_q.size());

        if(pending_q.size() != 0)

            $display(
                "[WARN] Pending queue not empty at end of simulation"
            );

        $display("================================================\n");

    endtask

endclass


`ifndef AES_MONITOR_SV
`define AES_MONITOR_SV

`timescale 1ns/1ps

import aes_pkg::*;
import aes_tb_pkg::*;

class aes_monitor;

    // =============================================================
    // INTERFACES
    // =============================================================

    virtual aes_ctrl_if   ctrl_vif;
    virtual aes_stream_if stream_vif;
    virtual key_if        key_vif;

    // =============================================================
    // MAILBOXES
    // =============================================================

    mailbox #(aes_transaction) out_mbox;

    // =============================================================
    // INTERNALS
    // =============================================================

    int unsigned out_count;

    string name;

    // =============================================================
    // CONSTRUCTOR
    // =============================================================

    function new(string n = "aes_monitor");

        name = n;

        out_mbox = new();

        out_count = 0;

    endfunction

    function string get_name();
        return name;
    endfunction

    // =============================================================
    // RUN
    // =============================================================

    task run();

        aes_transaction tr;

        wait(stream_vif.reset == 1'b0);

        forever begin

            @(stream_vif.cb_mon);

            // -----------------------------------------------------
            // OUTPUT HANDSHAKE
            // -----------------------------------------------------

            if(
                stream_vif.cb_mon.out_valid &&
                stream_vif.cb_mon.out_ready
            ) begin

                tr = new();

                tr.mode =
                    ctrl_vif.mode;

                tr.enc_dec =
                    ctrl_vif.enc_dec;

                tr.iv =
                    ctrl_vif.iv_in;

                tr.num_blocks = 1;

                tr.blocks = new[1];

                tr.blocks[0] =
                    stream_vif.cb_mon.data_out;

                out_mbox.put(tr);

                out_count++;

                `LOG_LOW(
                    $sformatf(
                        "[AES MON] mode=%s enc_dec=%0d data=%032h",
                        tr.mode.name(),
                        tr.enc_dec,
                        tr.blocks[0]
                    )
                );

            end

        end

    endtask

    // =============================================================
    // REPORT
    // =============================================================

    function void report_phase();

        $display("");
        $display(
            "[aes_monitor] observed=%0d",
            out_count
        );

    endfunction

endclass

`endif

`ifndef AES_MONITOR_SV
`define AES_MONITOR_SV

`timescale 1ns/1ps

import aes_pkg::*;
import aes_tb_pkg::*;

class aes_monitor;

    // =============================================================
    // INTERFACES
    // =============================================================

    virtual aes_ctrl_if   ctrl_vif;
    virtual aes_stream_if stream_vif;
    virtual key_if        key_vif;

    // =============================================================
    // MAILBOXES
    // =============================================================

    mailbox #(aes_transaction) in_mbox;
    mailbox #(aes_transaction) out_mbox;

    // =============================================================
    // INTERNALS
    // =============================================================

    int unsigned in_count;
    int unsigned out_count;

    string name;

    // =============================================================
    // CONSTRUCTOR
    // =============================================================

    function new(string n = "aes_monitor");

        name = n;

        in_mbox  = new();
        out_mbox = new();

        in_count  = 0;
        out_count = 0;

    endfunction

    // =============================================================
    // NAME
    // =============================================================

    function string get_name();

        return name;

    endfunction

    // =============================================================
    // RUN
    // =============================================================

    task run();

        fork
            monitor_inputs();
            monitor_outputs();
        join_none

    endtask

    // =============================================================
    // INPUT MONITOR
    // =============================================================

    task monitor_inputs();

        aes_transaction tr;

        wait(stream_vif.reset == 1'b0);

        forever begin

            @(stream_vif.cb_mon);

            // -----------------------------------------------------
            // INPUT HANDSHAKE
            // -----------------------------------------------------

            if(
                stream_vif.cb_mon.in_valid &&
                stream_vif.cb_mon.in_ready
            ) begin

                tr = new();

                tr.mode =
                    ctrl_vif.mode;

                tr.enc_dec =
                    ctrl_vif.enc_dec;

                tr.iv =
                    ctrl_vif.iv_in;

                tr.num_blocks = 1;

                tr.blocks = new[1];

                tr.blocks[0] =
                    stream_vif.cb_mon.data_in;

                in_mbox.put(tr);

                in_count++;

                `LOG_LOW(
                    $sformatf(
                        "[AES MON IN ] mode=%s enc_dec=%0d data=%032h",
                        tr.mode.name(),
                        tr.enc_dec,
                        tr.blocks[0]
                    )
                );

            end

        end

    endtask

    // =============================================================
    // OUTPUT MONITOR
    // =============================================================

    task monitor_outputs();

        aes_transaction tr;

        wait(stream_vif.reset == 1'b0);

        forever begin

            @(stream_vif.cb_mon);

            // -----------------------------------------------------
            // OUTPUT HANDSHAKE
            // -----------------------------------------------------

            if(
                stream_vif.cb_mon.out_valid &&
                stream_vif.cb_mon.out_ready
            ) begin

                tr = new();

                tr.mode =
                    ctrl_vif.mode;

                tr.enc_dec =
                    ctrl_vif.enc_dec;

                tr.iv =
                    ctrl_vif.iv_in;

                tr.num_blocks = 1;

                tr.blocks = new[1];

                tr.blocks[0] =
                    stream_vif.cb_mon.data_out;

                out_mbox.put(tr);

                out_count++;

                `LOG_LOW(
                    $sformatf(
                        "[AES MON OUT] mode=%s enc_dec=%0d data=%032h",
                        tr.mode.name(),
                        tr.enc_dec,
                        tr.blocks[0]
                    )
                );

            end

        end

    endtask

    // =============================================================
    // REPORT
    // =============================================================

    function void report_phase();

        $display("");

        $display(
            "[aes_monitor] inputs=%0d outputs=%0d",
            in_count,
            out_count
        );

    endfunction

endclass

`endif
*/

`ifndef AES_MONITOR_SV
`define AES_MONITOR_SV

`timescale 1ns/1ps

import aes_pkg::*;
import aes_tb_pkg::*;

class aes_monitor;

    // =============================================================
    // INTERFACES
    // =============================================================

    virtual aes_ctrl_if   ctrl_vif;
    virtual aes_stream_if stream_vif;
    virtual key_if        key_vif;

    // =============================================================
    // MAILBOXES
    // =============================================================

    mailbox #(aes_transaction) in_mbox;
    mailbox #(aes_transaction) out_mbox;

    // =============================================================
    // INTERNALS
    // =============================================================

    int unsigned in_count;
    int unsigned out_count;

    // -------------------------------------------------------------
    // FIX:
    // Queue input metadata so retiring outputs are matched to the
    // correct transaction instead of sampling live ctrl signals.
    // -------------------------------------------------------------

    aes_transaction pending_q[$];

    string name;

    // =============================================================
    // CONSTRUCTOR
    // =============================================================

    function new(string n = "aes_monitor");

        name = n;

        in_mbox  = new();
        out_mbox = new();

        in_count  = 0;
        out_count = 0;

    endfunction

    // =============================================================
    // NAME
    // =============================================================

    function string get_name();

        return name;

    endfunction

    // =============================================================
    // RUN
    // =============================================================

    task run();

        fork
            monitor_inputs();
            monitor_outputs();
        join_none

    endtask

    // =============================================================
    // INPUT MONITOR
    // =============================================================

    task monitor_inputs();

        aes_transaction tr;

        wait(stream_vif.reset == 1'b0);

        forever begin

            @(stream_vif.cb_mon);

            // -----------------------------------------------------
            // INPUT HANDSHAKE
            // -----------------------------------------------------

            if(
                stream_vif.cb_mon.in_valid &&
                stream_vif.cb_mon.in_ready
            ) begin

                tr = new();

                tr.mode =
                    ctrl_vif.mode;

                tr.enc_dec =
                    ctrl_vif.enc_dec;

                tr.iv =
                    ctrl_vif.iv_in;

                tr.num_blocks = 1;

                tr.blocks = new[1];

                tr.blocks[0] =
                    stream_vif.cb_mon.data_in;

                // -------------------------------------------------
                // PUSH TO SCOREBOARD INPUT CHANNEL
                // -------------------------------------------------

                in_mbox.put(tr);

                // -------------------------------------------------
                // SAVE METADATA FOR OUTPUT MATCHING
                // -------------------------------------------------

                pending_q.push_back(tr);

                in_count++;

                `LOG_LOW(
                    $sformatf(
                        "[AES MON IN ] mode=%s enc_dec=%0d data=%032h",
                        tr.mode.name(),
                        tr.enc_dec,
                        tr.blocks[0]
                    )
                );

            end

        end

    endtask

    // =============================================================
    // OUTPUT MONITOR
    // =============================================================

    task monitor_outputs();

        aes_transaction tr;

        wait(stream_vif.reset == 1'b0);

        forever begin

            @(stream_vif.cb_mon);

            // -----------------------------------------------------
            // OUTPUT HANDSHAKE
            // -----------------------------------------------------

            if(
                stream_vif.cb_mon.out_valid &&
                stream_vif.cb_mon.out_ready
            ) begin

                // -------------------------------------------------
                // FIX:
                // Use queued metadata from corresponding input.
                // -------------------------------------------------

                if(pending_q.size() == 0) begin

                    `LOG_ERROR(
                        "AES monitor output with empty pending_q"
                    );

                    continue;

                end

                tr = pending_q.pop_front();

                // -------------------------------------------------
                // STORE OUTPUT DATA
                // -------------------------------------------------

     //           //tr.data_out =
    //            //    stream_vif.cb_mon.data_out;
                tr.blocks[0] =
    stream_vif.cb_mon.data_out;
                // -------------------------------------------------
                // SEND TO SCOREBOARD
                // -------------------------------------------------

                out_mbox.put(tr);

                out_count++;

               // `LOG_LOW(
                //    $sformatf(
                 //       "[AES MON OUT] mode=%s enc_dec=%0d data=%032h",
                 //       tr.mode.name(),
                 //       tr.enc_dec,
                 //       tr.data_out
                 //   )
               // );
               
               `LOG_LOW(
    $sformatf(
        "[AES MON OUT] mode=%s enc_dec=%0d data=%032h",
        tr.mode.name(),
        tr.enc_dec,
        tr.blocks[0]
    )
);

            end

        end

    endtask

    // =============================================================
    // REPORT
    // =============================================================

    function void report_phase();

        $display("");

        $display(
            "[aes_monitor] inputs=%0d outputs=%0d",
            in_count,
            out_count
        );

    endfunction

endclass

`endif