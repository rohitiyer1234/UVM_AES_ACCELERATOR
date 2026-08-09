// ============================================================================
//  tb/transactions/gcm_transaction.sv
//
//  One GCM session: 96-bit IV + variable AAD + variable payload.  The
//  gcm_driver issues the IV, drives the AAD stream, then coordinates with
//  the aes_driver to push the payload and finally pulses payload_last.
// ============================================================================
`ifndef GCM_TRANSACTION_SV
`define GCM_TRANSACTION_SV

    import aes_pkg::*;
    import aes_tb_pkg::*;


class gcm_transaction;


    rand logic [95:0] iv96;
    rand int unsigned aad_blocks;       // 0..8
    rand int unsigned payload_blocks;   // 1..64
    rand aes_block_t  aad   [];
    rand aes_block_t  pld   [];

    // Filled in by the gcm_scoreboard from the reference model after
    // randomization completes, or pre-loaded for known-answer testing.
    aes_block_t expected_tag;

    int unsigned id;
    realtime     t_create;

    constraint c_lens {
        aad_blocks     inside {[0:8]};
        payload_blocks inside {[1:64]};
        aad.size()     == aad_blocks;
        pld.size()     == payload_blocks;
    }

    function new();
        id           = tb_next_id();
        t_create     = $realtime;
        expected_tag = '0;
    endfunction

    function void post_randomize();
        if (aad.size() != aad_blocks)     aad = new[aad_blocks];
        if (pld.size() != payload_blocks) pld = new[payload_blocks];
    endfunction

    function string convert2string();
        return $sformatf("GCM id=%0d iv96=0x%024h aad=%0d pld=%0d",
                         id, iv96, aad_blocks, payload_blocks);
    endfunction

endclass

`endif
