
// ============================================================================
//  tb/monitors/gcm_monitor.sv
//
//  Watches the GCM interface and emits one record per tag_valid pulse,
//  plus per-AAD-beat records.  Used by the gcm_scoreboard.
// ============================================================================
/*`ifndef GCM_MONITOR_SV
`define GCM_MONITOR_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;


class gcm_mon_item;
   
    typedef enum {EV_AAD, EV_TAG} ev_e;
    ev_e         kind;
    aes_block_t  data;     // AAD block or tag
    realtime     t_evt;
    bit          tag_match;
endclass

class gcm_monitor;


    virtual gcm_if vif;
    mailbox #(gcm_mon_item) out_mbox;

    string name;

    function new(string n = "gcm_monitor");
        name     = n;
        out_mbox = new();
    endfunction

    function string get_name(); return name; endfunction

    task run();
        gcm_mon_item it;
        wait (vif.reset == 1'b0);
        forever begin
            @(vif.cb_mon);
            if (vif.cb_mon.aad_valid && vif.cb_mon.aad_ready) begin
                it           = new();
                it.kind      = gcm_mon_item::EV_AAD;
                it.data      = vif.cb_mon.aad_data;
                it.t_evt     = $realtime;
                it.tag_match = 1'b0;
                out_mbox.put(it);
            end
            if (vif.cb_mon.tag_valid) begin
                it           = new();
                it.kind      = gcm_mon_item::EV_TAG;
                it.data      = vif.cb_mon.tag_out;
                it.t_evt     = $realtime;
                it.tag_match = vif.cb_mon.tag_match;
                out_mbox.put(it);
                `LOG_LOW($sformatf("GCM TAG 0x%032h match=%0d",
                                   it.data, it.tag_match));
            end
        end
    endtask

endclass

`endif


// ============================================================================
//  gcm_monitor.sv
//
//  Corrected GCM monitor.
//
//  Supports:
//      - AAD observation
//      - payload ordering
//      - tag capture
//      - latency-independent operation
//
// ============================================================================

`timescale 1ns/1ps

import aes_pkg::*;
import aes_tb_pkg::*;

class gcm_monitor;

    // =============================================================
    // INTERFACE
    // =============================================================

    virtual gcm_if gcm_vif;
    virtual aes_stream_if stream_vif;

    // =============================================================
    // MAILBOX
    // =============================================================

    mailbox #(gcm_transaction) mon2sb;

    // =============================================================
    // CONSTRUCTOR
    // =============================================================

    function new(

        virtual gcm_if gcm_vif,
        virtual aes_stream_if stream_vif,

        mailbox #(gcm_transaction) mon2sb

    );

        this.gcm_vif    = gcm_vif;
        this.stream_vif = stream_vif;
        this.mon2sb     = mon2sb;

    endfunction

    // =============================================================
    // RUN
    // =============================================================

    task run();

        gcm_transaction tr;

        forever begin

            @(posedge gcm_vif.clk);

            if(gcm_vif.reset)
                continue;

            // -----------------------------------------------------
            // TAG CAPTURE
            // -----------------------------------------------------

            if(gcm_vif.tag_valid) begin

                tr = new();

                tr.tag_out = gcm_vif.tag_out;

                tr.expected_tag =
                    gcm_vif.expected_tag;

                tr.tag_match =
                    gcm_vif.tag_match;

                tr.capture_time = $time;

                mon2sb.put(tr);

                $display(
                    "[GCM MON] tag=%h match=%0d time=%0t",
                    tr.tag_out,
                    tr.tag_match,
                    $time
                );

            end

        end

    endtask

endclass



// ============================================================================
//  gcm_monitor.sv
//
//  Compatible with existing aes_env architecture.
//
//  Monitors:
//      - AAD transfers
//      - tag outputs
//
//  Publishes gcm_transaction objects to scoreboard.
//
// ============================================================================

`ifndef GCM_MONITOR_SV
`define GCM_MONITOR_SV

`timescale 1ns/1ps

import aes_pkg::*;
import aes_tb_pkg::*;


class gcm_mon_item;

    typedef enum {EV_AAD, EV_TAG} ev_e;

    ev_e         kind;
    aes_block_t  data;
    realtime     t_evt;
    bit          tag_match;

endclass

class gcm_monitor;

    // =============================================================
    // INTERFACES
    // =============================================================

    virtual gcm_if vif;

    // =============================================================
    // MAILBOX
    // =============================================================

    mailbox #(gcm_mon_item) out_mbox;

    // =============================================================
    // INTERNALS
    // =============================================================

    string name;

    // =============================================================
    // CONSTRUCTOR
    // =============================================================

    function new(string n = "gcm_monitor");

        name = n;

        out_mbox = new();

    endfunction

    function string get_name();
        return name;
    endfunction

    // =============================================================
    // RUN
    // =============================================================

    task run();

        gcm_transaction tr;

        wait(vif.reset == 1'b0);

        forever begin

            @(vif.cb_mon);

            // -----------------------------------------------------
            // AAD OBSERVATION
            // -----------------------------------------------------

            if(
                vif.cb_mon.aad_valid &&
                vif.cb_mon.aad_ready
            ) begin

                tr = new();

                //tr.aad.push_back(
                 //   vif.cb_mon.aad_data
               // );
                tr.aad = new[1];
                tr.aad[0] = vif.cb_mon.aad_data;
                tr.capture_time = $time;

                out_mbox.put(tr);

                `LOG_LOW(
                    $sformatf(
                        "[GCM MON] AAD=%032h",
                        vif.cb_mon.aad_data
                    )
                );

            end

            // -----------------------------------------------------
            // TAG OBSERVATION
            // -----------------------------------------------------

            if(vif.cb_mon.tag_valid) begin

                tr = new();

                tr.tag_valid = 1'b1;

                tr.tag_out =
                    vif.cb_mon.tag_out;

                tr.tag_match =
                    vif.cb_mon.tag_match;

                tr.capture_time = $time;

                out_mbox.put(tr);

                `LOG_LOW(
                    $sformatf(
                        "[GCM MON] TAG=%032h match=%0d",
                        tr.tag_out,
                        tr.tag_match
                    )
                );

            end

        end

    endtask

endclass




`endif

*/

`ifndef GCM_MONITOR_SV
`define GCM_MONITOR_SV

`timescale 1ns/1ps

import aes_pkg::*;
import aes_tb_pkg::*;

// ============================================================================
//  Monitor observation item
// ============================================================================

class gcm_mon_item;

    typedef enum {
        EV_AAD,
        EV_TAG
    } ev_e;

    ev_e         kind;
    aes_block_t  data;
    realtime     t_evt;
    bit          tag_match;

endclass

// ============================================================================
//  GCM Monitor
// ============================================================================

class gcm_monitor;

    // =============================================================
    // INTERFACE
    // =============================================================

    virtual gcm_if vif;

    // =============================================================
    // MAILBOX
    // =============================================================

    mailbox #(gcm_mon_item) out_mbox;

    // =============================================================
    // INTERNALS
    // =============================================================

    string name;

    // =============================================================
    // CONSTRUCTOR
    // =============================================================

    function new(string n = "gcm_monitor");

        name = n;

        out_mbox = new();

    endfunction

    function string get_name();

        return name;

    endfunction

    // =============================================================
    // RUN
    // =============================================================

    task run();

        gcm_mon_item it;

        wait(vif.reset == 1'b0);

        forever begin

            @(vif.cb_mon);

            // -----------------------------------------------------
            // AAD OBSERVATION
            // -----------------------------------------------------

            if(
                vif.cb_mon.aad_valid &&
                vif.cb_mon.aad_ready
            ) begin

                it = new();

                it.kind      = gcm_mon_item::EV_AAD;
                it.data      = vif.cb_mon.aad_data;
                it.t_evt     = $realtime;
                it.tag_match = 1'b0;

                out_mbox.put(it);

                `LOG_LOW(
                    $sformatf(
                        "[GCM MON] AAD=%032h",
                        it.data
                    )
                );

            end

            // -----------------------------------------------------
            // TAG OBSERVATION
            // -----------------------------------------------------

            if(vif.cb_mon.tag_valid) begin

                it = new();

                it.kind      = gcm_mon_item::EV_TAG;
                it.data      = vif.cb_mon.tag_out;
                it.t_evt     = $realtime;
                it.tag_match = vif.cb_mon.tag_match;

                out_mbox.put(it);

                `LOG_LOW(
                    $sformatf(
                        "[GCM MON] TAG=%032h match=%0d",
                        it.data,
                        it.tag_match
                    )
                );

            end

        end

    endtask

endclass

`endif