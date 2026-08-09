// ============================================================================
//  tb/transactions/key_transaction.sv
//
//  Single 128-bit key push.  The driver schedules these at random gaps
//  across the simulation; the key system handles FIFO buffering and
//  expansion into the dual-bank store.
// ============================================================================
`ifndef KEY_TRANSACTION_SV
`define KEY_TRANSACTION_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;


class key_transaction;


    rand aes_block_t  key;
    rand int unsigned gap_cycles;

    int unsigned id;
    realtime     t_create;

    constraint c_default {
        gap_cycles inside {[1:64]};
    }

    function new();
        id       = tb_next_id();
        t_create = $realtime;
    endfunction

    function string convert2string();
        return $sformatf("KEY id=%0d gap=%0d key=0x%032h", id, gap_cycles, key);
    endfunction

endclass

`endif
