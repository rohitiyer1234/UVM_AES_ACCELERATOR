// ============================================================================
//  test_random_stress.sv
//  Heavy constrained-random stress: many transactions, random modes,
//  random pacing, random stalls.
// ============================================================================
`ifndef TEST_RANDOM_STRESS_SV
`define TEST_RANDOM_STRESS_SV

class test_random_stress extends test_base;

    function new(string n = "test_random_stress"); super.new(n); endfunction

    virtual function void configure();
        env.cfg.num_txns       = 500;
        env.cfg.blocks_min     = 1;
        env.cfg.blocks_max     = 16;
        env.cfg.input_gap_min  = 0;
        env.cfg.input_gap_max  = 6;
        env.cfg.stall_pct_min  = 0;
        env.cfg.stall_pct_max  = 30;
        env.cfg.verbosity      = aes_tb_pkg::VRB_LOW;
    endfunction

endclass

`endif
