// ============================================================================
//  tb/coverage/aes_coverage.sv
//
//  Centralised covergroups.  Sampled by the env on monitor events.
//  Each covergroup has an explicit purpose comment so closure reports
//  remain meaningful.
// ============================================================================
`ifndef AES_COVERAGE_SV
`define AES_COVERAGE_SV

import aes_pkg::*;
import aes_tb_pkg::*;


class aes_coverage;

    

    // ----------------------- Sample storage -----------------------
    aes_mode_e   cv_mode;
    bit          cv_enc;
    int unsigned cv_size_bin;       // 0=small 1=med 2=large
    aes_mode_e   cv_prev_mode;
    int unsigned cv_stall_density;  // 0..4
    bit          cv_bank_active;
    bit  [1:0]   cv_bank_valid;
    bit  [1:0]   cv_bank_busy;
    int unsigned cv_inflight;
    int unsigned cv_aad_blocks;
    int unsigned cv_pld_blocks;
    int unsigned cv_gcm_phase;
    bit          cv_override_active;
    int unsigned cv_serial_wait_cyc;
    int unsigned cv_reset_recover_cyc;

    string name;

    // -----------------------------------------------------------------
    // cg_mode : mode x enc/dec x payload size
    // -----------------------------------------------------------------
    covergroup cg_mode;
        coverpoint cv_mode {
            bins ecb = {MODE_ECB};
            bins cbc = {MODE_CBC};
            bins cfb = {MODE_CFB};
            bins ofb = {MODE_OFB};
            bins ctr = {MODE_CTR};
            bins gcm = {MODE_GCM};
        }
        coverpoint cv_enc { bins enc = {1'b0}; bins dec = {1'b1}; }
        coverpoint cv_size_bin { bins s = {0}; bins m = {1}; bins l = {2}; }
        cross cv_mode, cv_enc, cv_size_bin;
    endgroup

    // -----------------------------------------------------------------
    // cg_mode_transitions : prev_mode -> curr_mode legality matrix
    // -----------------------------------------------------------------
    covergroup cg_mode_transitions;
        prev: coverpoint cv_prev_mode;
        curr: coverpoint cv_mode;
        cross prev, curr;
    endgroup

    // -----------------------------------------------------------------
    // cg_backpressure : stall density x mode
    // -----------------------------------------------------------------
    covergroup cg_backpressure;
        coverpoint cv_stall_density {
            bins none  = {0};
            bins low   = {1};
            bins med   = {2};
            bins high  = {3};
            bins fully = {4};
        }
        coverpoint cv_mode;
        cross cv_stall_density, cv_mode;
    endgroup

    // -----------------------------------------------------------------
    // cg_key_banks : bank state combinations
    // -----------------------------------------------------------------
    covergroup cg_key_banks;
        coverpoint cv_bank_active;
        coverpoint cv_bank_valid;
        coverpoint cv_bank_busy;
        cross cv_bank_active, cv_bank_valid, cv_bank_busy;
    endgroup

    // -----------------------------------------------------------------
    // cg_dual_bank_swap : track inflight count across swaps
    // -----------------------------------------------------------------
    covergroup cg_dual_bank_swap;
        coverpoint cv_inflight {
            bins zero  = {0};
            bins few   = {[1:3]};
            bins many  = {[4:10]};
            bins deep  = {[11:32]};
        }
    endgroup

    // -----------------------------------------------------------------
    // cg_gcm : phase x lengths
    // -----------------------------------------------------------------
    covergroup cg_gcm;
        coverpoint cv_gcm_phase {
            bins idle    = {0};
            bins h_gen   = {1};
            bins j0_gen  = {2};
            bins aad     = {3};
            bins payload = {4};
            bins len     = {5};
            bins tag     = {6};
        }
        coverpoint cv_aad_blocks {
            bins z = {0};
            bins s = {[1:2]};
            bins m = {[3:5]};
            bins l = {[6:8]};
        }
        coverpoint cv_pld_blocks {
            bins s = {[1:8]};
            bins m = {[9:32]};
            bins l = {[33:64]};
        }
        cross cv_aad_blocks, cv_pld_blocks;
    endgroup

    // -----------------------------------------------------------------
    // cg_override : did override transactions actually fire?
    // -----------------------------------------------------------------
    covergroup cg_override;
        coverpoint cv_override_active;
        cross cv_override_active, cv_gcm_phase;
    endgroup

    // -----------------------------------------------------------------
    // cg_serialization : feedback_waiting cycles in CBC-enc / CFB / OFB
    // -----------------------------------------------------------------
    covergroup cg_serialization;
        coverpoint cv_serial_wait_cyc {
            bins zero  = {0};
            bins one   = {1};
            bins few   = {[2:5]};
            bins many  = {[6:32]};
        }
    endgroup

    // -----------------------------------------------------------------
    // cg_reset_recovery : cycles until first valid output after reset
    // -----------------------------------------------------------------
    covergroup cg_reset_recovery;
        coverpoint cv_reset_recover_cyc {
            bins fast   = {[0:30]};
            bins normal = {[31:200]};
            bins slow   = {[201:1000]};
        }
    endgroup

    function new(string n = "aes_coverage");
        name = n;
        cg_mode             = new();
        cg_mode_transitions = new();
        cg_backpressure     = new();
        cg_key_banks        = new();
        cg_dual_bank_swap   = new();
        cg_gcm              = new();
        cg_override         = new();
        cg_serialization    = new();
        cg_reset_recovery   = new();
    endfunction

    function string get_name(); return name; endfunction

    // -----------------------------------------------------------------
    // Sample helpers - the env calls the right one at the right moment.
    // -----------------------------------------------------------------
    function void sample_txn(aes_mode_e m, bit enc, int unsigned blocks,
                             int unsigned stall_pct, aes_mode_e prev);
        cv_mode  = m;
        cv_enc   = enc;
        cv_prev_mode = prev;
        cv_size_bin  = (blocks <= 4) ? 0 : (blocks <= 16 ? 1 : 2);
        cv_stall_density = (stall_pct <  5) ? 0 :
                           (stall_pct < 25) ? 1 :
                           (stall_pct < 75) ? 2 :
                           (stall_pct < 99) ? 3 : 4;
        cg_mode.sample();
        cg_mode_transitions.sample();
        cg_backpressure.sample();
    endfunction

    function void sample_key_state(bit active, bit [1:0] valid,
                                   bit [1:0] busy, int unsigned inflight);
        cv_bank_active = active;
        cv_bank_valid  = valid;
        cv_bank_busy   = busy;
        cv_inflight    = inflight;
        cg_key_banks.sample();
        cg_dual_bank_swap.sample();
    endfunction

    function void sample_gcm(int unsigned phase, int unsigned aad,
                             int unsigned pld, bit override_active);
        cv_gcm_phase       = phase;
        cv_aad_blocks      = aad;
        cv_pld_blocks      = pld;
        cv_override_active = override_active;
        cg_gcm.sample();
        cg_override.sample();
    endfunction

    function void sample_serialization(int unsigned cyc);
        cv_serial_wait_cyc = cyc;
        cg_serialization.sample();
    endfunction

    function void sample_reset_recovery(int unsigned cyc);
        cv_reset_recover_cyc = cyc;
        cg_reset_recovery.sample();
    endfunction

endclass

`endif
