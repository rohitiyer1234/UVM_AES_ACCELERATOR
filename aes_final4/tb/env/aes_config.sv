// ============================================================================
//  tb/env/aes_config.sv
//
//  Randomisable test knobs.  A test populates this once before invoking
//  env.run().  Tests can also override fields directly after randomize().
// ============================================================================
`ifndef AES_CONFIG_SV
`define AES_CONFIG_SV

import aes_pkg::*;
import aes_tb_pkg::*;

class aes_config;

    
    // ---- counts ----
    rand int unsigned num_txns;
    rand int unsigned num_keys;
    rand int unsigned num_gcm_sessions;

    // ---- pacing ----
    rand int unsigned input_gap_min;
    rand int unsigned input_gap_max;
    rand int unsigned stall_pct_min;
    rand int unsigned stall_pct_max;

    // ---- mode mix (set as weights for the test) ----
    rand int unsigned w_ecb, w_cbc, w_cfb, w_ofb, w_ctr, w_gcm;

    // ---- payload sizes ----
    rand int unsigned blocks_min;
    rand int unsigned blocks_max;

    // ---- runtime knobs ----
    rand int unsigned verbosity;
    rand bit          inject_resets;
    rand int unsigned reset_interval;

    constraint c_defaults {
        num_txns          inside {[1:5000]};
        num_keys          inside {[1:128]};
        num_gcm_sessions  inside {[0:32]};

        input_gap_min     inside {[0:4]};
        input_gap_max     inside {[input_gap_min:16]};
        stall_pct_min     inside {[0:100]};
        stall_pct_max     inside {[stall_pct_min:100]};

        w_ecb >= 0; w_cbc >= 0; w_cfb >= 0;
        w_ofb >= 0; w_ctr >= 0; w_gcm >= 0;
        (w_ecb + w_cbc + w_cfb + w_ofb + w_ctr + w_gcm) > 0;

        blocks_min inside {[1:8]};
        blocks_max inside {[blocks_min:64]};

        verbosity       inside {VRB_NONE, VRB_LOW, VRB_MED, VRB_HIGH, VRB_DEBUG};
        inject_resets   dist {0 := 5, 1 := 1};
        reset_interval  inside {[200:50000]};
    }

    function new();
        // smoke defaults
        num_txns         = 32;
        num_keys         = 2;
        num_gcm_sessions = 1;
        input_gap_min    = 0;
        input_gap_max    = 4;
        stall_pct_min    = 0;
        stall_pct_max    = 25;
        w_ecb = 1; w_cbc = 1; w_cfb = 1;
        w_ofb = 1; w_ctr = 1; w_gcm = 1;
        blocks_min       = 1;
        blocks_max       = 8;
        verbosity        = VRB_LOW;
        inject_resets    = 0;
        reset_interval   = 5000;
    endfunction

endclass

`endif
