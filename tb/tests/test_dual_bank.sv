// ============================================================================
//  test_dual_bank.sv
//  Rapid back-to-back key pushes while data is in flight.  Forces bank
//  rotation, exercises bank_busy / bank_free invariants.
// ============================================================================
`ifndef TEST_DUAL_BANK_SV
`define TEST_DUAL_BANK_SV

class test_dual_bank extends test_base;

    function new(string n = "test_dual_bank"); super.new(n); endfunction

    virtual function void configure();
        env.cfg.num_txns      = 80;
        env.cfg.num_keys      = 16;
        env.cfg.blocks_min    = 1;
        env.cfg.blocks_max    = 4;
        env.cfg.input_gap_min = 0;
        env.cfg.input_gap_max = 2;
        env.cfg.stall_pct_min = 0;
        env.cfg.stall_pct_max = 20;
        env.cfg.verbosity     = aes_tb_pkg::VRB_LOW;
    endfunction

    // Override setup_keys to push many keys at low gaps.
    virtual task setup_keys();
        for (int i = 0; i < env.cfg.num_keys; i++) begin
            key_transaction k = new();
            k.gap_cycles = 8;
            k.key = {32'hCAFE_0000 + i, 32'h0BAD_F00D,
                     32'hDEAD_BEEF, 32'hFEED_FACE};
            env.kdrv.in_mbox.put(k);
        end
        repeat (200) @(env.stream_vif.cb_drv);
    endtask

endclass

`endif
