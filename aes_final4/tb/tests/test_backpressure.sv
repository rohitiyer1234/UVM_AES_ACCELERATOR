// ============================================================================
//  test_backpressure.sv
//  Aggressive out_ready stall + variable input gaps.
// ============================================================================
`ifndef TEST_BACKPRESSURE_SV
`define TEST_BACKPRESSURE_SV

class test_backpressure extends test_base;

    function new(string n = "test_backpressure"); super.new(n); endfunction

    virtual function void configure();
        env.cfg.num_txns       = 200;
        env.cfg.blocks_min     = 4;
        env.cfg.blocks_max     = 12;
        env.cfg.input_gap_min  = 0;
        env.cfg.input_gap_max  = 8;
        env.cfg.stall_pct_min  = 50;
        env.cfg.stall_pct_max  = 90;
        env.cfg.verbosity      = aes_tb_pkg::VRB_LOW;
    endfunction

endclass

`endif
