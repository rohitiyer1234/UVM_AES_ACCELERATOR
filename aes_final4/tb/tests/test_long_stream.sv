// ============================================================================
//  test_long_stream.sv
//  Single very long CTR / CBC stream to exercise the metadata FIFO and
//  serialisation logic at scale.
// ============================================================================
`ifndef TEST_LONG_STREAM_SV
`define TEST_LONG_STREAM_SV

class test_long_stream extends test_base;

    function new(string n = "test_long_stream"); super.new(n); endfunction

    virtual function void configure();
        env.cfg.verbosity = aes_tb_pkg::VRB_LOW;
    endfunction

    virtual task body();
        // CTR 256-block stream
        begin
            aes_transaction t = new();
            t.mode      = MODE_CTR;
            t.enc_dec   = 1'b0;
            t.num_blocks = 256;
            t.iv = 128'hCAFEBABE_DEADBEEF_01234567_89ABCDEF;
            t.blocks = new[256];
            for (int i = 0; i < 256; i++) t.blocks[i] = i;
            t.input_gap_min = 0;
            t.input_gap_max = 2;
            t.output_stall_pct = 15;
            env.adrv.in_mbox.put(t);
            env.asb.expect_mbox.put(t);
        end
        // CBC enc 128-block stream
        begin
            aes_transaction t = new();
            t.mode      = MODE_CBC;
            t.enc_dec   = 1'b0;
            t.num_blocks = 128;
            t.iv = 128'h00000000_FFFFFFFF_AAAAAAAA_55555555;
            t.blocks = new[128];
            for (int i = 0; i < 128; i++) t.blocks[i] = {i, i};
            t.input_gap_min = 0;
            t.input_gap_max = 3;
            t.output_stall_pct = 20;
            env.adrv.in_mbox.put(t);
            env.asb.expect_mbox.put(t);
        end
    endtask

endclass

`endif
