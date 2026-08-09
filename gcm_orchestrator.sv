// ============================================================================
//  rtl_fixed/gcm_orchestrator.sv
//
//  Drop-in replacement for gcm_orchestrator.sv that adds:
//    - explicit GCM_AAD phase between J0 generation and CTR payload    (FIX-R3)
//    - AAD valid/ready/data ports                                      (FIX-R3)
//    - length-aware GCM_LEN that uses caller-provided length counters  (FIX-R4)
//    - payload_last strobe replacing the fragile (!in_valid&&!out_valid)
//      payload_done heuristic                                          (FIX-R4)
//    - aad_last strobe so a caller can mark end of AAD phase           (FIX-R3)
//    - clean override release in PAYLOAD/LEN/TAG                       (FIX-R3)
//
//  All other behaviour preserved.
// ============================================================================
`timescale 1ns/1ps
import aes_pkg::*;

module gcm_orchestrator(
    input  logic        clk,
    input  logic        reset,

    // -------------------- CONTROL --------------------
    input  logic        start_gcm,      // pulse: begin a new GCM session
    input  logic        payload_last,   // pulse on the LAST payload accept
                                        // FIX-R4 replaces "payload_done"

    // -------------------- AES PIPE OWNERSHIP --------------------
    output logic        pipe_override,
    output logic        pipe_in_valid,
    input  logic        pipe_in_ready,
    output aes_block_t  pipe_in_data,

    input  logic        pipe_out_valid,
    input  aes_block_t  pipe_out_data,

    // -------------------- COUNTER --------------------
    input  aes_block_t  j0,

    // -------------------- AAD STREAM (FIX-R3) --------------------
    input  logic        aad_valid,
    output logic        aad_ready,
    input  aes_block_t  aad_data,
    input  logic        aad_last,       // pulse on the final AAD block accept

    // -------------------- GHASH CONTROL --------------------
    output logic        h_load,
    output aes_block_t  h_value,

    output logic        ghash_valid,
    input  logic        ghash_ready,
    output aes_block_t  ghash_data,

    input  aes_block_t  ghash_result,

    // -------------------- CIPHERTEXT STREAM IN --------------------
    input  logic        ct_valid,
    input  aes_block_t  ct_data,

    // -------------------- LENGTH INFO --------------------
    // Bit counts of AAD and payload, owned by the caller. Captured by
    // this module when it transitions into GCM_LEN.
    input  logic [63:0] aad_length_bits,
    input  logic [63:0] payload_length_bits,

    // -------------------- TAG --------------------
    output logic        tag_valid,
    output aes_block_t  tag_out,

    // -------------------- STATUS --------------------
    output logic        busy
);

    // =====================================================================
    // FSM
    // =====================================================================
    typedef enum logic [2:0] {
        GCM_IDLE,
        GCM_H_GEN,
        GCM_J0_GEN,
        GCM_AAD,        // FIX-R3
        GCM_PAYLOAD,
        GCM_LEN,
        GCM_TAG
    } gcm_state_e;

    gcm_state_e state;

    // =====================================================================
    // INTERNAL REGS
    // =====================================================================
    aes_block_t h_reg;
    aes_block_t j0_enc_reg;
    logic h_sent, j0_sent, len_sent;
    logic aad_seen_any;            // at least one AAD block absorbed

    logic [63:0] aad_len_capture;
    logic [63:0] pld_len_capture;

    aes_block_t length_block;
    assign length_block = { aad_len_capture, pld_len_capture };

    // =====================================================================
    // h_load is a registered one-cycle pulse driven by the FSM.
    // Everything else is combinational.
    // =====================================================================
    logic h_load_q;
    assign h_load = h_load_q;

    // =====================================================================
    // DEFAULTS  (combinational outputs)
    // =====================================================================
    always_comb begin
        pipe_override = 1'b0;
        pipe_in_valid = 1'b0;
        pipe_in_data  = '0;

        h_value       = h_reg;

        ghash_valid   = 1'b0;
        ghash_data    = '0;

        aad_ready     = 1'b0;
        tag_valid     = 1'b0;
        busy          = (state != GCM_IDLE);

        unique case (state)
            // ----------------------------------------------------------
            // GCM_H_GEN : send AES(0) to derive H
            // ----------------------------------------------------------
            GCM_H_GEN: begin
                pipe_override = 1'b1;
                if (!h_sent) begin
                    pipe_in_valid = 1'b1;
                    pipe_in_data  = 128'd0;
                end
            end

            // ----------------------------------------------------------
            // GCM_J0_GEN : send J0 through AES to derive EK(J0)
            // ----------------------------------------------------------
            GCM_J0_GEN: begin
                pipe_override = 1'b1;
                if (!j0_sent) begin
                    pipe_in_valid = 1'b1;
                    pipe_in_data  = j0;
                end
            end

            // ----------------------------------------------------------
            // GCM_AAD : absorb AAD blocks into GHASH (FIX-R3)
            //   We deliberately keep pipe_override LOW here - the AES
            //   pipe is unused while AAD streams into GHASH.
            // ----------------------------------------------------------
            GCM_AAD: begin
                ghash_valid = aad_valid;
                ghash_data  = aad_data;
                aad_ready   = ghash_ready;
            end

            // ----------------------------------------------------------
            // GCM_PAYLOAD : CTR runs via mode_datapath; absorb CT
            // ----------------------------------------------------------
            GCM_PAYLOAD: begin
                ghash_valid = ct_valid;
                ghash_data  = ct_data;
            end

            // ----------------------------------------------------------
            // GCM_LEN : push the length block into GHASH
            // ----------------------------------------------------------
            GCM_LEN: begin
                if (!len_sent) begin
                    ghash_valid = 1'b1;
                    ghash_data  = length_block;
                end
            end

            // ----------------------------------------------------------
            // GCM_TAG : present final tag for one cycle
            // ----------------------------------------------------------
            GCM_TAG: begin
                tag_valid = 1'b1;
            end

            default: ;
        endcase
    end

    // =====================================================================
    // FSM SEQUENTIAL
    // =====================================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            state           <= GCM_IDLE;
            h_reg           <= '0;
            j0_enc_reg      <= '0;
            h_sent          <= 1'b0;
            j0_sent         <= 1'b0;
            len_sent        <= 1'b0;
            aad_seen_any    <= 1'b0;
            aad_len_capture <= 64'd0;
            pld_len_capture <= 64'd0;
            tag_out         <= '0;
            h_load_q        <= 1'b0;
        end else begin
            h_load_q <= 1'b0;   // default; FSM pulses it for one cycle
            unique case (state)
                // ------------------------------------------------------
                GCM_IDLE: begin
                    h_sent       <= 1'b0;
                    j0_sent      <= 1'b0;
                    len_sent     <= 1'b0;
                    aad_seen_any <= 1'b0;
                    if (start_gcm) state <= GCM_H_GEN;
                end

                // ------------------------------------------------------
                GCM_H_GEN: begin
                    if (pipe_in_valid && pipe_in_ready) h_sent <= 1'b1;
                    if (pipe_out_valid) begin
                        h_reg    <= pipe_out_data;
                        h_load_q <= 1'b1;    // pulse next cycle
                        state    <= GCM_J0_GEN;
                    end
                end

                // ------------------------------------------------------
                GCM_J0_GEN: begin
                    if (pipe_in_valid && pipe_in_ready) j0_sent <= 1'b1;
                    if (pipe_out_valid) begin
                        j0_enc_reg <= pipe_out_data;
                        state      <= GCM_AAD;       // FIX-R3: enter AAD
                    end
                end

                // ------------------------------------------------------
                // GCM_AAD : stay until aad_last AND ghash is idle.
                // If the caller has no AAD, they must just leave aad_valid
                // low and pulse aad_last immediately - we then skip to
                // PAYLOAD without absorbing anything.
                // ------------------------------------------------------
                GCM_AAD: begin
                    if (aad_valid && aad_ready) aad_seen_any <= 1'b1;
                    if (aad_last && ghash_ready) state <= GCM_PAYLOAD;
                end

                // ------------------------------------------------------
                // GCM_PAYLOAD : FIX-R4 transition on payload_last strobe.
                // Allow ghash to settle before moving to LEN.
                // ------------------------------------------------------
                GCM_PAYLOAD: begin
                    if (payload_last && ghash_ready) begin
                        aad_len_capture <= aad_length_bits;
                        pld_len_capture <= payload_length_bits;
                        state           <= GCM_LEN;
                    end
                end

                // ------------------------------------------------------
                GCM_LEN: begin
                    if (ghash_valid && ghash_ready) begin
                        len_sent <= 1'b1;
                        state    <= GCM_TAG;
                    end
                end

                // ------------------------------------------------------
                GCM_TAG: begin
                    tag_out <= ghash_result ^ j0_enc_reg;
                    state   <= GCM_IDLE;
                end

                default: state <= GCM_IDLE;
            endcase
        end
    end

endmodule
