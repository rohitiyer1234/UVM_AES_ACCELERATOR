// ============================================================================
//  tb/drivers/aes_driver.sv
//
//  Drives the ctrl + stream interfaces with random-paced beats.
//
//  Behaviour
//  ---------
//  - Pulls `aes_transaction` objects from in_mbox.
//  - Sets mode/enc_dec on the cycle BEFORE the first beat and holds them
//    locked until the last beat is accepted (mode is "sticky").
//  - For modes that need an IV (CBC/CFB/OFB/CTR/GCM) the driver pulses
//    iv_load with iv_in on the cycle before the first beat.
//  - Drives in_valid/data_in with optional inter-block gaps from the
//    transaction's pacing knobs.
//  - Drives out_ready as a randomised stall.  Probability of stall per
//    cycle is `txn.output_stall_pct`.
//  - Emits the original txn (with t_create stamped) to out_mbox after
//    randomization so the scoreboard can predict expected outputs.
// ============================================================================
`ifndef AES_DRIVER_SV
`define AES_DRIVER_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;
    
    
class aes_driver;



    virtual aes_ctrl_if   ctrl_vif;
    virtual aes_stream_if stream_vif;

    mailbox #(aes_transaction) in_mbox;
    mailbox #(aes_transaction) out_mbox;

    string name;
    bit    enabled;

    // Use one shared RNG handle so reproducibility is preserved when the
    // driver is replicated under stress tests.
    int unsigned seed;

    function new(string n = "aes_driver");
        name     = n;
        enabled  = 1'b1;
        seed     = 32'hDEAD_BEEF;
        in_mbox  = new();
        out_mbox = new();
    endfunction

    function string get_name(); return name; endfunction

    // -----------------------------------------------------------------
    // run: main forever loop
    // -----------------------------------------------------------------
    task run();
        aes_transaction t;
        wait (ctrl_vif.reset == 1'b0);
        @(ctrl_vif.cb_drv);
        forever begin
            if (in_mbox.try_get(t) == 0) begin
                @(ctrl_vif.cb_drv);
                continue;
            end
            drive_one(t);
            out_mbox.put(t);
        end
        
    endtask

    // -----------------------------------------------------------------
    // out_ready_thread: independent stall injector.  Lives for the full
    // run; stall probability is taken from a class-level field updated
    // by drive_one for the current transaction.
    // -----------------------------------------------------------------
    int unsigned cur_stall_pct = 0;

    task out_ready_thread();
        int unsigned r;
        wait (stream_vif.reset == 1'b0);
        @(stream_vif.cb_drv);
        forever begin
            r = $urandom_range(99, 0);
            stream_vif.cb_drv.out_ready <= (r >= cur_stall_pct);
            @(stream_vif.cb_drv);
        end
    endtask

    // -----------------------------------------------------------------
    // drive_one: drive a single multi-block transaction
    // -----------------------------------------------------------------
    task drive_one(aes_transaction t);
        int unsigned gap;
        // sticky mode/enc_dec
        ctrl_vif.cb_drv.mode    <= t.mode;
        ctrl_vif.cb_drv.enc_dec <= t.enc_dec;

        // IV phase (skip for ECB)
        if (t.mode != MODE_ECB) begin
            ctrl_vif.cb_drv.iv_load <= 1'b1;
            ctrl_vif.cb_drv.iv_in   <= t.iv;
            @(ctrl_vif.cb_drv);
            ctrl_vif.cb_drv.iv_load <= 1'b0;
        end

        cur_stall_pct = t.output_stall_pct;

        for (int i = 0; i < t.num_blocks; i++) begin
            // optional gap before this beat
            gap = $urandom_range(t.input_gap_max, t.input_gap_min);
            repeat (gap) begin
                stream_vif.cb_drv.in_valid <= 1'b0;
                @(stream_vif.cb_drv);
            end
            
            
            
         $display("[DRV] txn=%0d block=%0d/%0d mode=%s data=%032h time=%0t",
         t.id,
         i,
         t.num_blocks,
         mode_name(t.mode),
         t.blocks[i],
         $time);
            // drive beat and wait for handshake
           stream_vif.cb_drv.in_valid <= 1'b1;
        stream_vif.cb_drv.data_in  <= t.blocks[i];

        // wait until DUT accepts beat
        do @(stream_vif.cb_drv);
        while (!stream_vif.cb_drv.in_ready);

        // immediately drop valid next cycle
        stream_vif.cb_drv.in_valid <= 1'b0;

        @(stream_vif.cb_drv);
          end
        //stream_vif.cb_drv.in_valid <= 1'b0;

        // record realtime accept-finish moment for debug
        t.t_create = $realtime;
    endtask
    
   
endclass

`endif
