// ============================================================================
//  rtl_fixed/aes_top.sv
//
//  Top-level wrapper that integrates:
//      key_system_top            (unchanged - from original RTL)
//      gcm_ctr_gen               (unchanged)
//      gcm_orchestrator          (FIXED - rtl_fixed/gcm_orchestrator.sv)
//      aes_mode_datapath         (FIXED - rtl_fixed/aes_mode_datapath.sv)
//      AES_Encrypt_Pipe          (unchanged)
//      AES_Decrypt_Pipe          (unchanged)
//      ghash_core                (unchanged)
//
//  Fixes applied here:
//    BUG-R1 : wire mode_dp.internal_output (port now exists in the fixed
//             datapath) and use it instead of an undriven signal.
//    BUG-R3 : route aad_valid/aad_data/aad_ready through to orchestrator
//             and supply an aad_last input.
//    BUG-R4 : add saturating bit counters for AAD and payload lengths and
//             route them to the orchestrator.  Add an explicit
//             `payload_last` input strobe driven by the TB.
//
//  Originals untouched; this file is the "preferred" top for the TB.
// ============================================================================
`timescale 1ns/1ps
import aes_pkg::*;

module aes_top (
    input  logic        clk,
    input  logic        reset,

    // -------------------- CONTROL --------------------
    input  aes_mode_e   mode,
    input  logic        enc_dec,

    // -------------------- DATA IN --------------------
    input  logic        in_valid,
    output logic        in_ready,
    input  aes_block_t  data_in,

    // -------------------- DATA OUT --------------------
    output logic        out_valid,
    input  logic        out_ready,
    output aes_block_t  data_out,

    // -------------------- IV / NONCE --------------------
    input  logic        iv_load,
    input  aes_block_t  iv_in,
    input  logic [95:0] gcm_iv,

    // -------------------- AAD --------------------
    input  logic        aad_valid,
    output logic        aad_ready,
    input  aes_block_t  aad_data,
    input  logic        aad_last,         // FIX-R3 strobe on last AAD beat

    // -------------------- PAYLOAD-LAST  (FIX-R4) --------------------
    input  logic        payload_last,     // TB pulses on final payload beat

    // -------------------- TAG --------------------
    output logic        tag_valid,
    output aes_block_t  tag_out,

    input  aes_block_t  expected_tag,
    output logic        tag_match,

    // -------------------- KEY IN --------------------
    input  logic        key_push,
    input  aes_block_t  key_data,

    // -------------------- STATUS --------------------
    output logic        busy,

    output logic [1:0]  dbg_bank_valid,
    output logic [1:0]  dbg_bank_busy,
    output logic [1:0]  dbg_bank_free
);

    // =====================================================================
    // KEY SUBSYSTEM
    // =====================================================================
    rk_store_t   round_keys;
    logic [1:0]  bank_valid;
    logic [1:0]  bank_busy;
    logic [1:0]  bank_free;
    logic        key_available;
    logic        current_bank;
    logic        key_system_busy;

    key_system_top key_sys (
        .clk(clk), .reset(reset),
        .push(key_push), .key_in(key_data),
        .bank_busy(bank_busy),
        .round_keys(round_keys),
        .bank_valid(bank_valid),
        .bank_free(bank_free),
        .key_system_busy(key_system_busy),
        .key_available(key_available),
        .active_bank(current_bank)
    );

    // =====================================================================
    // PIPELINE SELECT
    // =====================================================================
    logic use_encrypt_pipe;
    always_comb begin
        use_encrypt_pipe = 1'b1;
        unique case (mode)
            MODE_ECB,
            MODE_CBC: use_encrypt_pipe = !enc_dec;
            MODE_CFB,
            MODE_OFB,
            MODE_CTR,
            MODE_GCM: use_encrypt_pipe = 1'b1;
            default : use_encrypt_pipe = 1'b1;
        endcase
    end

    // =====================================================================
    // GCM COUNTER
    // =====================================================================
    aes_block_t gcm_ctr;
    aes_block_t gcm_j0;
    logic       gcm_ctr_inc;
    logic       gcm_ctr_reset;

    assign gcm_ctr_reset = 1'b0;   // not used in this revision

    gcm_ctr_gen gcm_ctr_inst (
        .clk(clk), .reset(reset),
        .iv_load(iv_load),
        .iv_in(gcm_iv),
        .j0_out(gcm_j0),
        .ctr_out(gcm_ctr),
        .ctr_inc(gcm_ctr_inc),
        .ctr_reset(gcm_ctr_reset)
    );

    // =====================================================================
    // LENGTH COUNTERS  (FIX-R4)
    // Reset on iv_load when mode == MODE_GCM.
    // aad_bit_cnt increments on every aad_valid && aad_ready accept by 128.
    // pld_bit_cnt increments on every user_out_valid && user_out_ready
    //   accept during GCM_PAYLOAD by 128.
    // =====================================================================
    logic [63:0] aad_bit_cnt;
    logic [63:0] pld_bit_cnt;

    logic        gcm_pipe_override;
    logic        gcm_pipe_in_valid;
    logic        gcm_pipe_in_ready;
    aes_block_t  gcm_pipe_in_data;
    logic        gcm_pipe_out_valid;
    aes_block_t  gcm_pipe_out_data;

    logic        ghash_h_load;
    aes_block_t  ghash_h_in;
    logic        ghash_data_valid;
    logic        ghash_data_ready;
    aes_block_t  ghash_data_in;
    logic        ghash_accum_clear;
    aes_block_t  ghash_val;
    logic        ghash_done;

    logic        md_user_ready;
    logic        md_pipe_in_valid;
    logic        md_pipe_in_ready;
    aes_block_t  md_pipe_in_data;
    logic        md_pipe_out_valid;
    logic        md_pipe_out_ready;
    aes_block_t  md_pipe_out_data;
    logic        md_user_out_valid;
    aes_block_t  md_user_out_data;
    logic        md_pipe_accept;
    logic        md_internal_output;

    always_ff @(posedge clk) begin
        if (reset) begin
            aad_bit_cnt <= 64'd0;
            pld_bit_cnt <= 64'd0;
        end else begin
            if (iv_load && (mode == MODE_GCM)) begin
                aad_bit_cnt <= 64'd0;
                pld_bit_cnt <= 64'd0;
            end else begin
                if (aad_valid && aad_ready)
                    aad_bit_cnt <= aad_bit_cnt + 64'd128;
                // count payload only after AAD - tracked indirectly by the
                // orchestrator state; here we accept every user_out accept
                // when mode == GCM as payload.
                if (md_user_out_valid && out_ready && (mode == MODE_GCM))
                    pld_bit_cnt <= pld_bit_cnt + 64'd128;
            end
        end
    end

    // =====================================================================
    // GCM ORCHESTRATOR  (FIX-R3 + FIX-R4)
    // =====================================================================
    gcm_orchestrator gcm_ctrl (
        .clk(clk), .reset(reset),
        .start_gcm(iv_load && (mode == MODE_GCM)),
        .payload_last(payload_last && (mode == MODE_GCM)),

        .pipe_override(gcm_pipe_override),
        .pipe_in_valid(gcm_pipe_in_valid),
        .pipe_in_ready(gcm_pipe_in_ready),
        .pipe_in_data(gcm_pipe_in_data),
        .pipe_out_valid(gcm_pipe_out_valid),
        .pipe_out_data(gcm_pipe_out_data),

        .j0(gcm_j0),

        .aad_valid(aad_valid),
        .aad_ready(aad_ready),
        .aad_data(aad_data),
        .aad_last(aad_last),

        .h_load(ghash_h_load),
        .h_value(ghash_h_in),

        .ghash_valid(ghash_data_valid),
        .ghash_ready(ghash_data_ready),
        .ghash_data(ghash_data_in),
        .ghash_result(ghash_val),

        .ct_valid(md_user_out_valid && out_ready),
        .ct_data(md_user_out_data),

        .aad_length_bits(aad_bit_cnt),
        .payload_length_bits(pld_bit_cnt),

        .tag_valid(tag_valid),
        .tag_out(tag_out),

        .busy()
    );

    assign ghash_accum_clear = iv_load && (mode == MODE_GCM);
    assign tag_match         = tag_valid && (tag_out == expected_tag);

    // =====================================================================
    // MODE DATAPATH  (FIX-R1 uses internal_output)
    // =====================================================================
    aes_mode_datapath mode_dp (
        .clk(clk), .reset(reset),
        .mode(mode), .enc_dec(enc_dec),
        .iv_load(iv_load), .iv_in(iv_in),
        .gcm_ctr_in(gcm_ctr),

        .pipe_override(gcm_pipe_override),
        .override_in_valid(gcm_pipe_in_valid),
        .override_in_data(gcm_pipe_in_data),

        .user_valid(in_valid),
        .user_ready(md_user_ready),
        .user_data(data_in),

        .pipe_in_valid(md_pipe_in_valid),
        .pipe_in_ready(md_pipe_in_ready),
        .pipe_in_data(md_pipe_in_data),

        .pipe_out_valid(md_pipe_out_valid),
        .pipe_out_ready(md_pipe_out_ready),
        .pipe_out_data(md_pipe_out_data),

        .user_out_valid(md_user_out_valid),
        .user_out_ready(out_ready),
        .user_out_data(md_user_out_data),

        .internal_output(md_internal_output),   // FIX-R1
        .pipe_accept_o(md_pipe_accept)
    );

    // =====================================================================
    // ENCRYPT PIPELINE
    // =====================================================================
    logic        enc_in_ready;
    logic        enc_out_valid;
    aes_block_t  enc_out_data;
    logic [1:0]  enc_bank_busy;

    AES_Encrypt_Pipe enc_pipe (
        .clk(clk), .reset(reset),
        .in_valid(md_pipe_in_valid && use_encrypt_pipe && key_available),
        .in_ready(enc_in_ready),
        .plaintext(md_pipe_in_data),
        .current_bank(current_bank),
        .round_keys(round_keys),
        .ciphertext(enc_out_data),
        .out_valid(enc_out_valid),
        .out_ready(md_pipe_out_ready),
        .bank_busy(enc_bank_busy)
    );

    // =====================================================================
    // DECRYPT PIPELINE
    // =====================================================================
    logic        dec_in_ready;
    logic        dec_out_valid;
    aes_block_t  dec_out_data;
    logic [1:0]  dec_bank_busy;

    AES_Decrypt_Pipe dec_pipe (
        .clk(clk), .reset(reset),
        .in_valid(md_pipe_in_valid && !use_encrypt_pipe && key_available),
        .in_ready(dec_in_ready),
        .ciphertext(md_pipe_in_data),
        .current_bank(current_bank),
        .round_keys(round_keys),
        .plaintext(dec_out_data),
        .out_valid(dec_out_valid),
        .out_ready(md_pipe_out_ready),
        .bank_busy(dec_bank_busy)
    );

    // =====================================================================
    // PIPELINE ARBITRATION
    // =====================================================================
    always_comb begin
        md_pipe_in_ready   = 1'b0;
        md_pipe_out_valid  = 1'b0;
        md_pipe_out_data   = '0;

        gcm_pipe_in_ready  = 1'b0;
        gcm_pipe_out_valid = 1'b0;
        gcm_pipe_out_data  = '0;

        if (use_encrypt_pipe) begin
            md_pipe_in_ready  = enc_in_ready && key_available;
            md_pipe_out_valid = enc_out_valid;
            md_pipe_out_data  = enc_out_data;

            // FIX-R1: override results routed via the datapath's internal_output
            gcm_pipe_out_valid = enc_out_valid && md_internal_output;
            gcm_pipe_out_data  = enc_out_data;
            gcm_pipe_in_ready  = enc_in_ready && key_available;
        end else begin
            md_pipe_in_ready  = dec_in_ready && key_available;
            md_pipe_out_valid = dec_out_valid;
            md_pipe_out_data  = dec_out_data;
        end
    end

    // =====================================================================
    // GHASH CORE
    // =====================================================================
    ghash_core ghash_inst (
        .clk(clk), .reset(reset),
        .h_load(ghash_h_load),
        .h_in(ghash_h_in),
        .data_valid(ghash_data_valid),
        .data_ready(ghash_data_ready),
        .data_in(ghash_data_in),
        .accum_clear(ghash_accum_clear),
        .ghash_val(ghash_val),
        .done(ghash_done)
    );

    // =====================================================================
    // GCM CTR ADVANCE
    // =====================================================================
    assign gcm_ctr_inc = md_pipe_accept && (mode == MODE_GCM)
                         && !gcm_pipe_override;

    // =====================================================================
    // USER OUTPUT
    // =====================================================================
    assign in_ready  = md_user_ready;
    assign out_valid = md_user_out_valid;
    assign data_out  = md_user_out_data;

    // =====================================================================
    // BANK BUSY
    // =====================================================================
    always_comb begin
        bank_busy = 2'b00;
        if (use_encrypt_pipe) bank_busy = enc_bank_busy;
        else                  bank_busy = dec_bank_busy;
    end

    // =====================================================================
    // BUSY
    // =====================================================================
    always_comb begin
        busy = 1'b0;
        if (key_system_busy)    busy = 1'b1;
        if (bank_busy != 2'b00) busy = 1'b1;
        if (gcm_pipe_override)  busy = 1'b1;
        if (gcm_pipe_in_valid)  busy = 1'b1;
    end

    // =====================================================================
    // DEBUG
    // =====================================================================
    assign dbg_bank_valid = bank_valid;
    assign dbg_bank_busy  = bank_busy;
    assign dbg_bank_free  = bank_free;

endmodule
