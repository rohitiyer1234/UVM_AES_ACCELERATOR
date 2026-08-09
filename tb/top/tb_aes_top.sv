// ============================================================================
//  tb/top/tb_aes_top.sv
//
//  Top-level testbench module.  Instantiates the DUT (aes_top from
//  rtl_fixed/), the four interfaces, and a single test object selected
//  via +TEST=<name> plusarg.  Provides clock, reset, and waveform dump.
// ============================================================================
`timescale 1ns/1ps
/*
`include "aes_transaction.sv"
`include "key_transaction.sv"
`include "gcm_transaction.sv"

`include "aes_refmodel.sv"
`include "mode_refmodel.sv"
`include "gcm_refmodel.sv"
`include "key_refmodel.sv"

`include "aes_driver.sv"
`include "key_driver.sv"
`include "gcm_driver.sv"

`include "aes_monitor.sv"
`include "key_monitor.sv"
`include "gcm_monitor.sv"

`include "aes_scoreboard.sv"
`include "key_scoreboard.sv"
`include "gcm_scoreboard.sv"

`include "aes_coverage.sv"

`include "aes_config.sv"
`include "aes_env.sv"

`include "test_base.sv"
`include "test_smoke.sv"
`include "test_random_stress.sv"
`include "test_backpressure.sv"
`include "test_reset.sv"
`include "test_mode_switch.sv"
`include "test_long_stream.sv"
`include "test_gcm_stress.sv"
`include "test_dual_bank.sv"
*/
module tb_aes_top;

    import aes_pkg::*;
    import aes_tb_pkg::*;

    // ------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------
    logic clk;
    logic reset;

    initial clk = 1'b0;
    always #5 clk = ~clk;     // 100 MHz

    // ------------------------------------------------------------
    // Interfaces
    // ------------------------------------------------------------
    aes_ctrl_if   ctrl_if   (clk, reset);
    aes_stream_if stream_if (clk, reset);
    key_if        keyif     (clk, reset);
    gcm_if        gcmif     (clk, reset);

    // ------------------------------------------------------------
    // DUT  (uses fixed RTL from rtl_fixed/)
    // ------------------------------------------------------------
    aes_top dut (
        .clk           (clk),
        .reset         (reset),

        .mode          (ctrl_if.mode),
        .enc_dec       (ctrl_if.enc_dec),

        .in_valid      (stream_if.in_valid),
        .in_ready      (stream_if.in_ready),
        .data_in       (stream_if.data_in),

        .out_valid     (stream_if.out_valid),
        .out_ready     (stream_if.out_ready),
        .data_out      (stream_if.data_out),

        .iv_load       (ctrl_if.iv_load),
        .iv_in         (ctrl_if.iv_in),
        .gcm_iv        (gcmif.gcm_iv),

        .aad_valid     (gcmif.aad_valid),
        .aad_ready     (gcmif.aad_ready),
        .aad_data      (gcmif.aad_data),
        .aad_last      (gcmif.aad_last),

        .payload_last  (gcmif.payload_last),

        .tag_valid     (gcmif.tag_valid),
        .tag_out       (gcmif.tag_out),
        .expected_tag  (gcmif.expected_tag),
        .tag_match     (gcmif.tag_match),

        .key_push      (keyif.key_push),
        .key_data      (keyif.key_data),

        .busy          (ctrl_if.busy),

        .dbg_bank_valid(keyif.bank_valid),
        .dbg_bank_busy (keyif.bank_busy),
        .dbg_bank_free (keyif.bank_free)
    );

    // ------------------------------------------------------------
    // Reset sequencer
    // ------------------------------------------------------------
    initial begin
        reset = 1'b1;
        repeat (5) @(posedge clk);
        reset = 1'b0;
    end

    // ------------------------------------------------------------
    // Wave dump
    // ------------------------------------------------------------
    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("aes_tb.vcd");
            $dumpvars(0, tb_aes_top);
        end
    end

    // ------------------------------------------------------------
    // Test dispatcher
    // ------------------------------------------------------------
    string test_name;
    test_base t;

    initial begin
        if (!$value$plusargs("TEST=%s", test_name)) test_name = "test_smoke";
        if (!$value$plusargs("SEED=%d", tb_seed))   tb_seed   = 32'hC0FFEE;
        $display("=== tb_aes_top TEST=%s SEED=0x%08h ===", test_name, tb_seed);

        case (test_name)
            "test_smoke"          : t = test_smoke         ::new("test_smoke");
            "test_random_stress"  : t = test_random_stress ::new("test_random_stress");
            "test_backpressure"   : t = test_backpressure  ::new("test_backpressure");
            "test_reset"          : t = test_reset         ::new("test_reset");
            "test_mode_switch"    : t = test_mode_switch   ::new("test_mode_switch");
            "test_long_stream"    : t = test_long_stream   ::new("test_long_stream");
            "test_gcm_stress"     : t = test_gcm_stress    ::new("test_gcm_stress");
            "test_dual_bank"      : t = test_dual_bank     ::new("test_dual_bank");
            default               : t = test_smoke         ::new("test_smoke");
        endcase

        t.env.ctrl_vif   = ctrl_if;
        t.env.stream_vif = stream_if;
        t.env.key_vif    = keyif;
        t.env.gcm_vif    = gcmif;

        wait (reset == 1'b0);
        @(posedge clk);

        t.run();

        $display("=== tb_aes_top DONE ===");
        $finish;
    end

    // ------------------------------------------------------------
    // Safety: hard watchdog so a bug never holds the regression up
    // ------------------------------------------------------------
    initial begin
        #5_000_000;
        $display("[watchdog] TB exceeded 5ms - terminating");
        $finish;
    end

endmodule
