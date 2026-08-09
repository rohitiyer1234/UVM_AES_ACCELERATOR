// ============================================================================
//  tb/drivers/gcm_driver.sv
//
//  Drives the gcm_if for a complete GCM session.
//
//  Sequence (coordinated with aes_driver via shared events):
//      1.  set mode=GCM via ctrl interface (done by aes_driver before
//          handing control)
//      2.  drive gcm_iv and pulse iv_load (the aes_driver handles iv_load
//          as part of its IV phase; we just supply gcm_iv on the iv_load
//          cycle)
//      3.  stream AAD beats with aad_valid, holding aad_data; pulse
//          aad_last on the final block
//      4.  notify aes_driver to push the payload blocks
//      5.  wait for the payload's last accept then pulse payload_last
//      6.  wait for tag_valid and emit the captured tag in out_mbox
// ============================================================================
`ifndef GCM_DRIVER_SV
`define GCM_DRIVER_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;
    
class gcm_driver;



    virtual gcm_if vif;

    mailbox #(gcm_transaction) in_mbox;
    mailbox #(gcm_transaction) out_mbox;

    event e_iv_loaded;
    event e_aad_done;
    event e_payload_done;

    string name;

    function new(string n = "gcm_driver");
        name     = n;
        in_mbox  = new();
        out_mbox = new();
    endfunction

    function string get_name(); return name; endfunction

    task run();
        gcm_transaction t;
        wait (vif.reset == 1'b0);
        @(vif.cb_drv);
        vif.cb_drv.aad_valid    <= 1'b0;
        vif.cb_drv.aad_last     <= 1'b0;
        vif.cb_drv.payload_last <= 1'b0;
        forever begin
            if (in_mbox.try_get(t) == 0) begin
                @(vif.cb_drv);
                continue;
            end
            drive_session(t);
            out_mbox.put(t);
        end
    endtask

    // -----------------------------------------------------------------
    // drive_session: orchestrate one full GCM session.
    // The aes_driver is responsible for setting mode=GCM/enc_dec, pulsing
    // iv_load with iv_in (we mirror to gcm_iv here), and pushing the
    // payload beats once we signal e_aad_done.
    // -----------------------------------------------------------------
    task drive_session(gcm_transaction t);
        // expose gcm_iv across the run; aes_driver triggers iv_load
        vif.cb_drv.gcm_iv       <= t.iv96;
        vif.cb_drv.expected_tag <= t.expected_tag;

        ->e_iv_loaded;

        // ------------------- AAD phase -------------------
        for (int i = 0; i < t.aad_blocks; i++) begin
            vif.cb_drv.aad_valid <= 1'b1;
            vif.cb_drv.aad_data  <= t.aad[i];
            vif.cb_drv.aad_last  <= (i == t.aad_blocks - 1);
            do @(vif.cb_drv);
            while (!vif.cb_drv.aad_ready);
        end
        if (t.aad_blocks == 0) begin
            // no AAD: still must pulse aad_last so orchestrator can move on
            vif.cb_drv.aad_valid <= 1'b0;
            vif.cb_drv.aad_last  <= 1'b1;
            @(vif.cb_drv);
        end
        vif.cb_drv.aad_valid <= 1'b0;
        vif.cb_drv.aad_last  <= 1'b0;
        ->e_aad_done;

        // ------------------- Payload phase -------------------
        // The aes_driver streams t.pld[].  We wait for e_payload_done
        // and then pulse payload_last for one cycle.
        @(e_payload_done);
        vif.cb_drv.payload_last <= 1'b1;
        @(vif.cb_drv);
        vif.cb_drv.payload_last <= 1'b0;

        // ------------------- Tag wait -------------------
        do @(vif.cb_drv);
        while (!vif.cb_drv.tag_valid);
    endtask

endclass

`endif
