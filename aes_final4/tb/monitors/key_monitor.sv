// ============================================================================
//  tb/monitors/key_monitor.sv
//
//  Snapshots the dual-bank key state on every change so the scoreboard
//  can correlate keys with in-flight transactions and detect bank-state
//  rule violations.
// ============================================================================
`ifndef KEY_MONITOR_SV
`define KEY_MONITOR_SV


    import aes_pkg::*;
    import aes_tb_pkg::*;
    
class key_mon_item;
 
    aes_block_t  pushed_key;
    bit          push_seen;
    bit  [1:0]   bank_valid;
    bit  [1:0]   bank_busy;
    bit  [1:0]   bank_free;
    realtime     t_evt;
endclass

class key_monitor;



    virtual key_if vif;
    mailbox #(key_mon_item) out_mbox;

    string name;

    function new(string n = "key_monitor");
        name     = n;
        out_mbox = new();
    endfunction

    function string get_name(); return name; endfunction

    task run();
        key_mon_item it;
        bit  [1:0] last_bv, last_bb, last_bf;
        bit         first_sample;
        first_sample = 1'b1;
        wait (vif.reset == 1'b0);
        forever begin
            @(vif.cb_mon);
            // emit on push, or on any state change
            if (vif.cb_mon.key_push
                || first_sample
                || vif.cb_mon.bank_valid != last_bv
                || vif.cb_mon.bank_busy  != last_bb
                || vif.cb_mon.bank_free  != last_bf) begin
                it = new();
                it.pushed_key = vif.cb_mon.key_data;
                it.push_seen  = vif.cb_mon.key_push;
                it.bank_valid = vif.cb_mon.bank_valid;
                it.bank_busy  = vif.cb_mon.bank_busy;
                it.bank_free  = vif.cb_mon.bank_free;
                it.t_evt      = $realtime;
                out_mbox.put(it);
                last_bv = vif.cb_mon.bank_valid;
                last_bb = vif.cb_mon.bank_busy;
                last_bf = vif.cb_mon.bank_free;
                first_sample = 1'b0;
                `LOG_HIGH($sformatf("KEY ev push=%0d v=%02b b=%02b f=%02b",
                                    it.push_seen, it.bank_valid,
                                    it.bank_busy, it.bank_free));
            end
        end
    endtask

endclass

`endif
