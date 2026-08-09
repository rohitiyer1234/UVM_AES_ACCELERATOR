// ============================================================================
//  rtl_fixed/aes_mode_datapath.sv
//
//  Drop-in replacement for the active variant in aes_mode_datapath.sv
//  (the un-commented block starting at line 2044 of the original).
//
//  FIXES APPLIED (vs original)
//  ===========================
//
//  BUG-R1 (COMPILE-BLOCKER)
//  ------------------------
//  aes_top connects `.internal_output(md_internal_output)` to this module
//  but the original module exposed no such port.  We add it.
//
//  BUG-R2 (OWNERSHIP CORRUPTION)
//  -----------------------------
//  Original push rule:
//      if (pipe_accept && !pipe_override && !meta_full) ...
//  Pop rule:
//      if (pipe_out_valid && pipe_out_ready && !meta_empty) ...
//  Override blocks were accepted by the AES pipe but pushed NOTHING into
//  the metadata FIFO; their result still popped the FIFO when it emerged
//  from the pipeline, consuming the wrong user metadata.
//
//  Fix: push metadata for EVERY accept (override or not) with the owner
//  bit set to `pipe_override`.  Output gating remains driven by
//  current_meta.owner, and the new `internal_output` port lets the top
//  level route override results to the GCM orchestrator.
//
//  All other behaviour preserved.
// ============================================================================
`timescale 1ns/1ps
import aes_pkg::*;

module aes_mode_datapath #(
    parameter int META_DEPTH = 32
)(
    input  logic        clk,
    input  logic        reset,

    // ---- MODE CONTROL ----
    input  aes_mode_e   mode,
    input  logic        enc_dec,            // 0 = encrypt, 1 = decrypt

    // ---- IV / CTR ----
    input  logic        iv_load,
    input  aes_block_t  iv_in,
    input  aes_block_t  gcm_ctr_in,

    // ---- GCM ORCHESTRATOR OVERRIDE ----
    input  logic        pipe_override,
    input  logic        override_in_valid,
    input  aes_block_t  override_in_data,

    // ---- USER INPUT ----
    input  logic        user_valid,
    output logic        user_ready,
    input  aes_block_t  user_data,

    // ---- AES PIPE INPUT ----
    output logic        pipe_in_valid,
    input  logic        pipe_in_ready,
    output aes_block_t  pipe_in_data,

    // ---- AES PIPE OUTPUT ----
    input  logic        pipe_out_valid,
    output logic        pipe_out_ready,
    input  aes_block_t  pipe_out_data,

    // ---- USER OUTPUT ----
    output logic        user_out_valid,
    input  logic        user_out_ready,
    output aes_block_t  user_out_data,

    // ---- INTERNAL (OVERRIDE) OUTPUT FLAG  (FIX-R1) ----
    // Asserted on the cycle that pipe_out_valid carries an override
    // (GCM-orchestrator-owned) result.  aes_top uses this to route the
    // result back to the orchestrator instead of the user.
    output logic        internal_output,

    // ---- EXPORTED PIPELINE ACCEPT (for GCM CTR increment) ----
    output logic        pipe_accept_o
);

    // =====================================================================
    // MODE HELPERS
    // =====================================================================

    function automatic logic needs_serialization(
        input aes_mode_e m,
        input logic dec
    );
        return (
            ((m == MODE_CBC) && !dec) ||
             (m == MODE_CFB)          ||
             (m == MODE_OFB)
        );
    endfunction

    function automatic logic is_stream_mode(input aes_mode_e m);
        return (
            (m == MODE_CFB) ||
            (m == MODE_OFB) ||
            (m == MODE_CTR) ||
            (m == MODE_GCM)
        );
    endfunction

    // =====================================================================
    // INTERNAL STATE
    // =====================================================================

    aes_block_t feedback;
    aes_block_t ctr_reg;

    logic feedback_waiting;
    logic serialized_gate;
    logic datapath_stall;

    logic pipe_accept;
    logic out_accept;

    aes_block_t pipe_in_mux;

    // =====================================================================
    // SERIALIZATION
    // =====================================================================

    assign serialized_gate =
            needs_serialization(mode, enc_dec) && feedback_waiting;

    assign datapath_stall = serialized_gate || pipe_override;

    // =====================================================================
    // USER READY
    // =====================================================================

    assign user_ready = pipe_in_ready && !datapath_stall;

    // =====================================================================
    // PIPE INPUT VALID
    // =====================================================================

    assign pipe_in_valid = pipe_override
                           ? override_in_valid
                           : (user_valid && !serialized_gate);

    // =====================================================================
    // PIPE ACCEPT (handshake)
    // =====================================================================

    assign pipe_accept   = pipe_in_valid && pipe_in_ready;
    assign out_accept    = user_out_valid && user_out_ready;
    assign pipe_accept_o = pipe_accept;

    // =====================================================================
    // INPUT MUX
    // =====================================================================

    always_comb begin
        pipe_in_mux = user_data;
        unique case (mode)
            MODE_ECB: pipe_in_mux = user_data;
            MODE_CBC: pipe_in_mux = enc_dec ? user_data
                                            : user_data ^ feedback;
            MODE_CFB,
            MODE_OFB: pipe_in_mux = feedback;
            MODE_CTR: pipe_in_mux = ctr_reg;
            MODE_GCM: pipe_in_mux = gcm_ctr_in;
            default : pipe_in_mux = user_data;
        endcase
    end

    assign pipe_in_data = pipe_override ? override_in_data : pipe_in_mux;

    // =====================================================================
    // FEEDBACK REGISTER  (CBC-enc / CFB / OFB)
    // =====================================================================

    always_ff @(posedge clk) begin
        if (reset)
            feedback <= '0;
        else if (iv_load)
            feedback <= iv_in;
        else begin
            unique case (mode)
                MODE_CBC: if (!enc_dec && out_accept) feedback <= pipe_out_data;
                MODE_CFB,
                MODE_OFB: if (out_accept)             feedback <= pipe_out_data;
                default : ;
            endcase
        end
    end

    // =====================================================================
    // CTR REGISTER
    // =====================================================================

    always_ff @(posedge clk) begin
        if (reset)
            ctr_reg <= '0;
        else if (iv_load)
            ctr_reg <= iv_in;
        else if (pipe_accept && !pipe_override && (mode == MODE_CTR))
            ctr_reg <= ctr_reg + 128'd1;
    end

    // =====================================================================
    // FEEDBACK SERIALIZATION FLAG
    // =====================================================================

    always_ff @(posedge clk) begin
        if (reset)
            feedback_waiting <= 1'b0;
        else begin
            unique case ({
                pipe_accept && !pipe_override
                            && needs_serialization(mode, enc_dec),
                out_accept  && feedback_waiting
            })
                2'b10:   feedback_waiting <= 1'b1;
                2'b01:   feedback_waiting <= 1'b0;
                2'b11:   feedback_waiting <= 1'b1;
                default: ;
            endcase
        end
    end

    // =====================================================================
    // METADATA FIFO  (FIX-R2)
    //
    // Push on EVERY pipe_accept, recording the owner bit so override
    // results pop their own metadata entry on the way out.
    // =====================================================================

    typedef struct packed {
        aes_block_t data;
        aes_mode_e  mode;
        logic       enc_dec;
        logic       owner;       // 1 = orchestrator override, 0 = user
    } meta_t;

    meta_t meta_fifo [0:META_DEPTH-1];

    logic [$clog2(META_DEPTH)-1:0] meta_wr_ptr;
    logic [$clog2(META_DEPTH)-1:0] meta_rd_ptr;
    logic [$clog2(META_DEPTH+1)-1:0] meta_count;

    logic meta_full;
    logic meta_empty;

    meta_t current_meta;

    assign meta_full  = (meta_count == META_DEPTH);
    assign meta_empty = (meta_count == 0);

    // ------------------------------------------------------------------
    // current_meta is the HEAD of the FIFO (combinational read)
    // so that consumer gating sees the head value the cycle it appears.
    // We still register a copy of the popped entry for post-processing
    // XORs in stream modes.
    // ------------------------------------------------------------------

    meta_t head_meta;
    assign head_meta = meta_fifo[meta_rd_ptr];

    always_ff @(posedge clk) begin
        if (reset) begin
            meta_wr_ptr        <= '0;
            meta_rd_ptr        <= '0;
            meta_count         <= '0;
            current_meta.data    <= '0;
            current_meta.mode    <= MODE_ECB;
            current_meta.enc_dec <= 1'b0;
            current_meta.owner   <= 1'b0;
        end else begin
            // ----- PUSH (any pipe_accept, including override) -----
            if (pipe_accept && !meta_full) begin
                meta_fifo[meta_wr_ptr].data    <= pipe_override ? override_in_data
                                                                : user_data;
                meta_fifo[meta_wr_ptr].mode    <= mode;
                meta_fifo[meta_wr_ptr].enc_dec <= enc_dec;
                meta_fifo[meta_wr_ptr].owner   <= pipe_override;
                meta_wr_ptr                    <= meta_wr_ptr + 1'b1;
            end

            // ----- POP -----
            if (pipe_out_valid && pipe_out_ready && !meta_empty) begin
                current_meta <= head_meta;
                meta_rd_ptr  <= meta_rd_ptr + 1'b1;
            end

            // ----- COUNT -----
            unique case ({
                pipe_accept && !meta_full,
                pipe_out_valid && pipe_out_ready && !meta_empty
            })
                2'b10:   meta_count <= meta_count + 1'b1;
                2'b01:   meta_count <= meta_count - 1'b1;
                default: ;
            endcase
        end
    end

    // =====================================================================
    // OUTPUT GATING
    //
    // pipe_out_ready  : when head is internal we always accept it (the
    //                   orchestrator latches results combinationally);
    //                   otherwise we wait for user_out_ready.
    // user_out_valid  : only the user-owned head exits via the user port.
    // internal_output : asserted alongside pipe_out_valid when the head
    //                   is orchestrator-owned.
    // =====================================================================

    assign pipe_out_ready  = head_meta.owner ? 1'b1 : user_out_ready;
    assign user_out_valid  = pipe_out_valid && !meta_empty && !head_meta.owner;
    assign internal_output = pipe_out_valid && !meta_empty &&  head_meta.owner;

    // =====================================================================
    // OUTPUT POST-PROCESSING
    //
    // Uses head_meta (not current_meta) so that the data emerging this
    // cycle matches the metadata pushed at the same logical position.
    // current_meta is kept for diagnostics / potential downstream needs.
    // =====================================================================

    always_comb begin
        user_out_data = pipe_out_data;
        unique case (head_meta.mode)
            MODE_ECB: user_out_data = pipe_out_data;
            MODE_CBC: user_out_data = head_meta.enc_dec
                                       ? (pipe_out_data ^ head_meta.data)
                                       :  pipe_out_data;
            MODE_CFB,
            MODE_OFB,
            MODE_CTR,
            MODE_GCM: user_out_data = pipe_out_data ^ head_meta.data;
            default : user_out_data = pipe_out_data;
        endcase
    end

endmodule
