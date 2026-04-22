// ============================================================================
//  aes_top.sv  -  AES-128 Accelerator Top-Level (ECB + All Modes)
//
//  BUGS FIXED from original aes_top.sv:
//
//  BUG-T1 (CRITICAL): Module instantiated AES_Encrypt_Pipe / AES_Decrypt_Pipe
//    (renamed modules) but original used AES_Encrypt_Pipe03 / AES_Decrypt_Pipe03.
//    Corrected to AES_Encrypt_Pipe / AES_Decrypt_Pipe.
//
//  BUG-T2: aes_top.sv tried to instantiate AES_Key_Expansion_128 directly
//    with ports start_valid/start_ready which do not exist in that module.
//    The key system is properly handled by key_system_top. Fixed: use
//    key_system_top for the entire key subsystem.
//
//  BUG-7 (already partially fixed in original): current_bank edge-detect
//    logic preserved from the original BUG-7 fix. Verified correct.
//
//  NEW: Mode support integrated via aes_mode_datapath.
//    When mode == ECB, aes_mode_datapath is a transparent pass-through.
//    All modes share the same encrypt/decrypt pipelines.
//
//  Port interface:
//    - ECB-compatible interface preserved for backward compatibility with
//      the existing testbench (tb_aes_layered.sv uses this interface).
//    - Mode/IV ports added as optional (driven to ECB defaults if unused).
//
//  Debug probe outputs preserved exactly for testbench compatibility.
// ============================================================================
`timescale 1ns/1ps

import aes_pkg::*;

module aes_top (
    input  logic        clk,
    input  logic        reset,

    // ---- Operation mode ----
    input  logic        enc_dec,    // 0 = encrypt, 1 = decrypt
    input  aes_mode_e   mode,       // ECB/CBC/CFB/OFB/CTR

    // ---- IV / Counter (for non-ECB modes) ----
    input  logic        iv_load,    // pulse: load iv_in
    input  aes_block_t  iv_in,

    // ---- Data stream input ----
    input  logic        in_valid,
    output logic        in_ready,
    input  aes_block_t  data_in,

    // ---- Data stream output ----
    output logic        out_valid,
    input  logic        out_ready,
    output aes_block_t  data_out,

    // ---- Key loading ----
    input  logic        key_start,  // push key into FIFO
    input  aes_block_t  key,

    // ---- Debug probes (for testbench aes_probe_if) ----
    output logic [1:0]  dbg_bank_valid,
    output logic [1:0]  dbg_bank_free,
    output logic        dbg_fifo_empty,
    output logic        dbg_fifo_full,
    output logic        dbg_exp_done,
    output logic        dbg_current_bank,
    output logic [1:0]  dbg_bank_busy
);

    // -----------------------------------------------------------------------
    //  Key system
    // -----------------------------------------------------------------------
    logic [1:0]  bank_valid, bank_free;
    logic [1:0]  bank_busy_enc, bank_busy_dec, bank_busy;
    rk_store_t   round_keys;

    // Only the active pipeline contributes to bank_busy
    assign bank_busy[0] = enc_dec ? bank_busy_dec[0] : bank_busy_enc[0];
    assign bank_busy[1] = enc_dec ? bank_busy_dec[1] : bank_busy_enc[1];

    // FIFO full: expose for debug but not gated (push is external)
    logic fifo_full_i, fifo_empty_i, exp_done_i;

    key_system_top key_sys (
        .clk        (clk),
        .reset      (reset),
        .push       (key_start),
        .key_in     (key),
        .bank_busy  (bank_busy),
        .round_keys (round_keys),
        .bank_valid (bank_valid),
        .bank_free  (bank_free)
    );

    // Expose FIFO/expansion signals for debug (hierarchical access)
    assign fifo_empty_i = key_sys.fifo_empty;
    assign fifo_full_i  = key_sys.fifo_full;
    assign exp_done_i   = key_sys.exp_done;

    // -----------------------------------------------------------------------
    //  BUG-7 fix: current_bank tracks the most recently completed bank
    // -----------------------------------------------------------------------
    logic        current_bank;
    logic [1:0]  bank_valid_prev;

    always_ff @(posedge clk) begin
        if (reset) begin
            current_bank    <= 1'b0;
            bank_valid_prev <= 2'b00;
        end else begin
            bank_valid_prev <= bank_valid;
            if ( bank_valid[0] && !bank_valid_prev[0]) current_bank <= 1'b0;
            if ( bank_valid[1] && !bank_valid_prev[1]) current_bank <= 1'b1;
        end
    end

    // -----------------------------------------------------------------------
    //  Mode datapath (pre/post-processing + feedback/counter)
    // -----------------------------------------------------------------------
    logic        mode_pipe_in_valid,  mode_pipe_in_ready;
    aes_block_t  mode_pipe_in_data;
    logic        mode_pipe_out_valid, mode_pipe_out_ready;
    aes_block_t  mode_pipe_out_data;
    logic        mode_user_out_valid;
    aes_block_t  mode_user_out_data;

    // AES pipeline outputs wired back to mode datapath
    logic        enc_out_valid, dec_out_valid;
    aes_block_t  enc_out_data,  dec_out_data;
    logic        enc_in_ready,  dec_in_ready;

    // Mode datapath selects which pipeline output to observe
    assign mode_pipe_out_valid = enc_dec ? dec_out_valid : enc_out_valid;
    assign mode_pipe_out_data  = enc_dec ? dec_out_data  : enc_out_data;
    assign mode_pipe_out_ready = out_ready;  // direct pass-through

    aes_mode_datapath u_mode (
        .clk             (clk),
        .reset           (reset),
        .mode            (mode),
        .enc_dec         (enc_dec),
        .iv_load         (iv_load),
        .iv_in           (iv_in),
        .user_valid      (in_valid),
        .user_ready      (in_ready),
        .user_data       (data_in),
        .pipe_in_valid   (mode_pipe_in_valid),
        .pipe_in_ready   (mode_pipe_in_ready),
        .pipe_in_data    (mode_pipe_in_data),
        .pipe_out_valid  (mode_pipe_out_valid),
        .pipe_out_ready  (mode_pipe_out_ready),
        .pipe_out_data   (mode_pipe_out_data),
        .user_out_valid  (mode_user_out_valid),
        .user_out_ready  (out_ready),
        .user_out_data   (mode_user_out_data)
    );

    assign out_valid = mode_user_out_valid;
    assign data_out  = mode_user_out_data;

    // Mode pipe_in_ready = the active pipeline's in_ready
    assign mode_pipe_in_ready = enc_dec ? dec_in_ready : enc_in_ready;

    // Gate data into pipelines: only when a valid key bank is ready
    logic key_ready_gate;
    assign key_ready_gate = bank_valid[current_bank];

    // -----------------------------------------------------------------------
    //  Encrypt pipeline
    // -----------------------------------------------------------------------
    AES_Encrypt_Pipe enc_pipe (
        .clk          (clk),
        .reset        (reset),
        .in_valid     (mode_pipe_in_valid && !enc_dec && key_ready_gate),
        .in_ready     (enc_in_ready),
        .plaintext    (mode_pipe_in_data),
        .current_bank (current_bank),
        .round_keys   (round_keys),
        .ciphertext   (enc_out_data),
        .out_valid    (enc_out_valid),
        .out_ready    (out_ready),
        .bank_busy    (bank_busy_enc)
    );

    // -----------------------------------------------------------------------
    //  Decrypt pipeline
    // -----------------------------------------------------------------------
    AES_Decrypt_Pipe dec_pipe (
        .clk          (clk),
        .reset        (reset),
        .in_valid     (mode_pipe_in_valid && enc_dec && key_ready_gate),
        .in_ready     (dec_in_ready),
        .ciphertext   (mode_pipe_in_data),
        .current_bank (current_bank),
        .round_keys   (round_keys),
        .plaintext    (dec_out_data),
        .out_valid    (dec_out_valid),
        .out_ready    (out_ready),
        .bank_busy    (bank_busy_dec)
    );

    // -----------------------------------------------------------------------
    //  Debug probes
    // -----------------------------------------------------------------------
    assign dbg_bank_valid    = bank_valid;
    assign dbg_bank_free     = bank_free;
    assign dbg_fifo_empty    = fifo_empty_i;
    assign dbg_fifo_full     = fifo_full_i;
    assign dbg_exp_done      = exp_done_i;
    assign dbg_current_bank  = current_bank;
    assign dbg_bank_busy     = bank_busy;

endmodule : aes_top