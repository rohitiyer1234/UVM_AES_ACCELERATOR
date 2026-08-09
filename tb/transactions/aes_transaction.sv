// ============================================================================
//  tb/transactions/aes_transaction.sv
//
//  Streaming AES data transaction (one or many 128-bit blocks).  A packet
//  carries a mode + enc_dec + IV and an arbitrary block count.  The driver
//  emits the packet beat-by-beat; the monitor sees individual beats.
// ============================================================================
`ifndef AES_TRANSACTION_SV
`define AES_TRANSACTION_SV

import aes_pkg::*;
import aes_tb_pkg::*;
    
class aes_transaction;

    

    rand aes_mode_e   mode;
    rand bit          enc_dec;
    rand int unsigned num_blocks;
    rand aes_block_t  iv;
    rand aes_block_t  blocks [];

    // Backpressure / pacing knobs for the driver
    rand int unsigned input_gap_min;
    rand int unsigned input_gap_max;
    rand int unsigned output_stall_pct;   // 0..100

    // Bookkeeping
    int unsigned id;
    realtime     t_create;

    // ---------- Default constraints ----------
    constraint c_size {
        num_blocks inside {[1:32]};
        blocks.size() == num_blocks;
    }

    constraint c_pacing {
        input_gap_min inside {[0:4]};
        input_gap_max inside {[input_gap_min:16]};
        output_stall_pct inside {[0:100]};
    }

    constraint c_mode {
        mode dist { MODE_ECB := 1, MODE_CBC := 1, MODE_CFB := 1,
                    MODE_OFB := 1, MODE_CTR := 1, MODE_GCM := 1 };
    }

    function new();
        id       = tb_next_id();
        t_create = $realtime;
    endfunction

    function void post_randomize();
        // Force blocks array size to match num_blocks (in case it was
        // already populated to a different size before randomization).
        if (blocks.size() != num_blocks) blocks = new[num_blocks];
    endfunction

    function string convert2string();
        return $sformatf("id=%0d mode=%s enc_dec=%0d blocks=%0d iv=0x%032h",
                          id, mode_name(mode), enc_dec, num_blocks, iv);
    endfunction

    function aes_transaction clone();
        aes_transaction c = new();
        c.mode             = mode;
        c.enc_dec          = enc_dec;
        c.num_blocks       = num_blocks;
        c.iv               = iv;
        c.blocks           = blocks;
        c.input_gap_min    = input_gap_min;
        c.input_gap_max    = input_gap_max;
        c.output_stall_pct = output_stall_pct;
        c.id               = id;
        c.t_create         = t_create;
        return c;
    endfunction

endclass

`endif
