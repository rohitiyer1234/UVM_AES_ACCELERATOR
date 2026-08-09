// ============================================================================
//  test_mode_switch.sv
//  Issue short bursts that rotate through every mode at idle boundaries.
// ============================================================================
`ifndef TEST_MODE_SWITCH_SV
`define TEST_MODE_SWITCH_SV

class test_mode_switch extends test_base;

    function new(string n = "test_mode_switch"); super.new(n); endfunction

    virtual function void configure();
        env.cfg.num_txns      = 60;
        env.cfg.blocks_min    = 1;
        env.cfg.blocks_max    = 3;
        env.cfg.input_gap_min = 1;
        env.cfg.input_gap_max = 6;
        env.cfg.stall_pct_min = 10;
        env.cfg.stall_pct_max = 30;
        env.cfg.verbosity     = aes_tb_pkg::VRB_LOW;
    endfunction

    virtual task body();
        aes_mode_e seq [] = '{MODE_ECB, MODE_CBC, MODE_CFB, MODE_OFB, MODE_CTR};
        for (int i = 0; i < env.cfg.num_txns; i++) begin
            aes_transaction t = new();
            t.mode = seq[i % seq.size()];
            if (!t.randomize() with {
                mode == seq[i % seq.size()];
                num_blocks inside {[1:3]};
                input_gap_min inside {[1:6]};
                input_gap_max inside {[input_gap_min:6]};
                output_stall_pct inside {[10:30]};
            }) `LOG_ERROR("randomize failed");
            env.adrv.in_mbox.put(t);
            env.asb.expect_mbox.put(t);
        end
    endtask

endclass

`endif
