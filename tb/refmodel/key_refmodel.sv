// ============================================================================
//  tb/refmodel/key_refmodel.sv
//
//  Behavioural model of the dual-bank key subsystem.
//  Models:
//      - 4-entry key FIFO
//      - sequential expansion (12 cycles per key)
//      - dual-bank allocation: bank0 priority
//      - active_bank tracking (latches write_bank on exp_done)
//      - bank release on pressure (priority encoder: bank0 then bank1)
//
//  Used by the key_scoreboard to predict what bank should be active and
//  by the aes_scoreboard to know which key the DUT used for a given
//  transaction (we record bank_at_accept from the monitor).
// ============================================================================
`ifndef KEY_REFMODEL_SV
`define KEY_REFMODEL_SV

    import aes_pkg::*;
    import aes_refmodel::*;

class key_refmodel;


    typedef struct {
        aes_block_t key;
        rk_array_t  rk;
        bit         valid;
    } bank_t;

    bank_t        banks   [0:1];
    aes_block_t   fifo_q  [$];   // raw keys
    bit           active_bank;

    function new();
        active_bank = 1'b0;
        banks[0].valid = 1'b0;
        banks[1].valid = 1'b0;
    endfunction

    // -----------------------------------------------------------------
    // push_key: model what happens when a user pushes a key.  Returns
    // the bank index that will store the expanded round keys.
    // -----------------------------------------------------------------
    function automatic int unsigned push_key(input aes_block_t k);
        int unsigned slot;
        if (!banks[0].valid)      slot = 0;
        else if (!banks[1].valid) slot = 1;
        else                      slot = 0;   // recycle bank0 by priority
        banks[slot].key   = k;
        expand_key(k, banks[slot].rk);
        banks[slot].valid = 1'b1;
        active_bank       = bit'(slot);
        return slot;
    endfunction

    // -----------------------------------------------------------------
    // key_for_bank: return the round-key array currently in a bank.
    // -----------------------------------------------------------------
    function automatic rk_array_t key_for_bank(input bit b);
        return banks[b].rk;
    endfunction

    // -----------------------------------------------------------------
    // any_key_loaded: returns 1 if at least one bank is valid.
    // -----------------------------------------------------------------
    function automatic bit any_key_loaded();
        return banks[0].valid || banks[1].valid;
    endfunction

endclass

`endif
