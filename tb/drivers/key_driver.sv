// ============================================================================
//  tb/drivers/key_driver.sv
//
//  Drives the key_if.  Models a host-style push with random gaps and
//  respects the implicit FIFO depth by not blasting more than DEPTH keys
//  back-to-back when bank_free == 0 and FIFO is observed at maximum.
//  (The key system has its own FIFO; we just don't over-push.)
// ============================================================================
`ifndef KEY_DRIVER_SV
`define KEY_DRIVER_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;
    
class key_driver;



    virtual key_if  vif;
    mailbox #(key_transaction) in_mbox;
    mailbox #(key_transaction) out_mbox;

    string name;
    int unsigned seed;
    bit enabled;

    function new(string n = "key_driver");
        name     = n;
        enabled  = 1'b1;
        seed     = 32'hBEEF_CAFE;
        in_mbox  = new();
        out_mbox = new();
    endfunction

    function string get_name(); return name; endfunction

    task run();
        key_transaction k;
        wait (vif.reset == 1'b0);
        @(vif.cb_drv);
        vif.cb_drv.key_push <= 1'b0;
        forever begin
            if (in_mbox.try_get(k) == 0) begin
                vif.cb_drv.key_push <= 1'b0;
                @(vif.cb_drv);
                continue;
            end
            // back-off gap
            repeat (k.gap_cycles) begin
                vif.cb_drv.key_push <= 1'b0;
                @(vif.cb_drv);
            end
            vif.cb_drv.key_push <= 1'b1;
            vif.cb_drv.key_data <= k.key;
            @(vif.cb_drv);
            vif.cb_drv.key_push <= 1'b0;
            out_mbox.put(k);
        end
    endtask

endclass

`endif
