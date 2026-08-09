// ============================================================================
//  tb/env/aes_env.sv
//
//  Pure-SV "environment" container.  Instantiates and wires all TB
//  components, exposes a single run() task that the test calls.
//
//  No factory, no UVM phasing.  Construction order:
//      1.  new()  - allocates everything
//      2.  connect()  - hands virtual interfaces to drivers/monitors/SBs
//      3.  start_threads() - forks the per-component run() tasks
//      4.  test code generates and pushes transactions
//      5.  finish() - waits for drain, calls report_phase()
// ============================================================================
`ifndef AES_ENV_SV
`define AES_ENV_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;
    
class aes_env;



    // ---- knobs ----
    aes_config cfg;

    // ---- DUT-facing virtual interfaces ----
    virtual aes_ctrl_if   ctrl_vif;
    virtual aes_stream_if stream_vif;
    virtual key_if        key_vif;
    virtual gcm_if        gcm_vif;

    // ---- components ----
    aes_driver      adrv;
    key_driver      kdrv;
    gcm_driver      gdrv;

    aes_monitor     amon;
    key_monitor     kmon;
    gcm_monitor     gmon;

    aes_scoreboard  asb;
    key_scoreboard  ksb;
    gcm_scoreboard  gsb;

    aes_coverage    cov;
    key_refmodel    key_model;

    string name;

    function new(string n = "aes_env");
        name      = n;
        cfg       = new();
        key_model = new();
        adrv      = new("aes_driver");
        kdrv      = new("key_driver");
        gdrv      = new("gcm_driver");
        amon      = new("aes_monitor");
        kmon      = new("key_monitor");
        gmon      = new("gcm_monitor");
        asb       = new("aes_scoreboard");
        ksb       = new("key_scoreboard");
        gsb       = new("gcm_scoreboard");
        cov       = new("aes_coverage");
        // share refmodel state
        asb.key_model = key_model;
        ksb.model     = key_model;
        gsb.key_model = key_model;
    endfunction

    function string get_name(); return name; endfunction

    // -----------------------------------------------------------------
    // connect: hand interfaces and wire mailboxes after the tb_top has
    // instantiated the physical interfaces.
    // -----------------------------------------------------------------
    function void connect();
        adrv.ctrl_vif   = ctrl_vif;
        adrv.stream_vif = stream_vif;
        kdrv.vif        = key_vif;
        gdrv.vif        = gcm_vif;

        amon.ctrl_vif   = ctrl_vif;
        amon.stream_vif = stream_vif;
        amon.key_vif    = key_vif;
        kmon.vif        = key_vif;
        gmon.vif        = gcm_vif;

        // ---------------------------------------------------------
        // AES scoreboard connections
        // ---------------------------------------------------------

        asb.expect_mbox = adrv.out_mbox;

        asb.in_mbox  = amon.in_mbox;
        asb.out_mbox = amon.out_mbox;

        // ---------------------------------------------------------
        // KEY scoreboard connections
        // ---------------------------------------------------------

       // Driver out mailbox feeds GCM expected channel
        gsb.expect_mbox = gdrv.out_mbox;
        ksb.mon_mbox = kmon.out_mbox;

        // ---------------------------------------------------------
        // GCM scoreboard connections
        // ---------------------------------------------------------

        gsb.mon_mbox = gmon.out_mbox;
        // Driver out mailbox feeds scoreboard expected channel
        ksb.tx_mbox = kdrv.out_mbox;
    endfunction

    // -----------------------------------------------------------------
    // start_threads: fork every component's run() under join_none.
    // -----------------------------------------------------------------
    task start_threads();
        tb_verbosity = cfg.verbosity;
        fork
            adrv.run();
            adrv.out_ready_thread();
            kdrv.run();
            gdrv.run();
            amon.run();
            kmon.run();
            gmon.run();
            asb.run();
            ksb.run();
            gsb.run();
        join_none
    endtask

    // -----------------------------------------------------------------
    // finish: drain and report.  `quiet_cycles` waits for that many
    // cycles of no activity before declaring done.
    // -----------------------------------------------------------------
    task finish(input int unsigned drain_cycles = 200000);

    repeat (drain_cycles)
        @(stream_vif.cb_drv);

    asb.report_phase();
    ksb.report_phase();
    gsb.report_phase();

    $display("");
    $display("=== ENV SUMMARY ===");

    $display("    aes_scoreboard errors = %0d (compared %0d)",
             asb.errors, asb.compared);

    $display("    key_scoreboard errors = %0d (pushes %0d)",
             ksb.errors, ksb.pushes_seen);

    $display("    gcm_scoreboard errors = %0d (tags %0d)",
             gsb.errors, gsb.compared);

    // ---------------------------------------------------------
    // Require minimum useful compare count
    // ---------------------------------------------------------

    if ((asb.errors == 0) &&
        (ksb.errors == 0) &&
        (gsb.errors == 0) &&
        (asb.compared > 10))
        $display("    PASS");
    else
        $display("    FAIL");

endtask

endclass

`endif
