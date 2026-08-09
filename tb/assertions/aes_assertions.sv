// ============================================================================
//  tb/assertions/aes_assertions.sv
//
//  SVA module bound into aes_top so the DUT source remains untouched.
//  Each property carries a brief purpose comment and a deterministic label
//  so failure messages stay greppable.
// ============================================================================
/*
`timescale 1ns/1ps
import aes_pkg::*;

module aes_assertions (
    input  logic        clk,
    input  logic        reset,

    // stream
    input  logic        in_valid,
    input  logic        in_ready,
    input  aes_block_t  data_in,
    input  logic        out_valid,
    input  logic        out_ready,
    input  aes_block_t  data_out,

    // ctrl
    input  aes_mode_e   mode,
    input  logic        enc_dec,

    // bank state
    input  logic [1:0]  dbg_bank_valid,
    input  logic [1:0]  dbg_bank_busy,
    input  logic [1:0]  dbg_bank_free,

    // GCM
    input  logic        aad_valid,
    input  logic        aad_ready,
    input  logic        tag_valid
);

    // Active-high reset: gate every property until the first cycle after
    // de-assertion.
    default clocking @(posedge clk); endclocking
    //default disable iff (reset);

    // ---------------------------------------------------------------------
    // a_valid_stable
    // While in_valid is high but in_ready has not yet accepted, data_in
    // must not change.  Standard ready/valid handshake invariant.
    // ---------------------------------------------------------------------
    property p_valid_stable;
    disable iff (reset)
    in_valid && !in_ready |=> in_valid && $stable(data_in, @(posedge clk));
    endproperty
    a_valid_stable: assert property (p_valid_stable)
        else $error("a_valid_stable: data_in changed under stalled in_valid");

    // ---------------------------------------------------------------------
    // a_out_stable_under_bp
    // While the DUT presents an output but consumer is not ready, the data
    // must remain stable.
    // ---------------------------------------------------------------------
   property p_out_stable;
    disable iff (reset)
    out_valid && !out_ready |=> out_valid && $stable(data_out, @(posedge clk));
endproperty
    a_out_stable_under_bp: assert property (p_out_stable)
        else $error("a_out_stable_under_bp: data_out changed under backpressure");

    // ---------------------------------------------------------------------
    // a_bank_state_legal
    // bank_free[i] implies !bank_valid[i] and !bank_busy[i] (independence)
    // ---------------------------------------------------------------------
    property p_bank0_free;
    disable iff (reset)
        dbg_bank_free[0] |-> !dbg_bank_valid[0] && !dbg_bank_busy[0];
    endproperty
    a_bank0_free: assert property (p_bank0_free)
        else $error("a_bank0_free: bank0 free overlaps with valid/busy");

    property p_bank1_free;
    disable iff (reset)
        dbg_bank_free[1] |-> !dbg_bank_valid[1] && !dbg_bank_busy[1];
    endproperty
    a_bank1_free: assert property (p_bank1_free)
        else $error("a_bank1_free: bank1 free overlaps with valid/busy");

    // ---------------------------------------------------------------------
    // a_aad_handshake_legal
    // aad_valid && !aad_ready => aad_valid still high next cycle (no drop).
    // ---------------------------------------------------------------------
    property p_aad_hold;
    disable iff (reset)
        aad_valid && !aad_ready |=> aad_valid;
    endproperty
    a_aad_hold: assert property (p_aad_hold)
        else $error("a_aad_hold: aad_valid dropped without handshake");

    // ---------------------------------------------------------------------
    // a_deadlock_watchdog
    // No output for an excessively long time while inputs are arriving:
    // flag as fatal.  Tunable threshold for long streams.
    // ---------------------------------------------------------------------
    int unsigned no_progress_cyc;
    always_ff @(posedge clk) begin
        if (reset)                            no_progress_cyc <= 0;
        else if (out_valid && out_ready)      no_progress_cyc <= 0;
        else if (in_valid)                    no_progress_cyc <= no_progress_cyc + 1;
        else                                  no_progress_cyc <= 0;
    end
    a_deadlock_watchdog: assert property (@(posedge clk) disable iff (reset)
        no_progress_cyc < 50_000)
        else $fatal(1, "a_deadlock_watchdog: 50000 cycles without output progress");

    // ---------------------------------------------------------------------
    // a_tag_not_during_idle_mode
    // tag_valid must only be asserted while mode==MODE_GCM (or just after
    // it was MODE_GCM and a session completed).  We weaken to: if tag_valid
    // is high, mode must have been MODE_GCM within the last 4 cycles.
    // ---------------------------------------------------------------------
property p_tag_only_gcm;
    disable iff (reset)
    tag_valid |-> (
           mode == MODE_GCM
        || $past(mode == MODE_GCM, 1, 1'b0, @(posedge clk))
        || $past(mode == MODE_GCM, 2, 1'b0, @(posedge clk))
        || $past(mode == MODE_GCM, 3, 1'b0, @(posedge clk))
    );
endproperty
    a_tag_only_gcm: assert property (p_tag_only_gcm)
        else $error("a_tag_only_gcm: tag_valid outside GCM mode window");

endmodule

// ----------------------------------------------------------------------------
// Bind the assertion module into the DUT.
// ----------------------------------------------------------------------------
bind aes_top aes_assertions u_aes_asserts (
    .clk            (clk),
    .reset          (reset),
    .in_valid       (in_valid),
    .in_ready       (in_ready),
    .data_in        (data_in),
    .out_valid      (out_valid),
    .out_ready      (out_ready),
    .data_out       (data_out),
    .mode           (mode),
    .enc_dec        (enc_dec),
    .dbg_bank_valid (dbg_bank_valid),
    .dbg_bank_busy  (dbg_bank_busy),
    .dbg_bank_free  (dbg_bank_free),
    .aad_valid      (aad_valid),
    .aad_ready      (aad_ready),
    .tag_valid      (tag_valid)
);

*/
// ============================================================================
//  aes_assertions.sv
//
//  Assertions for corrected AES datapath/top architecture.
//
// ============================================================================

`timescale 1ns/1ps

import aes_pkg::*;

module aes_assertions (

    input logic clk,
    input logic reset,

    // -------------------------------------------------------------
    // STREAM
    // -------------------------------------------------------------

    input logic in_valid,
    input logic in_ready,

    input logic out_valid,
    input logic out_ready,

    // -------------------------------------------------------------
    // DATAPATH
    // -------------------------------------------------------------

    input logic pipe_in_valid,
    input logic pipe_in_ready,

    input logic pipe_out_valid,
    input logic pipe_out_ready,

    // -------------------------------------------------------------
    // OWNERSHIP
    // -------------------------------------------------------------

    input logic internal_output,
    input logic head_owner,

    // -------------------------------------------------------------
    // PIPE SELECT
    // -------------------------------------------------------------

    input logic pipe_use_encrypt,
    input logic ret_use_encrypt

);

    // =============================================================
    // NO X PROPAGATION
    // =============================================================

    always @(posedge clk) begin

        if(!reset) begin

            assert(!$isunknown(in_valid))
            else $fatal("[ASSERT] in_valid is X");

            assert(!$isunknown(out_valid))
            else $fatal("[ASSERT] out_valid is X");

            assert(!$isunknown(pipe_out_ready))
            else $fatal("[ASSERT] pipe_out_ready is X");

            assert(!$isunknown(head_owner))
            else $fatal("[ASSERT] head_owner is X");

        end

    end

    // =============================================================
    // OUTPUT OWNERSHIP CONSISTENCY
    // =============================================================

    property p_internal_output_consistent;

        @(posedge clk)
        disable iff(reset)

        internal_output |-> head_owner;

    endproperty

    assert property(p_internal_output_consistent)
    else
        $fatal("[ASSERT] internal_output without head_owner");

    // =============================================================
    // USER OUTPUT MUST NOT BE INTERNAL
    // =============================================================

    property p_user_output_not_internal;

        @(posedge clk)
        disable iff(reset)

        (out_valid && out_ready)
            |-> !internal_output;

    endproperty

    assert property(p_user_output_not_internal)
    else
        $fatal("[ASSERT] Internal GCM traffic leaked to user");

    // =============================================================
    // VALID MUST STAY ASSERTED UNTIL READY
    // =============================================================

    property p_hold_valid_until_ready;

        @(posedge clk)
        disable iff(reset)

        pipe_out_valid && !pipe_out_ready
            |=> pipe_out_valid;

    endproperty

    assert property(p_hold_valid_until_ready)
    else
        $fatal("[ASSERT] pipe_out_valid dropped before ready");

    // =============================================================
    // NO INPUT ACCEPT WITHOUT READY
    // =============================================================

    property p_input_handshake;

        @(posedge clk)
        disable iff(reset)

        pipe_in_valid && !pipe_in_ready
            |=> pipe_in_valid;

    endproperty

    assert property(p_input_handshake)
    else
        $fatal("[ASSERT] pipe_in_valid dropped early");

    // =============================================================
    // RETURN PIPE CONSISTENCY
    // =============================================================

    property p_return_pipe_known;

        @(posedge clk)
        disable iff(reset)

        pipe_out_valid |-> !$isunknown(ret_use_encrypt);

    endproperty

    assert property(p_return_pipe_known)
    else
        $fatal("[ASSERT] ret_use_encrypt unknown");

    // =============================================================
    // DEADLOCK WATCHDOG
    // =============================================================

    integer stall_counter;

    always @(posedge clk) begin

        if(reset)

            stall_counter <= 0;

        else begin

            if(
                pipe_out_valid &&
                !pipe_out_ready
            )

                stall_counter <= stall_counter + 1;

            else

                stall_counter <= 0;

            assert(stall_counter < 2000)
            else
                $fatal(
                    "[ASSERT] Possible deadlock detected"
                );

        end

    end

endmodule