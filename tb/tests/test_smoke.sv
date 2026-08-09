// ============================================================================
//  test_smoke.sv
//  One block per mode, no stalls.  Validates compile + basic correctness.
// ============================================================================
`ifndef TEST_SMOKE_SV
`define TEST_SMOKE_SV

class test_smoke extends test_base;

    function new(string n = "test_smoke"); super.new(n); endfunction

    virtual function void configure();
        env.cfg.num_txns   = 6;
        env.cfg.blocks_min = 1;
        env.cfg.blocks_max = 2;
        env.cfg.stall_pct_min = 0;
        env.cfg.stall_pct_max = 0;
        env.cfg.verbosity  = aes_tb_pkg::VRB_LOW;
    endfunction

    virtual task body();
        aes_mode_e modes [] = '{ MODE_ECB, MODE_CBC, MODE_CFB,
                                  MODE_OFB, MODE_CTR };
        foreach (modes[i]) begin
            aes_transaction t = new();
            t.mode    = modes[i];
            t.enc_dec = 1'b0;
            t.num_blocks = 1;
            t.iv = 128'h0;
            t.blocks = new[1];
            t.blocks[0] = 128'h00000000_00000000_00000000_00000000;
            t.input_gap_min = 0;
            t.input_gap_max = 0;
            t.output_stall_pct = 0;
            env.adrv.in_mbox.put(t);
            env.asb.expect_mbox.put(t);
        end
        // decrypt back-tests for ECB/CBC
        begin
            aes_transaction d = new();
            d.mode = MODE_ECB;
            d.enc_dec = 1'b1;
            d.num_blocks = 1;
            d.iv = 128'h0;
            d.blocks = new[1];
            d.blocks[0] = 128'h11111111_22222222_33333333_44444444;
            d.input_gap_min = 0; d.input_gap_max = 0; d.output_stall_pct = 0;
            env.adrv.in_mbox.put(d);
            env.asb.expect_mbox.put(d);
        end
    endtask

endclass

`endif
