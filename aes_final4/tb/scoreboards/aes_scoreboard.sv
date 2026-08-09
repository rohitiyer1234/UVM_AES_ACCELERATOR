// ============================================================================
//  tb/scoreboards/aes_scoreboard.sv
//
//  Central correctness checker for ECB/CBC/CFB/OFB/CTR transactions.
//
//  Approach
//  --------
//  - Receives expected transactions on `expect_mbox` (from the test, after
//    randomization).  Each transaction carries mode/enc_dec/IV and all
//    plaintext (or ciphertext) blocks.
//  - For each expected transaction, it computes the full expected output
//    stream using mode_refmodel + the current key in the key_refmodel.
//  - As the aes_monitor delivers OUT beats, the scoreboard pops the next
//    expected beat for the head transaction and compares.
//  - On mismatch, a structured txn_log_t record is printed and the error
//    counter increments.  Simulation terminates if tb_max_errors exceeded.
//
//  Note on key correlation: aes_top streams whatever key is currently
//  active.  The TB convention is "load one key, then run a burst" - the
//  scoreboard takes the most recently observed key from key_refmodel at
//  the time the transaction's first input beat is sampled.
// ============================================================================
/*`ifndef AES_SCOREBOARD_SV
`define AES_SCOREBOARD_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;
    import aes_refmodel::*;
    import mode_refmodel::*;
    
    
class aes_scoreboard;



    mailbox #(aes_transaction) expect_mbox;   // from test/env after randomize
    mailbox #(aes_mon_item)    in_mbox;       // from monitor
    mailbox #(aes_mon_item)    out_mbox;      // from monitor

    key_refmodel               key_model;

    int unsigned errors;
    int unsigned compared;
    int unsigned dropped;
    string       name;

    // pending expected outputs queue (interleaved across modes is allowed
    // because the DUT preserves order)
    typedef struct {
        int unsigned id;
        aes_mode_e   mode;
        bit          enc_dec;
        aes_block_t  in_blk;
        aes_block_t  exp_blk;
        realtime     t_create;
    } exp_beat_t;
    exp_beat_t pending [$];

    function new(string n = "aes_scoreboard");
        name        = n;
        errors      = 0;
        compared    = 0;
        dropped     = 0;
        expect_mbox = new();
        in_mbox     = new();
        out_mbox    = new();
    endfunction

    function string get_name(); return name; endfunction

    task run();
        fork
            absorb_expected();
            compare_outputs();
        join_none
    endtask

    // -----------------------------------------------------------------
    // absorb_expected: for each expected transaction, compute and push
    // per-block expected outputs into `pending`.
    // -----------------------------------------------------------------
    task absorb_expected();
        aes_transaction t;
        aes_block_t exp_blocks [];
        aes_block_t key;
        rk_array_t  rk;
        forever begin
            expect_mbox.get(t);
            // grab the most recently used bank key from the model
            if (!key_model.any_key_loaded()) begin
                `LOG_ERROR($sformatf("expect arrived (id=%0d) with no key loaded",
                                     t.id));
                dropped++;
                continue;
            end
            key = key_model.banks[key_model.active_bank].key;
            mode_refmodel::process(t.mode, t.enc_dec, t.iv, key,
                                   t.blocks, exp_blocks);
            for (int i = 0; i < t.num_blocks; i++) begin
                exp_beat_t e;
                e.id       = t.id;
                e.mode     = t.mode;
                e.enc_dec  = t.enc_dec;
                e.in_blk   = t.blocks[i];
                e.exp_blk  = exp_blocks[i];
                e.t_create = t.t_create;
                pending.push_back(e);
            end
        end
    endtask

    // -----------------------------------------------------------------
    // compare_outputs: pop each output beat, match against pending head
    // -----------------------------------------------------------------
    task compare_outputs();
        aes_mon_item it;
        exp_beat_t   e;
        txn_log_t    r;
        forever begin
            out_mbox.get(it);
            if (pending.size() == 0) begin
                `LOG_ERROR($sformatf("unexpected OUT beat 0x%032h", it.data));
                errors++;
                continue;
            end
            e = pending.pop_front();
            compared++;
            if (e.exp_blk !== it.data) begin
                r.id                   = e.id;
                r.t_in                 = e.t_create;
                r.t_out                = it.t_evt;
                r.mode                 = e.mode;
                r.enc_dec              = e.enc_dec;
                r.data_in              = e.in_blk;
                r.iv_or_ctr            = '0;
                r.exp_out              = e.exp_blk;
                r.dut_out              = it.data;
                r.bank_at_accept       = it.bank_at_accept;
                r.bank_valid_at_accept = it.bank_valid_at_accept;
                r.bank_busy_at_accept  = it.bank_busy_at_accept;
                r.meta_count_at_accept = pending.size();
                r.note                 = "aes_scoreboard mismatch";
                $display("%s", format_mismatch(r));
                errors++;
                if (errors > tb_max_errors) begin
                    `LOG_FATAL("aes_scoreboard exceeded tb_max_errors");
                end
            end
        end
    endtask

    function void report_phase();
        $display("[aes_scoreboard] compared=%0d errors=%0d dropped=%0d pending=%0d",
                 compared, errors, dropped, pending.size());
    endfunction

endclass

`endif


// ============================================================================
//  aes_scoreboard.sv
//
//  Corrected scoreboard compatible with:
//
//  - variable pipeline latency
//  - corrected metadata architecture
//  - backpressure
//  - CBC/CFB/OFB feedback correctness
//  - CTR/GCM streaming
//
// ============================================================================

`timescale 1ns/1ps

import aes_pkg::*;
import aes_tb_pkg::*;

class aes_scoreboard;

    // =====================================================================
    // MAILBOX
    // =====================================================================

    mailbox #(aes_transaction) mon2sb;

    // =====================================================================
    // REFERENCE MODELS
    // =====================================================================

    aes_refmodel  aes_rm;
    mode_refmodel mode_rm;

    // =====================================================================
    // STATISTICS
    // =====================================================================

    int unsigned total_checked;
    int unsigned total_passed;
    int unsigned total_failed;

    // =====================================================================
    // CONSTRUCTOR
    // =====================================================================

    function new(
        mailbox #(aes_transaction) mon2sb
    );

        this.mon2sb = mon2sb;

        aes_rm  = new();
        mode_rm = new();

        total_checked = 0;
        total_passed  = 0;
        total_failed  = 0;

    endfunction

    // =====================================================================
    // RUN
    // =====================================================================

    task run();

        aes_transaction tr;

        aes_block_t aes_result;
        aes_block_t expected;

        forever begin

            mon2sb.get(tr);

            // -------------------------------------------------------------
            // RAW AES REFERENCE
            // -------------------------------------------------------------

            aes_result =
                aes_rm.process_block(
                    tr.data_in,
                    tr.enc_dec
                );

            // -------------------------------------------------------------
            // MODE REFERENCE
            // -------------------------------------------------------------

            expected =
                mode_rm.process_block(
                    tr.mode,
                    tr.enc_dec,
                    tr.data_in,
                    aes_result
                );

            total_checked++;

            // -------------------------------------------------------------
            // COMPARE
            // -------------------------------------------------------------

            if(expected !== tr.data_out) begin

                total_failed++;

                $display("\n================================================");
                $display("[SB FAIL]");
                $display("mode      = %s", tr.mode.name());
                $display("enc_dec   = %0d", tr.enc_dec);
                $display("data_in   = %h", tr.data_in);
                $display("expected  = %h", expected);
                $display("observed  = %h", tr.data_out);
                $display("latency   = %0d cycles", tr.latency_cycles);
                $display("time      = %0t", $time);
                $display("================================================\n");

            end

            else begin

                total_passed++;

                $display(
                    "[SB PASS] mode=%s data=%h",
                    tr.mode.name(),
                    tr.data_out
                );

            end

        end

    endtask

    // =====================================================================
    // REPORT
    // =====================================================================

    task report();

        $display("\n================================================");

        $display("[AES SCOREBOARD REPORT]");

        $display("Total Checked : %0d", total_checked);
        $display("Total Passed  : %0d", total_passed);
        $display("Total Failed  : %0d", total_failed);

        if(total_failed == 0)

            $display("[RESULT] PASS");

        else

            $display("[RESULT] FAIL");

        $display("================================================\n");

    endtask

endclass

*/

`timescale 1ns/1ps

import aes_pkg::*;
import aes_tb_pkg::*;

class aes_scoreboard;

    // =====================================================================
    // MAILBOXES
    // =====================================================================

    mailbox #(aes_transaction) expect_mbox;
    mailbox #(aes_transaction) in_mbox;
    mailbox #(aes_transaction) out_mbox;

    // =====================================================================
    // REFERENCE MODELS
    // =====================================================================

    //aes_refmodel  aes_rm;
    key_refmodel  key_model;

    // =====================================================================
    // INTERNALS
    // =====================================================================

    aes_transaction pending_q[$];

    int unsigned compared;
    int unsigned errors;

    string name;

    // =====================================================================
    // CONSTRUCTOR
    // =====================================================================

    function new(string n = "aes_scoreboard");

        name = n;

        expect_mbox = new();
        in_mbox     = new();
        out_mbox    = new();

       // aes_rm    = new();
        key_model = new();

        compared = 0;
        errors   = 0;

    endfunction

    // =====================================================================
    // NAME
    // =====================================================================

    function string get_name();
        return name;
    endfunction

    // =====================================================================
    // RUN
    // =====================================================================

    task run();

        fork
            absorb_inputs();
            absorb_outputs();
        join_none

    endtask

    // =====================================================================
    // INPUT ABSORB
    // =====================================================================

    task absorb_inputs();

        aes_transaction tr;

        forever begin

            in_mbox.get(tr);

            pending_q.push_back(
                tr.clone()
            );

        end

    endtask

    // =====================================================================
    // OUTPUT ABSORB
    // =====================================================================

    task absorb_outputs();

        aes_transaction tr;

        aes_transaction exp_tr;

        aes_block_t expected;
        aes_block_t key;

        aes_refmodel::rk_array_t rk;

        forever begin

            out_mbox.get(tr);

            if(pending_q.size() == 0) begin

                `LOG_ERROR(
                    "AES scoreboard output with empty queue"
                );

                errors++;
                continue;

            end

            exp_tr = pending_q.pop_front();

            if(!key_model.any_key_loaded()) begin

                `LOG_ERROR(
                    "AES scoreboard no key loaded"
                );

                errors++;
                continue;

            end

            key =
                key_model.banks[
                    key_model.active_bank
                ].key;

            aes_refmodel::expand_key(key, rk);

            // -------------------------------------------------------------
            // EXPECTED AES RESULT
            // -------------------------------------------------------------

            if(exp_tr.enc_dec)

              
                    expected =
    aes_refmodel::dec_block(
                        exp_tr.blocks[0],
                        rk
                    );

            else

                expected =
    aes_refmodel::enc_block(
                        exp_tr.blocks[0],
                        rk
                    );

            compared++;

            // -------------------------------------------------------------
            // COMPARE
            // -------------------------------------------------------------

            if(expected !== tr.blocks[0]) begin

                errors++;

                $display("\n====================================");
                $display("[AES SCOREBOARD FAIL]");
                $display("mode      = %s", exp_tr.mode.name());
                $display("enc_dec   = %0d", exp_tr.enc_dec);
                $display("expected  = %032h", expected);
                $display("observed  = %032h", tr.blocks[0]);
                $display("time      = %0t", $time);
                $display("====================================\n");

            end

            else begin

                $display(
                    "[SB PASS] mode=%s data=%032h",
                    exp_tr.mode.name(),
                    tr.blocks[0]
                );

            end

        end

    endtask

    // =====================================================================
    // REPORT
    // =====================================================================

    function void report_phase();

        $display("");
        $display("[aes_scoreboard]");
        $display("compared = %0d", compared);
        $display("errors   = %0d", errors);

    endfunction

endclass