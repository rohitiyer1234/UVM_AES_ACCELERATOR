
// ============================================================================
//  tb/scoreboards/gcm_scoreboard.sv
//
//  For each GCM transaction (gcm_transaction handed in via expect_mbox):
//    1.  Compute expected ciphertext via gcm_refmodel::ctr_encrypt
//    2.  Compute expected tag    via gcm_refmodel::compute_tag
//    3.  When the next tag arrives from gcm_monitor, compare
// ============================================================================
`ifndef GCM_SCOREBOARD_SV
`define GCM_SCOREBOARD_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;
    import gcm_refmodel::*;
    
class gcm_scoreboard;



    mailbox #(gcm_transaction) expect_mbox;
    mailbox #(gcm_mon_item) mon_mbox;
    key_refmodel               key_model;

    int unsigned compared;
    int unsigned errors;
    string       name;

    // queue of pending expected tags, one per session
    aes_block_t  exp_tags [$];
    int unsigned exp_ids  [$];

    function new(string n = "gcm_scoreboard");
        name        = n;
        compared    = 0;
        errors      = 0;
        expect_mbox = new();
        mon_mbox    = new();
    endfunction

    function string get_name(); return name; endfunction

    task run();
        fork
            absorb_expected();
            absorb_tags();
        join_none
    endtask

    task absorb_expected();
        gcm_transaction t;
        aes_block_t     ct [];
        aes_block_t     tag;
        aes_block_t     key;
        forever begin
            expect_mbox.get(t);
            if (!key_model.any_key_loaded()) begin
                `LOG_ERROR("GCM expected but no key loaded");
                continue;
            end
            key = key_model.banks[key_model.active_bank].key;
            ctr_encrypt(t.iv96, key, t.pld, ct);
            tag = compute_tag(t.iv96, key, t.aad, ct);
            t.expected_tag = tag;
            exp_tags.push_back(tag);
            exp_ids.push_back(t.id);
        end
    endtask

    task absorb_tags();
    gcm_mon_item it;
        aes_block_t  exp;
        int unsigned exp_id;
        forever begin
            mon_mbox.get(it);
            if (it.kind != gcm_mon_item::EV_TAG)
    continue;
            if (exp_tags.size() == 0) begin
                `LOG_ERROR($sformatf("unexpected TAG 0x%032h", it.data));
                errors++;
                continue;
            end
            exp    = exp_tags.pop_front();
            exp_id = exp_ids.pop_front();
            compared++;
           if (exp !== it.data) begin
                $display("--- GCM TAG MISMATCH id=%0d t=%0t ---", exp_id, $time);
                $display("    expected: 0x%032h", exp);
                $display("    got     : 0x%032h", it.data);
                $display("    diff    : 0x%032h", exp ^ it.data);
                errors++;
                if (errors > tb_max_errors)
                    `LOG_FATAL("gcm_scoreboard exceeded tb_max_errors");
            end
        end
    endtask

    function void report_phase();
        $display("[gcm_scoreboard] compared=%0d errors=%0d", compared, errors);
    endfunction

endclass

`endif
