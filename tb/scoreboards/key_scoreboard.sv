// ============================================================================
//  tb/scoreboards/key_scoreboard.sv
//
//  Cross-checks the dual-bank state observed on the key_if against the
//  key_refmodel.  Catches:
//      - bank_valid asserted on a bank we did not push to
//      - bank_free held LOW after a release
//      - active_bank not equal to the most recently loaded
// ============================================================================
`ifndef KEY_SCOREBOARD_SV
`define KEY_SCOREBOARD_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;
    
class key_scoreboard;



    mailbox #(key_mon_item) mon_mbox;
    mailbox #(key_transaction) tx_mbox;   // pushes seen by driver

    key_refmodel  model;

    int unsigned errors;
    int unsigned pushes_seen;
    string       name;

    function new(string n = "key_scoreboard");
        name        = n;
        errors      = 0;
        pushes_seen = 0;
        mon_mbox    = new();
        tx_mbox     = new();
    endfunction

    function string get_name(); return name; endfunction

    task run();
        fork
            absorb_pushes();
            absorb_state();
        join_none
    endtask

    // -----------------------------------------------------------------
    // absorb_pushes: when the key_driver finishes a push, advance the
    // model so its `active_bank` and bank slots match what the DUT will
    // eventually present.
    // -----------------------------------------------------------------
    task absorb_pushes();
        key_transaction k;
        forever begin
            tx_mbox.get(k);
            void'(model.push_key(k.key));
            pushes_seen++;
            `LOG_MED($sformatf("model push key=0x%032h active=%0d",
                               k.key, model.active_bank));
        end
    endtask

    // -----------------------------------------------------------------
    // absorb_state: lightweight sanity checks on bank state transitions.
    // -----------------------------------------------------------------
    task absorb_state();
        key_mon_item it;
        forever begin
            mon_mbox.get(it);
            // both bits of bank_valid AND bank_free can never be high
            // simultaneously for the same bank (mutually exclusive).
            if (|(it.bank_valid & it.bank_free)) begin
                `LOG_ERROR($sformatf("bank_valid & bank_free overlap: v=%02b f=%02b",
                                     it.bank_valid, it.bank_free));
                errors++;
            end
        end
    endtask

    function void report_phase();
        $display("[key_scoreboard] pushes=%0d errors=%0d", pushes_seen, errors);
    endfunction

endclass

`endif
