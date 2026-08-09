/*
`timescale 1ns/1ps
// ============================================================================
//  key_system_top.sv
// ============================================================================
//  AES Key Management Subsystem
//
//  FEATURES
//  --------
//  - Key FIFO buffering
//  - Dual-bank round-key storage
//  - Automatic bank allocation
//  - Automatic bank recycling
//  - AES-128 key expansion
//  - Timing-safe control
//  - Pipeline-safe bank ownership
//  - Continuous operation support
//
//  ARCHITECTURE
//  ------------
//
//      key_fifo
//          ->
//      key_controller
//          ->
//      AES_Key_Expansion_128
//          ->
//      keymem_dual
//
//  DESIGN GOALS
//  ------------
//  - No combinational loops
//  - No multi-driver hazards
//  - No stale-bank races
//  - No expansion interruption
//  - Timing-closure safe
//  - Continuous streaming safe
//  - Synthesizable Vivado-safe RTL
//
// ============================================================================

import aes_pkg::*;

module key_system_top(

    input  logic        clk,
    input  logic        reset,

    // =========================================================================
    // KEY INPUT
    // =========================================================================

    input  logic        push,
    input  aes_block_t  key_in,

    // =========================================================================
    // PIPELINE FEEDBACK
    // =========================================================================

    input  logic [1:0]  bank_busy,

    // =========================================================================
    // OUTPUTS
    // =========================================================================

    output rk_store_t   round_keys,

    output logic [1:0]  bank_valid,
    output logic [1:0]  bank_free,

    output logic        key_system_busy,

    output logic        key_available,

    output logic        active_bank

);

    // =========================================================================
    // FIFO SIGNALS
    // =========================================================================

    logic fifo_empty;
    logic fifo_full;

    logic fifo_pop;

    aes_block_t fifo_key;

    // =========================================================================
    // CONTROLLER SIGNALS
    // =========================================================================

    logic exp_start;

    logic write_bank;

    logic exp_done;

    // =========================================================================
    // EXPANSION SIGNALS
    // =========================================================================

    logic        w_en;
    logic [3:0]  waddr;
    aes_block_t  wkey;

    // =========================================================================
    // BANK RELEASE
    // =========================================================================

    logic [1:0] bank_release;

    // =========================================================================
    // FIFO
    // =========================================================================

    key_fifo fifo_inst(

        .clk(clk),
        .reset(reset),

        .push(push),
        .data_in(key_in),

        .pop(fifo_pop),
        .data_out(fifo_key),

        .empty(fifo_empty),
        .full(fifo_full)

    );

    // =========================================================================
    // CONTROLLER
    // =========================================================================

    key_controller ctrl_inst(

        .clk(clk),
        .reset(reset),

        .key_valid(!fifo_empty),
        .key_ready(fifo_pop),

        .bank_free(bank_free),

        .exp_done(exp_done),

        .exp_start(exp_start),
        .write_bank(write_bank)

    );

    // =========================================================================
    // KEY EXPANSION
    // =========================================================================

    AES_Key_Expansion_128 expand_inst(

        .clk(clk),
        .reset(reset),

        .exp_start(exp_start),

        .key_in(fifo_key),

        .w_en(w_en),
        .waddr(waddr),
        .wkey(wkey),

        .done(exp_done)

    );

    // =========================================================================
    // BANK RELEASE CONTROL
    // =========================================================================
    //
    // POLICY:
    //
    // Release a bank ONLY IF:
    // 1. new key pending in FIFO
    // 2. no free bank exists
    // 3. bank currently idle
    //
    // This avoids:
    // - premature key destruction
    // - unnecessary reloads
    // - pipeline races
    //
    // =========================================================================

    always_ff @(posedge clk) begin

        if(reset)

            bank_release <= 2'b00;

        else begin

            bank_release <= 2'b00;

            // -----------------------------------------------------------------
            // recycle bank0
            // -----------------------------------------------------------------

            if(
                !fifo_empty               &&
                (bank_free == 2'b00)      &&
                bank_valid[0]             &&
                !bank_busy[0]
            )
                bank_release[0] <= 1'b1;

            // -----------------------------------------------------------------
            // recycle bank1
            // -----------------------------------------------------------------

            if(
                !fifo_empty               &&
                (bank_free == 2'b00)      &&
                bank_valid[1]             &&
                !bank_busy[1]
            )
                bank_release[1] <= 1'b1;

        end

    end

    // =========================================================================
    // KEY MEMORY
    // =========================================================================

    keymem_dual keymem_inst(

        .clk(clk),
        .reset(reset),

        .w_en(w_en),
        .waddr(waddr),
        .wkey(wkey),

        .write_bank(write_bank),

        .bank_release(bank_release),

        .bank_busy(bank_busy),

        .round_keys(round_keys),

        .bank_valid(bank_valid),
        .bank_free(bank_free)

    );

    // =========================================================================
    // ACTIVE BANK TRACKING
    // =========================================================================
    //
    // Tracks newest valid key bank.
    // Encrypt/decrypt pipelines may use this
    // as default bank selection.
    //
    // =========================================================================

    always_ff @(posedge clk) begin

        if(reset)

            active_bank <= 1'b0;

        else begin

            if(bank_valid[0])
                active_bank <= 1'b0;

            else if(bank_valid[1])
                active_bank <= 1'b1;

        end

    end

    // =========================================================================
    // KEY AVAILABLE
    // =========================================================================

    always_comb begin

        key_available = 1'b0;

        if(bank_valid[0]) key_available = 1'b1;
        if(bank_valid[1]) key_available = 1'b1;

    end

    // =========================================================================
    // KEY SYSTEM BUSY
    // =========================================================================

    always_comb begin

        key_system_busy = 1'b0;

        if(!fifo_empty) key_system_busy = 1'b1;
        if(bank_busy != 2'b00) key_system_busy = 1'b1;

    end

endmodule

*/

`timescale 1ns/1ps
// ============================================================================
//  key_system_top.sv  (FIXED)
// ============================================================================
//
//  BUGS FIXED
//  ----------
//
//  BUG-KST1 [CRITICAL]: expand_enable not connected to AES_Key_Expansion_128.
//    The original instantiation omitted .expand_enable().  The module port
//    was left undriven → synthesis resolves it to 0 (or X in simulation),
//    so the expansion FSM inside AES_Key_Expansion_128 never advanced past
//    the start cycle.  No round keys beyond K0 were ever written.
//    FIX: Wire expand_enable = 1'b1.  The expansion engine should always be
//    allowed to run once started.  The controller already gates start via
//    exp_start.  Gating expand_enable is not needed and was harmful.
//
//  BUG-KST2: active_bank logic always picks bank0 if bank_valid[0] is set,
//    even if bank1 was loaded more recently.  Under normal dual-bank
//    rotation (bank0 loaded, then bank1 loaded), the pipeline always uses
//    bank0, never transitioning to the newer key in bank1.
//    FIX: Track the bank most recently signaled as valid.  When exp_done
//    fires, record write_bank as the new active_bank.
//
//  BUG-KST3: bank_release can assert both bits simultaneously when both
//    banks are valid, busy==0, and a new key is pending.  This clears both
//    banks in keymem_dual, leaving no valid key for in-flight pipeline data
//    even briefly.  Only one bank needs to be released at a time; priority
//    encoder prevents double-release.
//    FIX: Release bank0 first if both conditions are met; only release
//    bank1 if bank0 is not being released this cycle.
//
// ============================================================================

import aes_pkg::*;

module key_system_top(

    input  logic        clk,
    input  logic        reset,

    // =========================================================================
    // KEY INPUT
    // =========================================================================

    input  logic        push,
    input  aes_block_t  key_in,

    // =========================================================================
    // PIPELINE FEEDBACK
    // =========================================================================

    input  logic [1:0]  bank_busy,

    // =========================================================================
    // OUTPUTS
    // =========================================================================

    output rk_store_t   round_keys,

    output logic [1:0]  bank_valid,
    output logic [1:0]  bank_free,

    output logic        key_system_busy,

    output logic        key_available,

    output logic        active_bank

);

    // =========================================================================
    // FIFO SIGNALS
    // =========================================================================

    logic fifo_empty;
    logic fifo_full;
    logic fifo_pop;
    aes_block_t fifo_key;

    // =========================================================================
    // CONTROLLER SIGNALS
    // =========================================================================

    logic exp_start;
    logic write_bank;
    logic exp_done;

    // =========================================================================
    // EXPANSION SIGNALS
    // =========================================================================

    logic        w_en;
    logic [3:0]  waddr;
    aes_block_t  wkey;

    // =========================================================================
    // BANK RELEASE
    // =========================================================================

    logic [1:0] bank_release;

    // =========================================================================
    // FIFO
    // =========================================================================

    key_fifo fifo_inst(
        .clk(clk),
        .reset(reset),
        .push(push),
        .data_in(key_in),
        .pop(fifo_pop),
        .data_out(fifo_key),
        .empty(fifo_empty),
        .full(fifo_full)
    );

    // =========================================================================
    // CONTROLLER
    // =========================================================================

    key_controller ctrl_inst(
        .clk(clk),
        .reset(reset),
        .key_valid(!fifo_empty),
        .key_ready(fifo_pop),
        .bank_free(bank_free),
        .exp_done(exp_done),
        .exp_start(exp_start),
        .write_bank(write_bank)
    );

    // =========================================================================
    // KEY EXPANSION
    // FIX-KST1: expand_enable tied to 1'b1 - expansion always runs once
    //           started.  Gating it was preventing key derivation.
    // =========================================================================

    AES_Key_Expansion_128 expand_inst(
        .clk(clk),
        .reset(reset),
        .exp_start(exp_start),
        .expand_enable(1'b1),       // FIX-KST1: was left unconnected → 0/X
        .key_in(fifo_key),
        .w_en(w_en),
        .waddr(waddr),
        .wkey(wkey),
        .done(exp_done)
    );

    // =========================================================================
    // BANK RELEASE CONTROL
    // FIX-KST3: priority encoder - never release both banks simultaneously
    //
    // POLICY:
    //   Release a bank ONLY IF:
    //   1. New key is pending in FIFO
    //   2. No free bank exists
    //   3. Bank is currently idle (not busy in pipeline)
    //   4. Bank is currently valid
    //   Priority: bank0 before bank1
    // =========================================================================

    always_ff @(posedge clk) begin

        if (reset)
            bank_release <= 2'b00;
        else begin

            bank_release <= 2'b00;

            if (
                !fifo_empty           &&
                (bank_free == 2'b00)  &&
                bank_valid[0]         &&
                !bank_busy[0]
            ) begin
                // FIX-KST3: only release bank0
                bank_release[0] <= 1'b1;
            end

            else if (
                !fifo_empty           &&
                (bank_free == 2'b00)  &&
                bank_valid[1]         &&
                !bank_busy[1]
            ) begin
                // FIX-KST3: only release bank1 if bank0 not being released
                bank_release[1] <= 1'b1;
            end

        end

    end

    // =========================================================================
    // KEY MEMORY
    // =========================================================================

    keymem_dual keymem_inst(
        .clk(clk),
        .reset(reset),
        .w_en(w_en),
        .waddr(waddr),
        .wkey(wkey),
        .write_bank(write_bank),
        .bank_release(bank_release),
        .bank_busy(bank_busy),
        .round_keys(round_keys),
        .bank_valid(bank_valid),
        .bank_free(bank_free)
    );

    // =========================================================================
    // ACTIVE BANK TRACKING
    // FIX-KST2: track the most recently loaded bank (by watching exp_done)
    //           rather than always preferring bank0.
    // =========================================================================

    always_ff @(posedge clk) begin

        if (reset)
            active_bank <= 1'b0;
        else begin
            // When expansion completes, the written bank becomes active
            if (exp_done)
                active_bank <= write_bank;
        end

    end

    // =========================================================================
    // KEY AVAILABLE
    // =========================================================================

    always_comb begin
        key_available = 1'b0;
        if (bank_valid[0]) key_available = 1'b1;
        if (bank_valid[1]) key_available = 1'b1;
    end

    // =========================================================================
    // KEY SYSTEM BUSY
    // =========================================================================

    always_comb begin
        key_system_busy = 1'b0;
        if (!fifo_empty)          key_system_busy = 1'b1;
        if (bank_busy != 2'b00)   key_system_busy = 1'b1;
    end

endmodule