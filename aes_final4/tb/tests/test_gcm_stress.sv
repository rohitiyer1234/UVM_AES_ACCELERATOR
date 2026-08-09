// ============================================================================
//  test_gcm_stress.sv
//  Random AAD + payload sizes, multiple sessions back-to-back.
//  Coordinates with the aes_driver and gcm_driver via event/mailbox.
// ============================================================================
`ifndef TEST_GCM_STRESS_SV
`define TEST_GCM_STRESS_SV

class test_gcm_stress extends test_base;

    function new(string n = "test_gcm_stress"); super.new(n); endfunction

    virtual function void configure();
        env.cfg.num_gcm_sessions = 4;
        env.cfg.verbosity        = aes_tb_pkg::VRB_LOW;
    endfunction

    virtual task body();
        gcm_transaction g;
        aes_transaction t;
        for (int s = 0; s < env.cfg.num_gcm_sessions; s++) begin
            g = new();
            if (!g.randomize() with {
                aad_blocks     inside {[0:4]};
                payload_blocks inside {[1:16]};
            }) `LOG_ERROR("gcm randomize failed");
            env.gsb.expect_mbox.put(g);
            env.gdrv.in_mbox.put(g);

            // Build the matching AES transaction representing the
            // GCM payload (so the aes_driver pushes it through the
            // data stream while orchestrator runs).
            t = new();
            t.mode             = MODE_GCM;
            t.enc_dec          = 1'b0;
            t.num_blocks       = g.payload_blocks;
            t.iv               = '0;
            t.blocks           = g.pld;
            t.input_gap_min    = 0;
            t.input_gap_max    = 2;
            t.output_stall_pct = 10;
            env.adrv.in_mbox.put(t);
        end
    endtask

endclass

`endif
