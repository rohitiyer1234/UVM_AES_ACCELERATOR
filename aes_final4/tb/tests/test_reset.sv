// ============================================================================
//  test_reset.sv
//  Periodically asserts an extra synchronous reset to verify recovery.
//  Reset is implemented by writing to a shared `force_reset` event that
//  tb_aes_top observes - see tb_aes_top for the wiring.
// ============================================================================
`ifndef TEST_RESET_SV
`define TEST_RESET_SV

class test_reset extends test_base;

    function new(string n = "test_reset"); super.new(n); endfunction

    virtual function void configure();
        env.cfg.num_txns       = 200;
        env.cfg.blocks_min     = 1;
        env.cfg.blocks_max     = 6;
        env.cfg.input_gap_min  = 0;
        env.cfg.input_gap_max  = 4;
        env.cfg.stall_pct_min  = 0;
        env.cfg.stall_pct_max  = 30;
        env.cfg.inject_resets  = 1'b1;
        env.cfg.reset_interval = 1500;
        env.cfg.verbosity      = aes_tb_pkg::VRB_LOW;
    endfunction

endclass

`endif
