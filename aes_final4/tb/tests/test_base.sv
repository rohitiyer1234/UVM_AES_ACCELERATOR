// ============================================================================
//  tb/tests/test_base.sv
//
//  Common test skeleton.  A concrete test extends test_base and overrides
//  `body()` and / or `configure()` only.
// ============================================================================
`ifndef TEST_BASE_SV
`define TEST_BASE_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;
    
class test_base;



    aes_env env;
    string  name;

    function new(string n = "test_base");
        name = n;
        env  = new();
    endfunction

    function string get_name(); return name; endfunction

    // -----------------------------------------------------------------
    // configure(): override to tweak env.cfg before run()
    // -----------------------------------------------------------------
    virtual function void configure();
        env.cfg.num_txns = 16;
    endfunction

    // -----------------------------------------------------------------
    // setup_keys(): push at least one key so the AES core has work to
    // do.  Default pushes a single deterministic key.
    // -----------------------------------------------------------------
    virtual task setup_keys();
        key_transaction k;
        k = new();
        k.key = 128'h00112233_44556677_8899AABB_CCDDEEFF;
        k.gap_cycles = 2;
        // Push to driver only - it forwards to its out_mbox after driving,
        // which env.connect() wired to ksb.tx_mbox so the scoreboard sees
        // the push exactly once.
        env.kdrv.in_mbox.put(k);
        repeat (60) @(env.stream_vif.cb_drv);
    endtask

    // -----------------------------------------------------------------
    // body(): main stimulus.  Override for each test.
    // -----------------------------------------------------------------
    virtual task body();
        aes_transaction t;
        for (int i = 0; i < env.cfg.num_txns; i++) begin
            t = new();
            if (!t.randomize() with {
                num_blocks inside {[env.cfg.blocks_min:env.cfg.blocks_max]};
                input_gap_min inside {[env.cfg.input_gap_min:env.cfg.input_gap_max]};
                input_gap_max inside {[input_gap_min:env.cfg.input_gap_max]};
                output_stall_pct inside {[env.cfg.stall_pct_min:env.cfg.stall_pct_max]};
            }) begin
                `LOG_ERROR("aes_transaction randomize failed");
                return;
            end
            env.adrv.in_mbox.put(t);
            env.asb.expect_mbox.put(t);
        end
    endtask

    // -----------------------------------------------------------------
    // run(): full test flow.  Called by tb_aes_top after reset.
    // -----------------------------------------------------------------
    task run();
        configure();
        env.connect();
        env.start_threads();
        setup_keys();
        body();
        // Wait for pipelines + scoreboard drain
        repeat (50000)
            @(env.stream_vif.cb_drv);
        env.finish(2000);
    endtask

endclass

`endif
