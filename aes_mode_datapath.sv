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
/*`timescale 1ns/1ps
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
    output logic        pipe_accept_o,
    
    output logic        pipe_use_encrypt,
    output logic        ret_use_encrypt,
    output logic         head_owner_o
);
    
       // new port


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

    assign pipe_in_valid =
    pipe_override
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
    // METADATA FIFO  (FIX-R2)
    //
    // Push on EVERY pipe_accept, recording the owner bit so override
    // results pop their own metadata entry on the way out.
    // =====================================================================

    typedef struct packed {
        aes_block_t data;
        aes_mode_e  mode;
        logic       enc_dec;
        logic       owner;
        logic       use_encrypt_pipe;       // 1 = orchestrator override, 0 = user
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
    //assign head_meta = meta_fifo[meta_rd_ptr];
   
   wire popping = pipe_out_valid && pipe_out_ready && !meta_empty;
    //assign head_meta = popping
    //? meta_fifo[(meta_rd_ptr + 1'b1) % META_DEPTH]
    //: meta_fifo[meta_rd_ptr];
    logic [$clog2(META_DEPTH)-1:0] meta_next_ptr;

    assign meta_next_ptr =
    (meta_rd_ptr == META_DEPTH-1)
        ? '0
        : (meta_rd_ptr + 1'b1);

    assign head_meta = popping
        ? meta_fifo[meta_next_ptr]
        : meta_fifo[meta_rd_ptr];
    
    
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

    meta_fifo[meta_wr_ptr].data <=
            pipe_override
                ? override_in_data
                : user_data;

    meta_fifo[meta_wr_ptr].mode <= mode;

    meta_fifo[meta_wr_ptr].enc_dec <= enc_dec;

    meta_fifo[meta_wr_ptr].owner <= pipe_override;

    // ---------------------------------------------------------
    // CORRECT PIPE OWNERSHIP STORAGE
    // ---------------------------------------------------------

    meta_fifo[meta_wr_ptr].use_encrypt_pipe <=
            ((mode == MODE_ECB) || (mode == MODE_CBC))
                ? !enc_dec
                : 1'b1;

    meta_wr_ptr <= meta_wr_ptr + 1'b1;

       
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
    
    // driven as a registered signal - no pipe_out_valid in cone
always_ff @(posedge clk)
    if (reset) head_owner_o <= 1'b0;
    else       head_owner_o <= !meta_empty && head_meta.owner;
    
    
    // =====================================================================
// FEEDBACK REGISTER
//
// CBC encrypt : feedback = ciphertext output
// CBC decrypt : feedback = input ciphertext block
//
// CFB encrypt : feedback = ciphertext output
// CFB decrypt : feedback = input ciphertext block
//
// OFB         : feedback = AES(feedback)
// =====================================================================

always_ff @(posedge clk) begin
    if (reset)
        feedback <= '0;

    else if (iv_load)
        feedback <= iv_in;

    else begin
        unique case (mode)

            // ---------------------------------------------------------
            // CBC
            // ---------------------------------------------------------

            // encrypt
            MODE_CBC: begin
                if (!enc_dec && out_accept)
                    feedback <= pipe_out_data;

                // decrypt
                else if (enc_dec && pipe_accept && !pipe_override)
                    feedback <= user_data;
            end

            // ---------------------------------------------------------
            // CFB
            // ---------------------------------------------------------

            // encrypt:
            // feedback = ciphertext
            MODE_CFB: begin
                 if (!enc_dec && pipe_out_valid && pipe_out_ready &&
                        !meta_empty && !head_meta.owner)
                 feedback <= pipe_out_data;        // AES keystream output, not XOR result
             else if (enc_dec && pipe_accept && !pipe_override)
                feedback <= user_data;
            end

            // ---------------------------------------------------------
            // OFB
            // ---------------------------------------------------------

            MODE_OFB: begin
                if (pipe_out_valid && pipe_out_ready)
                        feedback <= pipe_out_data;
            end

            default: ;
        endcase
    end
end
    
      // =====================================================================
// FEEDBACK SERIALIZATION TRACKER
//
// IMPORTANT:
// Clear logic MUST use the RETURNING transaction metadata
// (head_meta), not current global mode state.
//
// Otherwise pipelined overlapping traffic corrupts feedback ordering.
// =====================================================================
always_ff @(posedge clk) begin
    if (reset) feedback_waiting <= 1'b0;
    else begin
        if (pipe_out_valid && pipe_out_ready && !meta_empty &&
            needs_serialization(head_meta.mode, head_meta.enc_dec))
            feedback_waiting <= 1'b0;
        // This assignment is last → it wins on simultaneous set+clear
        if (pipe_accept && !pipe_override &&
            needs_serialization(mode, enc_dec))
            feedback_waiting <= 1'b1;
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
    assign pipe_out_ready =
        (!meta_empty && head_meta.owner)
            ? 1'b1
            : user_out_ready;
    assign user_out_valid  = pipe_out_valid && !meta_empty && !head_meta.owner;
    assign internal_output = pipe_out_valid && !meta_empty &&  head_meta.owner;
    assign ret_use_encrypt = !meta_empty ? head_meta.use_encrypt_pipe : 1'b1;

        
always_comb begin

    pipe_use_encrypt = 1'b1;

    unique case (mode)

        MODE_ECB,
        MODE_CBC:
            pipe_use_encrypt = !enc_dec;

        MODE_CFB,
        MODE_OFB,
        MODE_CTR,
        MODE_GCM:
            pipe_use_encrypt = 1'b1;

        default:
            pipe_use_encrypt = 1'b1;
    endcase
end


    // =====================================================================
    // OUTPUT POST-PROCESSING
    //
    // Uses head_meta (not current_meta) so that the data emerging this
    // cycle matches the metadata pushed at the same logical position.
    // current_meta is kept for diagnostics / potential downstream needs.
    // =====================================================================

    // =====================================================================
// OUTPUT POST-PROCESSING
//
// ECB:
//   encrypt/decrypt => direct AES output
//
// CBC:
//   encrypt => ciphertext direct
//   decrypt => AES_dec(ciphertext) XOR previous ciphertext
//
// CFB:
//   encrypt => plaintext XOR AES(feedback)
//   decrypt => ciphertext XOR AES(feedback)
//
// OFB/CTR/GCM:
//   output = input XOR keystream
// =====================================================================

always_comb begin

    user_out_data = pipe_out_data;

    unique case (head_meta.mode)

        // -------------------------------------------------------------
        // ECB
        // -------------------------------------------------------------

        MODE_ECB: begin
            user_out_data = pipe_out_data;
        end

        // -------------------------------------------------------------
        // CBC
        // -------------------------------------------------------------

        MODE_CBC: begin
            if (head_meta.enc_dec)
                //user_out_data = pipe_out_data ^ feedback;
                user_out_data = pipe_out_data ^ head_meta.data;
            else
                user_out_data = pipe_out_data;
        end

        // -------------------------------------------------------------
        // CFB
        // -------------------------------------------------------------

        MODE_CFB: begin
            user_out_data = pipe_out_data ^ head_meta.data;
        end

        // -------------------------------------------------------------
        // OFB / CTR / GCM
        // -------------------------------------------------------------

        MODE_OFB,
        MODE_CTR,
        MODE_GCM: begin
            user_out_data = pipe_out_data ^ head_meta.data;
        end

        default: begin
            user_out_data = pipe_out_data;
        end
    endcase
end

endmodule

`timescale 1ns/1ps
import aes_pkg::*;

module aes_mode_datapath #(
    parameter int META_DEPTH = 32
)(
    input  logic        clk,
    input  logic        reset,

    // -----------------------------------------------------------------
    // MODE CONTROL
    // -----------------------------------------------------------------

    input  aes_mode_e   mode,
    input  logic        enc_dec,

    // -----------------------------------------------------------------
    // IV / CTR
    // -----------------------------------------------------------------

    input  logic        iv_load,
    input  aes_block_t  iv_in,
    input  aes_block_t  gcm_ctr_in,

    // -----------------------------------------------------------------
    // GCM OVERRIDE
    // -----------------------------------------------------------------

    input  logic        pipe_override,
    input  logic        override_in_valid,
    input  aes_block_t  override_in_data,

    // -----------------------------------------------------------------
    // USER INPUT
    // -----------------------------------------------------------------

    input  logic        user_valid,
    output logic        user_ready,
    input  aes_block_t  user_data,

    // -----------------------------------------------------------------
    // AES PIPE INPUT
    // -----------------------------------------------------------------

    output logic        pipe_in_valid,
    input  logic        pipe_in_ready,
    output aes_block_t  pipe_in_data,

    // -----------------------------------------------------------------
    // AES PIPE OUTPUT
    // -----------------------------------------------------------------

    input  logic        pipe_out_valid,
    output logic        pipe_out_ready,
    input  aes_block_t  pipe_out_data,

    // -----------------------------------------------------------------
    // USER OUTPUT
    // -----------------------------------------------------------------

    output logic        user_out_valid,
    input  logic        user_out_ready,
    output aes_block_t  user_out_data,

    // -----------------------------------------------------------------
    // INTERNAL RETURN
    // -----------------------------------------------------------------

    output logic        internal_output,

    // -----------------------------------------------------------------
    // PIPE CONTROL
    // -----------------------------------------------------------------

    output logic        pipe_accept_o,
    output logic        pipe_use_encrypt,
    output logic        ret_use_encrypt,
    output logic        head_owner_o
);

    // ================================================================
    // HELPERS
    // ================================================================

    function automatic logic needs_serialization(
        input aes_mode_e m,
        input logic dec
    );
        return (
            ((m == MODE_CBC) && !dec) ||
            (m == MODE_CFB) ||
            (m == MODE_OFB)
        );
    endfunction

    // ================================================================
    // INTERNALS
    // ================================================================

    aes_block_t feedback;
    aes_block_t ctr_reg;

    logic feedback_waiting;

    logic pipe_accept;
    logic out_accept;

    // ================================================================
    // PIPE INPUT CONTROL
    // ================================================================

    assign pipe_in_valid =
        pipe_override
            ? override_in_valid
            : (
                user_valid &&
                !feedback_waiting
              );

    assign pipe_accept =
        pipe_in_valid &&
        pipe_in_ready;

    assign pipe_accept_o = pipe_accept;

    assign user_ready =
        pipe_in_ready &&
        !feedback_waiting &&
        !pipe_override;

    // ================================================================
    // PIPE INPUT DATA
    // ================================================================

    always_comb begin

        pipe_in_data = user_data;

        unique case(mode)

            MODE_ECB:
                pipe_in_data = user_data;

            MODE_CBC:
                pipe_in_data =
                    enc_dec
                        ? user_data
                        : (user_data ^ feedback);

            MODE_CFB,
            MODE_OFB:
                pipe_in_data = feedback;

            MODE_CTR:
                pipe_in_data = ctr_reg;

            MODE_GCM:
                pipe_in_data = gcm_ctr_in;

            default:
                pipe_in_data = user_data;

        endcase

        if(pipe_override)
            pipe_in_data = override_in_data;

    end

    // ================================================================
    // CTR REGISTER
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset)
            ctr_reg <= '0;

        else if(iv_load)
            ctr_reg <= iv_in;

        else if(
            pipe_accept &&
            !pipe_override &&
            (mode == MODE_CTR)
        )
            ctr_reg <= ctr_reg + 128'd1;

    end

    // ================================================================
    // METADATA FIFO
    // ================================================================

    typedef struct packed {

        aes_block_t data;
        aes_mode_e  mode;
        logic       enc_dec;
        logic       owner;
        logic       use_encrypt_pipe;

    } meta_t;

    meta_t meta_fifo [0:META_DEPTH-1];

    logic [$clog2(META_DEPTH)-1:0] wr_ptr;
    logic [$clog2(META_DEPTH)-1:0] rd_ptr;

    logic [$clog2(META_DEPTH+1)-1:0] count;

    logic fifo_empty;
    logic fifo_full;

    meta_t head_meta;

    assign fifo_empty = (count == 0);
    assign fifo_full  = (count == META_DEPTH);

    // ================================================================
    // SAFE HEAD METADATA
    // ================================================================

    always_comb begin

        head_meta = '0;

        if(!fifo_empty)
            head_meta = meta_fifo[rd_ptr];

    end

    // ================================================================
    // FIFO MANAGEMENT
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset) begin

            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;

        end

        else begin

            // --------------------------------------------------------
            // PUSH
            // --------------------------------------------------------

            if(pipe_accept && !fifo_full) begin

                meta_fifo[wr_ptr].data <=
                    pipe_override
                        ? override_in_data
                        : user_data;

                meta_fifo[wr_ptr].mode <= mode;

                meta_fifo[wr_ptr].enc_dec <= enc_dec;

                meta_fifo[wr_ptr].owner <= pipe_override;

                meta_fifo[wr_ptr].use_encrypt_pipe <=
                    ((mode == MODE_ECB) || (mode == MODE_CBC))
                        ? !enc_dec
                        : 1'b1;

                wr_ptr <= wr_ptr + 1'b1;

            end

            // --------------------------------------------------------
            // POP
            // --------------------------------------------------------

            if(
                pipe_out_valid &&
                pipe_out_ready &&
                !fifo_empty
            ) begin

                rd_ptr <= rd_ptr + 1'b1;

            end

            // --------------------------------------------------------
            // COUNT
            // --------------------------------------------------------

            case({
                pipe_accept && !fifo_full,
                pipe_out_valid && pipe_out_ready && !fifo_empty
            })

                2'b10:
                    count <= count + 1'b1;

                2'b01:
                    count <= count - 1'b1;

                default: ;

            endcase

        end

    end

    // ================================================================
    // FEEDBACK TRACKING
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset)
            feedback <= '0;

        else if(iv_load)
            feedback <= iv_in;

        else begin

            unique case(head_meta.mode)

                // ----------------------------------------------------
                // CBC
                // ----------------------------------------------------

                MODE_CBC: begin

                    // encrypt
                    if(
                        !head_meta.enc_dec &&
                        pipe_out_valid &&
                        pipe_out_ready &&
                        !fifo_empty
                    )
                        feedback <= pipe_out_data;

                    // decrypt
                    else if(
                        head_meta.enc_dec &&
                        pipe_accept &&
                        !pipe_override
                    )
                        feedback <= user_data;

                end

                // ----------------------------------------------------
                // CFB
                // ----------------------------------------------------

                MODE_CFB: begin

                    if(
                        !head_meta.enc_dec &&
                        pipe_out_valid &&
                        pipe_out_ready &&
                        !fifo_empty
                    )
                        feedback <= user_out_data;

                    else if(
                        head_meta.enc_dec &&
                        pipe_accept &&
                        !pipe_override
                    )
                        feedback <= user_data;

                end

                // ----------------------------------------------------
                // OFB
                // ----------------------------------------------------

                MODE_OFB: begin

                    if(
                        pipe_out_valid &&
                        pipe_out_ready &&
                        !fifo_empty
                    )
                        feedback <= pipe_out_data;

                end

                default: ;

            endcase

        end

    end

    // ================================================================
    // SERIALIZATION TRACKING
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset)
            feedback_waiting <= 1'b0;

        else begin

            if(
                pipe_out_valid &&
                pipe_out_ready &&
                !fifo_empty &&
                needs_serialization(
                    head_meta.mode,
                    head_meta.enc_dec
                )
            )
                feedback_waiting <= 1'b0;

            if(
                pipe_accept &&
                !pipe_override &&
                needs_serialization(mode, enc_dec)
            )
                feedback_waiting <= 1'b1;

        end

    end

    // ================================================================
    // OUTPUT CONTROL
    // ================================================================

    assign pipe_out_ready =
        head_meta.owner
            ? 1'b1
            : user_out_ready;

    assign user_out_valid =
        pipe_out_valid &&
        !fifo_empty &&
        !head_meta.owner;

    assign internal_output =
        pipe_out_valid &&
        !fifo_empty &&
        head_meta.owner;

    assign ret_use_encrypt =
        fifo_empty
            ? 1'b1
            : head_meta.use_encrypt_pipe;

    assign head_owner_o =
        !fifo_empty &&
        head_meta.owner;

    // ================================================================
    // INPUT PIPE OWNERSHIP
    // ================================================================

    always_comb begin

        pipe_use_encrypt = 1'b1;

        unique case(mode)

            MODE_ECB,
            MODE_CBC:
                pipe_use_encrypt = !enc_dec;

            default:
                pipe_use_encrypt = 1'b1;

        endcase

    end

    // ================================================================
    // OUTPUT POSTPROCESSING
    // ================================================================

    always_comb begin

        user_out_data = pipe_out_data;

        unique case(head_meta.mode)

            // --------------------------------------------------------
            // ECB
            // --------------------------------------------------------

            MODE_ECB:
                user_out_data = pipe_out_data;

            // --------------------------------------------------------
            // CBC
            // --------------------------------------------------------

            MODE_CBC: begin

                if(head_meta.enc_dec)
                    user_out_data =
                        pipe_out_data ^ head_meta.data;

                else
                    user_out_data = pipe_out_data;

            end

            // --------------------------------------------------------
            // STREAM MODES
            // --------------------------------------------------------

            MODE_CFB,
            MODE_OFB,
            MODE_CTR,
            MODE_GCM:

                user_out_data =
                    pipe_out_data ^ head_meta.data;

            default:
                user_out_data = pipe_out_data;

        endcase

    end

endmodule



`timescale 1ns/1ps
import aes_pkg::*;

module aes_mode_datapath #(
    parameter int META_DEPTH = 32
)(
    input  logic        clk,
    input  logic        reset,

    // -----------------------------------------------------------------
    // MODE CONTROL
    // -----------------------------------------------------------------

    input  aes_mode_e   mode,
    input  logic        enc_dec,

    // -----------------------------------------------------------------
    // IV / CTR
    // -----------------------------------------------------------------

    input  logic        iv_load,
    input  aes_block_t  iv_in,
    input  aes_block_t  gcm_ctr_in,

    // -----------------------------------------------------------------
    // GCM OVERRIDE
    // -----------------------------------------------------------------

    input  logic        pipe_override,
    input  logic        override_in_valid,
    input  aes_block_t  override_in_data,

    // -----------------------------------------------------------------
    // USER INPUT
    // -----------------------------------------------------------------

    input  logic        user_valid,
    output logic        user_ready,
    input  aes_block_t  user_data,

    // -----------------------------------------------------------------
    // AES PIPE INPUT
    // -----------------------------------------------------------------

    output logic        pipe_in_valid,
    input  logic        pipe_in_ready,
    output aes_block_t  pipe_in_data,

    // -----------------------------------------------------------------
    // AES PIPE OUTPUT
    // -----------------------------------------------------------------

    input  logic        pipe_out_valid,
    output logic        pipe_out_ready,
    input  aes_block_t  pipe_out_data,

    // -----------------------------------------------------------------
    // USER OUTPUT
    // -----------------------------------------------------------------

    output logic        user_out_valid,
    input  logic        user_out_ready,
    output aes_block_t  user_out_data,

    // -----------------------------------------------------------------
    // INTERNAL RETURN
    // -----------------------------------------------------------------

    output logic        internal_output,

    // -----------------------------------------------------------------
    // PIPE CONTROL
    // -----------------------------------------------------------------

    output logic        pipe_accept_o,
    output logic        pipe_use_encrypt,
    output logic        ret_use_encrypt,
    output logic        head_owner_o
);
    
    
        logic fifo_empty;
    logic fifo_full;
    
    // ================================================================
    // HELPERS
    // ================================================================

    function automatic logic needs_serialization(
        input aes_mode_e m,
        input logic dec
    );

        return (
            ((m == MODE_CBC) && !dec) ||
            (m == MODE_CFB) ||
            (m == MODE_OFB)
        );

    endfunction

    // ================================================================
    // INTERNALS
    // ================================================================

    aes_block_t feedback;
    aes_block_t ctr_reg;

    logic feedback_waiting;

    logic pipe_accept;

    // ================================================================
    // PIPE INPUT CONTROL
    // ================================================================

    assign pipe_in_valid =

        !fifo_full &&

        (
            pipe_override
                ? override_in_valid
                : (
                    user_valid &&
                    !feedback_waiting
                  )
        );

    assign pipe_accept =
        pipe_in_valid &&
        pipe_in_ready;

    assign pipe_accept_o =
        pipe_accept;

    assign user_ready =

        pipe_in_ready &&
        !feedback_waiting &&
        !pipe_override &&
        !fifo_full;

    // ================================================================
    // PIPE INPUT DATA
    // ================================================================

    always_comb begin

        pipe_in_data = user_data;

        unique case(mode)

            // --------------------------------------------------------
            // ECB
            // --------------------------------------------------------

            MODE_ECB:
                pipe_in_data = user_data;

            // --------------------------------------------------------
            // CBC
            // --------------------------------------------------------

            MODE_CBC:

                pipe_in_data =
                    enc_dec
                        ? user_data
                        : (user_data ^ feedback);

            // --------------------------------------------------------
            // CFB / OFB
            // --------------------------------------------------------

            MODE_CFB,
            MODE_OFB:

                pipe_in_data = feedback;

            // --------------------------------------------------------
            // CTR
            // --------------------------------------------------------

            MODE_CTR:

                pipe_in_data = ctr_reg;

            // --------------------------------------------------------
            // GCM
            // --------------------------------------------------------

            MODE_GCM:

                pipe_in_data = gcm_ctr_in;

            default:
                pipe_in_data = user_data;

        endcase

        // ------------------------------------------------------------
        // OVERRIDE HAS PRIORITY
        // ------------------------------------------------------------

        if(pipe_override)
            pipe_in_data = override_in_data;

    end

    // ================================================================
    // CTR REGISTER
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset)

            ctr_reg <= '0;

        else if(iv_load)

            ctr_reg <=
                (mode == MODE_GCM)
                    ? gcm_ctr_in
                    : iv_in;

        else if(
            pipe_accept &&
            !pipe_override &&
            (
                (mode == MODE_CTR) ||
                (mode == MODE_GCM)
            )
        )

            ctr_reg <= ctr_reg + 128'd1;

    end

    // ================================================================
    // METADATA FIFO
    // ================================================================

    typedef struct packed {

        aes_block_t data;
        aes_mode_e  mode;
        logic       enc_dec;
        logic       owner;
        logic       use_encrypt_pipe;

    } meta_t;

    meta_t meta_fifo [0:META_DEPTH-1];

    logic [$clog2(META_DEPTH)-1:0] wr_ptr;
    logic [$clog2(META_DEPTH)-1:0] rd_ptr;

    logic [$clog2(META_DEPTH+1)-1:0] count;



    meta_t head_meta;

    assign fifo_empty =
        (count == 0);

    assign fifo_full =
        (count == META_DEPTH);

    // ================================================================
    // SAFE HEAD METADATA
    // ================================================================

    always_comb begin

        head_meta = '0;

        if(!fifo_empty)
            head_meta = meta_fifo[rd_ptr];

    end

    // ================================================================
    // FIFO MANAGEMENT
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset) begin

            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;

        end

        else begin

            // --------------------------------------------------------
            // PUSH
            // --------------------------------------------------------

            if(
                pipe_accept &&
                !fifo_full
            ) begin

                meta_fifo[wr_ptr].data <=
                    pipe_override
                        ? override_in_data
                        : user_data;

                meta_fifo[wr_ptr].mode <=
                    mode;

                meta_fifo[wr_ptr].enc_dec <=
                    enc_dec;

                meta_fifo[wr_ptr].owner <=
                    pipe_override;

                meta_fifo[wr_ptr].use_encrypt_pipe <=

                    ((mode == MODE_ECB) ||
                     (mode == MODE_CBC))

                        ? !enc_dec
                        : 1'b1;

                wr_ptr <= wr_ptr + 1'b1;

            end

            // --------------------------------------------------------
            // POP
            // --------------------------------------------------------

            if(
                pipe_out_valid &&
                pipe_out_ready &&
                !fifo_empty
            )

                rd_ptr <= rd_ptr + 1'b1;

            // --------------------------------------------------------
            // COUNT
            // --------------------------------------------------------

            unique case({

                pipe_accept &&
                !fifo_full,

                pipe_out_valid &&
                pipe_out_ready &&
                !fifo_empty

            })

                2'b10:
                    count <= count + 1'b1;

                2'b01:
                    count <= count - 1'b1;

                default: ;

            endcase

        end

    end

    // ================================================================
    // FEEDBACK TRACKING
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset)

            feedback <= '0;

        else if(iv_load)

            feedback <= iv_in;

        else begin

            unique case(head_meta.mode)

                // ----------------------------------------------------
                // CBC
                // ----------------------------------------------------

                MODE_CBC: begin

                    // CBC ENCRYPT
                    if(
                        !head_meta.enc_dec &&
                        pipe_out_valid &&
                        pipe_out_ready &&
                        !fifo_empty
                    )

                        feedback <= pipe_out_data;

                    // CBC DECRYPT
                    else if(
                        head_meta.enc_dec &&
                        pipe_accept &&
                        !pipe_override
                    )

                        feedback <= user_data;

                end

                // ----------------------------------------------------
                // CFB
                // ----------------------------------------------------

                MODE_CFB: begin

                    // CFB ENCRYPT
                    if(
                        !head_meta.enc_dec &&
                        pipe_out_valid &&
                        pipe_out_ready &&
                        !fifo_empty
                    )

                        feedback <=
                            pipe_out_data ^
                            head_meta.data;

                    // CFB DECRYPT
                    else if(
                        head_meta.enc_dec &&
                        pipe_accept &&
                        !pipe_override
                    )

                        feedback <= user_data;

                end

                // ----------------------------------------------------
                // OFB
                // ----------------------------------------------------

                MODE_OFB: begin

                    if(
                        pipe_out_valid &&
                        pipe_out_ready &&
                        !fifo_empty
                    )

                        feedback <= pipe_out_data;

                end

                default: ;

            endcase

        end

    end

    // ================================================================
    // SERIALIZATION TRACKING
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset)

            feedback_waiting <= 1'b0;

        else begin

            unique case({

                pipe_accept &&
                !pipe_override &&
                needs_serialization(mode, enc_dec),

                pipe_out_valid &&
                pipe_out_ready &&
                !fifo_empty &&
                needs_serialization(
                    head_meta.mode,
                    head_meta.enc_dec
                )

            })

                // ----------------------------------------------------
                // NEW SERIALIZED BLOCK ENTERED
                // ----------------------------------------------------

                2'b10:
                    feedback_waiting <= 1'b1;

                // ----------------------------------------------------
                // SERIALIZED BLOCK COMPLETED
                // ----------------------------------------------------

                2'b01:
                    feedback_waiting <= 1'b0;

                // ----------------------------------------------------
                // ONE LEFT / ONE ENTERED
                // ----------------------------------------------------

                2'b11:
                    feedback_waiting <= 1'b1;

                default: ;

            endcase

        end

    end

    // ================================================================
    // OUTPUT CONTROL
    // ================================================================

    assign pipe_out_ready =

        head_meta.owner
            ? 1'b1
            : user_out_ready;

    assign user_out_valid =

        pipe_out_valid &&
        !fifo_empty &&
        !head_meta.owner;

    assign internal_output =

        pipe_out_valid &&
        !fifo_empty &&
        head_meta.owner;

    assign ret_use_encrypt =

        fifo_empty
            ? 1'b1
            : head_meta.use_encrypt_pipe;

    assign head_owner_o =

        !fifo_empty &&
        head_meta.owner;

    // ================================================================
    // INPUT PIPE OWNERSHIP
    // ================================================================

    always_comb begin

        pipe_use_encrypt = 1'b1;

        unique case(mode)

            MODE_ECB,
            MODE_CBC:

                pipe_use_encrypt = !enc_dec;

            default:
                pipe_use_encrypt = 1'b1;

        endcase

    end

    // ================================================================
    // OUTPUT POSTPROCESSING
    // ================================================================

    always_comb begin

        user_out_data = pipe_out_data;

        unique case(head_meta.mode)

            // --------------------------------------------------------
            // ECB
            // --------------------------------------------------------

            MODE_ECB:

                user_out_data = pipe_out_data;

            // --------------------------------------------------------
            // CBC
            // --------------------------------------------------------

            MODE_CBC: begin

                // CBC DECRYPT
                if(head_meta.enc_dec)

                    user_out_data =
    pipe_out_data ^
    head_meta.data;

                // CBC ENCRYPT
                else

                    user_out_data =
                        pipe_out_data;

            end

            // --------------------------------------------------------
            // STREAM MODES
            // --------------------------------------------------------

            MODE_CFB,
            MODE_OFB,
            MODE_CTR,
            MODE_GCM:

                user_out_data =
                    pipe_out_data ^
                    head_meta.data;

            default:

                user_out_data = pipe_out_data;

        endcase

    end

endmodule


`timescale 1ns/1ps

import aes_pkg::*;

module aes_mode_datapath #(
    parameter int META_DEPTH = 32
)(
    input  logic        clk,
    input  logic        reset,

    // -----------------------------------------------------------------
    // MODE CONTROL
    // -----------------------------------------------------------------

    input  aes_mode_e   mode,
    input  logic        enc_dec,

    // -----------------------------------------------------------------
    // IV / CTR
    // -----------------------------------------------------------------

    input  logic        iv_load,
    input  aes_block_t  iv_in,
    input  aes_block_t  gcm_ctr_in,

    // -----------------------------------------------------------------
    // GCM OVERRIDE
    // -----------------------------------------------------------------

    input  logic        pipe_override,
    input  logic        override_in_valid,
    input  aes_block_t  override_in_data,

    // -----------------------------------------------------------------
    // USER INPUT
    // -----------------------------------------------------------------

    input  logic        user_valid,
    output logic        user_ready,
    input  aes_block_t  user_data,

    // -----------------------------------------------------------------
    // AES PIPE INPUT
    // -----------------------------------------------------------------

    output logic        pipe_in_valid,
    input  logic        pipe_in_ready,
    output aes_block_t  pipe_in_data,

    // -----------------------------------------------------------------
    // AES PIPE OUTPUT
    // -----------------------------------------------------------------

    input  logic        pipe_out_valid,
    output logic        pipe_out_ready,
    input  aes_block_t  pipe_out_data,

    // -----------------------------------------------------------------
    // USER OUTPUT
    // -----------------------------------------------------------------

    output logic        user_out_valid,
    input  logic        user_out_ready,
    output aes_block_t  user_out_data,

    // -----------------------------------------------------------------
    // INTERNAL RETURN
    // -----------------------------------------------------------------

    output logic        internal_output,

    // -----------------------------------------------------------------
    // PIPE CONTROL
    // -----------------------------------------------------------------

    output logic        pipe_accept_o,
    output logic        pipe_use_encrypt,
    output logic        ret_use_encrypt,
    output logic        head_owner_o
);

    // ================================================================
    // FIFO FLAGS
    // ================================================================

    logic fifo_empty;
    logic fifo_full;

    // ================================================================
    // HELPERS
    // ================================================================

    function automatic logic needs_serialization(
        input aes_mode_e m,
        input logic dec
    );

        return (
            ((m == MODE_CBC) && !dec) ||
            (m == MODE_CFB) ||
            (m == MODE_OFB)
        );

    endfunction

    // ================================================================
    // INTERNALS
    // ================================================================

    aes_block_t feedback;
    aes_block_t ctr_reg;

    logic feedback_waiting;

    logic pipe_accept;

    // ================================================================
    // PIPE INPUT CONTROL
    // ================================================================

    assign pipe_in_valid =

        !fifo_full &&

        (
            pipe_override
                ? override_in_valid
                : (
                    user_valid &&
                    !feedback_waiting
                  )
        );

    assign pipe_accept =
        pipe_in_valid &&
        pipe_in_ready;

    assign pipe_accept_o =
        pipe_accept;

    assign user_ready =

        pipe_in_ready &&
        !feedback_waiting &&
        !pipe_override &&
        !fifo_full;

    // ================================================================
    // PIPE INPUT DATA
    // ================================================================

    always_comb begin

        pipe_in_data = user_data;

        unique case(mode)

            // --------------------------------------------------------
            // ECB
            // --------------------------------------------------------

            MODE_ECB:
                pipe_in_data = user_data;

            // --------------------------------------------------------
            // CBC
            // --------------------------------------------------------

            MODE_CBC:

                pipe_in_data =
                    enc_dec
                        ? user_data
                        : (user_data ^ feedback);

            // --------------------------------------------------------
            // CFB / OFB
            // --------------------------------------------------------

            MODE_CFB,
            MODE_OFB:

                pipe_in_data = feedback;

            // --------------------------------------------------------
            // CTR
            // --------------------------------------------------------

            MODE_CTR:

                pipe_in_data = ctr_reg;

            // --------------------------------------------------------
            // GCM
            // --------------------------------------------------------

            MODE_GCM:

                pipe_in_data = gcm_ctr_in;

            default:
                pipe_in_data = user_data;

        endcase

        // ------------------------------------------------------------
        // OVERRIDE PRIORITY
        // ------------------------------------------------------------

        if(pipe_override)
            pipe_in_data = override_in_data;

    end

    // ================================================================
    // CTR REGISTER
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset)

            ctr_reg <= '0;

        else if(iv_load)

            ctr_reg <=
                (mode == MODE_GCM)
                    ? gcm_ctr_in
                    : iv_in;

        else if(
            pipe_accept &&
            !pipe_override &&
            (
                (mode == MODE_CTR) ||
                (mode == MODE_GCM)
            )
        )

            ctr_reg <= ctr_reg + 128'd1;

    end

    // ================================================================
    // METADATA FIFO
    // ================================================================

    typedef struct packed {

        aes_block_t data;
        aes_mode_e  mode;
        logic       enc_dec;
        logic       owner;
        logic       use_encrypt_pipe;

    } meta_t;

    meta_t meta_fifo [0:META_DEPTH-1];

    logic [$clog2(META_DEPTH)-1:0] wr_ptr;
    logic [$clog2(META_DEPTH)-1:0] rd_ptr;

    logic [$clog2(META_DEPTH+1)-1:0] count;

    meta_t head_meta;
    meta_t retire_meta;

    logic retire_fire;
    assign fifo_empty =
        (count == 0);

    assign fifo_full =
        (count == META_DEPTH);
        
        assign retire_fire =

    pipe_out_valid &&
    pipe_out_ready &&
    !fifo_empty;

    // ================================================================
    // SAFE HEAD METADATA
    // ================================================================

    always_comb begin

        head_meta = '0;

        if(!fifo_empty)
            head_meta = meta_fifo[rd_ptr];

    end
    
    // ================================================================
// RETIRING METADATA SNAPSHOT
// ================================================================

always_ff @(posedge clk) begin

    if(reset)

        retire_meta <= '0;

    else if(retire_fire)

        retire_meta <= head_meta;

end
    // ================================================================
    // FIFO MANAGEMENT
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset) begin

            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;

        end

        else begin

            // --------------------------------------------------------
            // PUSH
            // --------------------------------------------------------

            if(
                pipe_accept &&
                !fifo_full
            ) begin

                meta_fifo[wr_ptr].data <=
                    pipe_override
                        ? override_in_data
                        : user_data;

                meta_fifo[wr_ptr].mode <=
                    mode;

                meta_fifo[wr_ptr].enc_dec <=
                    enc_dec;

                meta_fifo[wr_ptr].owner <=
                    pipe_override;

                meta_fifo[wr_ptr].use_encrypt_pipe <=

                    ((mode == MODE_ECB) ||
                     (mode == MODE_CBC))

                        ? !enc_dec
                        : 1'b1;

                wr_ptr <= wr_ptr + 1'b1;

            end

            // --------------------------------------------------------
            // POP
            // --------------------------------------------------------

            if(
                pipe_out_valid &&
                pipe_out_ready &&
                !fifo_empty
            )

                rd_ptr <= rd_ptr + 1'b1;

            // --------------------------------------------------------
            // COUNT
            // --------------------------------------------------------

            unique case({

                pipe_accept &&
                !fifo_full,

                pipe_out_valid &&
                pipe_out_ready &&
                !fifo_empty

            })

                2'b10:
                    count <= count + 1'b1;

                2'b01:
                    count <= count - 1'b1;

                default: ;

            endcase

        end

    end

    // ================================================================
    // FEEDBACK TRACKING
    // ================================================================

    always_ff @(posedge clk) begin

        if(reset)

            feedback <= '0;

        else if(iv_load)

            feedback <= iv_in;

        else begin

            unique case(head_meta.mode)

                // ----------------------------------------------------
                // CBC
                // ----------------------------------------------------

                MODE_CBC: begin

                    // CBC ENCRYPT
                    if(
                        !head_meta.enc_dec &&
                        pipe_out_valid &&
                        pipe_out_ready &&
                        !fifo_empty
                    )

                        feedback <= pipe_out_data;

                    // CBC DECRYPT
                    else if(
                        head_meta.enc_dec &&
                        pipe_accept &&
                        !pipe_override
                    )

                        feedback <= user_data;

                end

                // ----------------------------------------------------
                // CFB
                // ----------------------------------------------------

                MODE_CFB: begin

                    // CFB ENCRYPT
                    if(
                        !head_meta.enc_dec &&
                        pipe_out_valid &&
                        pipe_out_ready &&
                        !fifo_empty
                    )

                        feedback <=
                            pipe_out_data ^
                            head_meta.data;

                    // CFB DECRYPT
                    else if(
                        head_meta.enc_dec &&
                        pipe_accept &&
                        !pipe_override
                    )

                        feedback <= user_data;

                end

                // ----------------------------------------------------
                // OFB
                // ----------------------------------------------------

                MODE_OFB: begin

                    if(
                        pipe_out_valid &&
                        pipe_out_ready &&
                        !fifo_empty
                    )

                        feedback <= pipe_out_data;

                end

                default: ;

            endcase

        end

    end
*/
    // ================================================================
    // SERIALIZATION TRACKING
    // ================================================================
/*
    always_ff @(posedge clk) begin

        if(reset)

            feedback_waiting <= 1'b0;

        else begin

            unique case({

                pipe_accept &&
                !pipe_override &&
                needs_serialization(mode, enc_dec),

                pipe_out_valid &&
                pipe_out_ready &&
                !fifo_empty &&
                (
                    (head_meta.mode == MODE_CBC &&
                     !head_meta.enc_dec) ||

                    (head_meta.mode == MODE_CFB) ||

                    (head_meta.mode == MODE_OFB)
                )

            })

                // ----------------------------------------------------
                // NEW SERIALIZED BLOCK ENTERED
                // ----------------------------------------------------

                2'b10:
                    feedback_waiting <= 1'b1;

                // ----------------------------------------------------
                // SERIALIZED BLOCK COMPLETED
                // ----------------------------------------------------

                2'b01:
                    feedback_waiting <= 1'b0;

                // ----------------------------------------------------
                // ONE LEFT / ONE ENTERED
                // ----------------------------------------------------

                2'b11:
                    feedback_waiting <= 1'b1;

                default: ;

            endcase

        end

    end
    
    // ================================================================
// TEMPORARY DEMO FIX
// Disable serialization stall logic
// ================================================================

always_ff @(posedge clk) begin

    if(reset)

        feedback_waiting <= 1'b0;

    else

        feedback_waiting <= 1'b0;

end

// ================================================================
// SERIALIZED MODE TRACKING
// FINAL FIX
//
// Replaces broken feedback_waiting FSM with true outstanding
// serialized transaction counting.
//
// This fixes:
//   - ECB-only completion
//   - CBC/CFB/OFB deadlock
//   - pipeline serialization race
//   - mode retirement stall
//   - feedback ownership mismatch
//
// ================================================================

// ----------------------------------------------------------------
// REMOVE THIS OLD DECLARATION
// ----------------------------------------------------------------
//
// logic feedback_waiting;
//
// ----------------------------------------------------------------

// ----------------------------------------------------------------
// ADD THIS INSTEAD
// ----------------------------------------------------------------

logic [3:0] serial_count;


// ================================================================
// PIPE INPUT CONTROL
// ================================================================

assign pipe_in_valid =

    !fifo_full &&

    (
        pipe_override
            ? override_in_valid
            : (
                user_valid &&
                (serial_count == 0)
              )
    );

assign pipe_accept =
    pipe_in_valid &&
    pipe_in_ready;

assign pipe_accept_o =
    pipe_accept;

assign user_ready =

    pipe_in_ready &&
    (serial_count == 0) &&
    !pipe_override &&
    !fifo_full;


// ================================================================
// SERIALIZED MODE TRACKING
// ================================================================

always_ff @(posedge clk) begin

    logic push_serial;
    logic pop_serial;

    push_serial =

        pipe_accept &&
        !pipe_override &&
        needs_serialization(mode, enc_dec);

    pop_serial =

        retire_fire &&
        (
            (retire_meta.mode == MODE_CBC &&
             !retire_meta.enc_dec) ||

            (retire_meta.mode == MODE_CFB) ||

            (retire_meta.mode == MODE_OFB)
        );

    if(reset)

        serial_count <= '0;

    else begin

        unique case({push_serial, pop_serial})

            // --------------------------------------------
            // ENTERED ONLY
            // --------------------------------------------

            2'b10:

                serial_count <= serial_count + 1'b1;

            // --------------------------------------------
            // RETIRED ONLY
            // --------------------------------------------

            2'b01:

                serial_count <= serial_count - 1'b1;

            // --------------------------------------------
            // BOTH SAME CYCLE
            // --------------------------------------------

            2'b11:

                serial_count <= serial_count;

            default: ;

        endcase

    end

end
    // ================================================================
    // OUTPUT CONTROL
    // ================================================================

    // ---------------------------------------------------------------
    // FIX:
    // GCM/internal returns MUST obey handshake semantics.
    // ---------------------------------------------------------------

    assign pipe_out_ready =

    user_out_ready ||
    head_meta.owner;

    assign user_out_valid =

        pipe_out_valid &&
        !fifo_empty &&
        !head_meta.owner;

    // ---------------------------------------------------------------
    // FIX:
    // internal_output MUST represent accepted transfer.
    // ---------------------------------------------------------------

    assign internal_output =

        pipe_out_valid &&
        pipe_out_ready &&
        !fifo_empty &&
        head_meta.owner;

    assign ret_use_encrypt =

        fifo_empty
            ? 1'b1
            : head_meta.use_encrypt_pipe;

    assign head_owner_o =

        !fifo_empty &&
        head_meta.owner;

    // ================================================================
    // INPUT PIPE OWNERSHIP
    // ================================================================

    always_comb begin

        pipe_use_encrypt = 1'b1;

        unique case(mode)

            MODE_ECB,
            MODE_CBC:

                pipe_use_encrypt = !enc_dec;

            default:
                pipe_use_encrypt = 1'b1;

        endcase

    end

    // ================================================================
    // OUTPUT POSTPROCESSING
    // ================================================================

    always_comb begin

        user_out_data = pipe_out_data;

        unique case(head_meta.mode)

            // --------------------------------------------------------
            // ECB
            // --------------------------------------------------------

            MODE_ECB:

                user_out_data = pipe_out_data;

            // --------------------------------------------------------
            // CBC
            // --------------------------------------------------------

            MODE_CBC: begin

                // CBC DECRYPT
                if(head_meta.enc_dec)

                    user_out_data =
                        pipe_out_data ^
                        head_meta.data;

                // CBC ENCRYPT
                else

                    user_out_data =
                        pipe_out_data;

            end

            // --------------------------------------------------------
            // STREAM MODES
            // --------------------------------------------------------

            MODE_CFB,
            MODE_OFB,
            MODE_CTR,
            MODE_GCM:

                user_out_data =
                    pipe_out_data ^
                    head_meta.data;

            default:

                user_out_data = pipe_out_data;

        endcase

    end

endmodule */


`timescale 1ns/1ps

import aes_pkg::*;

module aes_mode_datapath #(
    parameter int META_DEPTH = 32
)(
    input  logic        clk,
    input  logic        reset,

    // ============================================================
    // MODE CONTROL
    // ============================================================

    input  aes_mode_e   mode,
    input  logic        enc_dec,

    // ============================================================
    // IV / CTR
    // ============================================================

    input  logic        iv_load,
    input  aes_block_t  iv_in,
    input  aes_block_t  gcm_ctr_in,

    // ============================================================
    // GCM OVERRIDE
    // ============================================================

    input  logic        pipe_override,
    input  logic        override_in_valid,
    input  aes_block_t  override_in_data,

    // ============================================================
    // USER INPUT
    // ============================================================

    input  logic        user_valid,
    output logic        user_ready,
    input  aes_block_t  user_data,

    // ============================================================
    // AES PIPE INPUT
    // ============================================================

    output logic        pipe_in_valid,
    input  logic        pipe_in_ready,
    output aes_block_t  pipe_in_data,

    // ============================================================
    // AES PIPE OUTPUT
    // ============================================================

    input  logic        pipe_out_valid,
    output logic        pipe_out_ready,
    input  aes_block_t  pipe_out_data,

    // ============================================================
    // USER OUTPUT
    // ============================================================

    output logic        user_out_valid,
    input  logic        user_out_ready,
    output aes_block_t  user_out_data,

    // ============================================================
    // INTERNAL RETURN
    // ============================================================

    output logic        internal_output,

    // ============================================================
    // PIPE CONTROL
    // ============================================================

    output logic        pipe_accept_o,
    output logic        pipe_use_encrypt,
    output logic        ret_use_encrypt,
    output logic        head_owner_o
);

    // ============================================================
    // HELPERS
    // ============================================================

    function automatic logic needs_serialization(
        input aes_mode_e m,
        input logic dec
    );

        return (
            ((m == MODE_CBC) && !dec) ||
            (m == MODE_CFB) ||
            (m == MODE_OFB)
        );

    endfunction

    // ============================================================
    // INTERNALS
    // ============================================================

    aes_block_t feedback;
    aes_block_t ctr_reg;

    logic pipe_accept;

    logic fifo_empty;
    logic fifo_full;

    logic [3:0] serial_count;

    // ============================================================
    // METADATA
    // ============================================================

    typedef struct packed {

        aes_block_t data;
        aes_mode_e  mode;
        logic       enc_dec;
        logic       owner;
        logic       use_encrypt_pipe;

    } meta_t;

    meta_t meta_fifo [0:META_DEPTH-1];

    logic [$clog2(META_DEPTH)-1:0] wr_ptr;
    logic [$clog2(META_DEPTH)-1:0] rd_ptr;

    logic [$clog2(META_DEPTH+1)-1:0] count;

    meta_t head_meta;
    meta_t retire_meta;

    logic retire_fire;

    // ============================================================
    // FIFO FLAGS
    // ============================================================

    assign fifo_empty =
        (count == 0);

    assign fifo_full =
        (count == META_DEPTH);

    assign retire_fire =

        pipe_out_valid &&
        pipe_out_ready &&
        !fifo_empty;

    // ============================================================
    // SAFE HEAD METADATA
    // ============================================================

    always_comb begin

        head_meta = '0;

        if(!fifo_empty)
            head_meta = meta_fifo[rd_ptr];

    end

    // ============================================================
    // RETIRE SNAPSHOT
    // ============================================================

    always_ff @(posedge clk) begin

        if(reset)

            retire_meta <= '0;

        else if(retire_fire)

            retire_meta <= head_meta;

    end

    // ============================================================
    // PIPE INPUT CONTROL
    // ============================================================

    assign pipe_in_valid =

        !fifo_full &&

        (
            pipe_override
                ? override_in_valid
                : (
                    user_valid &&
                    (serial_count == 0)
                  )
        );

    assign pipe_accept =

        pipe_in_valid &&
        pipe_in_ready;

    assign pipe_accept_o =
        pipe_accept;

    assign user_ready =

        pipe_in_ready &&
        (serial_count == 0) &&
        !pipe_override &&
        !fifo_full;

    // ============================================================
    // PIPE INPUT DATA
    // ============================================================

    always_comb begin

        pipe_in_data = user_data;

        unique case(mode)

            // ----------------------------------------------------
            // ECB
            // ----------------------------------------------------

            MODE_ECB:

                pipe_in_data = user_data;

            // ----------------------------------------------------
            // CBC
            // ----------------------------------------------------

            MODE_CBC:

                pipe_in_data =

                    enc_dec
                        ? user_data
                        : (user_data ^ feedback);

            // ----------------------------------------------------
            // CFB/OFB
            // ----------------------------------------------------

            MODE_CFB,
            MODE_OFB:

                pipe_in_data = feedback;

            // ----------------------------------------------------
            // CTR
            // ----------------------------------------------------

            MODE_CTR:

                pipe_in_data = ctr_reg;

            // ----------------------------------------------------
            // GCM
            // ----------------------------------------------------

            MODE_GCM:

                pipe_in_data = gcm_ctr_in;

            default:

                pipe_in_data = user_data;

        endcase

        // --------------------------------------------------------
        // OVERRIDE PRIORITY
        // --------------------------------------------------------

        if(pipe_override)

            pipe_in_data = override_in_data;

    end

    // ============================================================
    // CTR REGISTER
    // ============================================================

    always_ff @(posedge clk) begin

        if(reset)

            ctr_reg <= '0;

        else if(iv_load)

            ctr_reg <=

                (mode == MODE_GCM)
                    ? gcm_ctr_in
                    : iv_in;

        else if(
            pipe_accept &&
            !pipe_override &&
            (
                (mode == MODE_CTR) ||
                (mode == MODE_GCM)
            )
        )

            ctr_reg <= ctr_reg + 128'd1;

    end

    // ============================================================
    // FIFO MANAGEMENT
    // ============================================================

    always_ff @(posedge clk) begin

        if(reset) begin

            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;

        end

        else begin

            // ----------------------------------------------------
            // PUSH
            // ----------------------------------------------------

            if(
                pipe_accept &&
                !fifo_full
            ) begin

                meta_fifo[wr_ptr].data <=

                    pipe_override
                        ? override_in_data
                        : user_data;

                meta_fifo[wr_ptr].mode <=
                    mode;

                meta_fifo[wr_ptr].enc_dec <=
                    enc_dec;

                meta_fifo[wr_ptr].owner <=
                    pipe_override;

                meta_fifo[wr_ptr].use_encrypt_pipe <=

                    ((mode == MODE_ECB) ||
                     (mode == MODE_CBC))

                        ? !enc_dec
                        : 1'b1;

                wr_ptr <= wr_ptr + 1'b1;

            end

            // ----------------------------------------------------
            // POP
            // ----------------------------------------------------

            if(retire_fire)

                rd_ptr <= rd_ptr + 1'b1;

            // ----------------------------------------------------
            // COUNT
            // ----------------------------------------------------

            unique case({

                pipe_accept &&
                !fifo_full,

                retire_fire

            })

                2'b10:
                    count <= count + 1'b1;

                2'b01:
                    count <= count - 1'b1;

                default: ;

            endcase

        end

    end

    // ============================================================
    // FEEDBACK TRACKING
    // ============================================================

    always_ff @(posedge clk) begin

        if(reset)

            feedback <= '0;

        else if(iv_load)

            feedback <= iv_in;

        else begin

            unique case(retire_meta.mode)

                // ------------------------------------------------
                // CBC
                // ------------------------------------------------

                MODE_CBC: begin

                    // CBC ENCRYPT
                    if(
                        !retire_meta.enc_dec &&
                        retire_fire
                    )

                        feedback <= pipe_out_data;

                    // CBC DECRYPT
                    else if(
                        retire_meta.enc_dec &&
                        pipe_accept &&
                        !pipe_override
                    )

                        feedback <= user_data;

                end

                // ------------------------------------------------
                // CFB
                // ------------------------------------------------

                MODE_CFB: begin

                    // CFB ENCRYPT
                    if(
                        !retire_meta.enc_dec &&
                        retire_fire
                    )

                        feedback <=
                            pipe_out_data ^
                            retire_meta.data;

                    // CFB DECRYPT
                    else if(
                        retire_meta.enc_dec &&
                        pipe_accept &&
                        !pipe_override
                    )

                        feedback <= user_data;

                end

                // ------------------------------------------------
                // OFB
                // ------------------------------------------------

                MODE_OFB: begin

                    if(retire_fire)

                        feedback <= pipe_out_data;

                end

                default: ;

            endcase

        end

    end

    // ============================================================
    // SERIALIZED MODE TRACKING
    // ============================================================

    always_ff @(posedge clk) begin

        logic push_serial;
        logic pop_serial;

        push_serial =

            pipe_accept &&
            !pipe_override &&
            needs_serialization(mode, enc_dec);

        pop_serial =

            retire_fire &&
            (
                (retire_meta.mode == MODE_CBC &&
                 !retire_meta.enc_dec) ||

                (retire_meta.mode == MODE_CFB) ||

                (retire_meta.mode == MODE_OFB)
            );

        if(reset)

            serial_count <= '0;

        else begin

            unique case({push_serial, pop_serial})

                2'b10:

                    serial_count <=
                        serial_count + 1'b1;

                2'b01:

                    serial_count <=
                        serial_count - 1'b1;

                2'b11:

                    serial_count <=
                        serial_count;

                default: ;

            endcase

        end

    end

    // ============================================================
    // OUTPUT CONTROL
    // ============================================================

    assign pipe_out_ready =

        user_out_ready ||
        head_meta.owner;

    assign user_out_valid =

        pipe_out_valid &&
        !fifo_empty &&
        !head_meta.owner;

    assign internal_output =

        pipe_out_valid &&
        pipe_out_ready &&
        !fifo_empty &&
        head_meta.owner;

    assign ret_use_encrypt =

        fifo_empty
            ? 1'b1
            : head_meta.use_encrypt_pipe;

    assign head_owner_o =

        !fifo_empty &&
        head_meta.owner;

    // ============================================================
    // PIPE OWNERSHIP
    // ============================================================

    always_comb begin

        pipe_use_encrypt = 1'b1;

        unique case(mode)

            MODE_ECB,
            MODE_CBC:

                pipe_use_encrypt = !enc_dec;

            default:

                pipe_use_encrypt = 1'b1;

        endcase

    end

    // ============================================================
    // OUTPUT POSTPROCESSING
    // ============================================================

    always_comb begin

        user_out_data = pipe_out_data;

        unique case(head_meta.mode)

            // ----------------------------------------------------
            // ECB
            // ----------------------------------------------------

            MODE_ECB:

                user_out_data = pipe_out_data;

            // ----------------------------------------------------
            // CBC
            // ----------------------------------------------------

            MODE_CBC: begin

                // CBC DECRYPT
                if(head_meta.enc_dec)

                    user_out_data =
                        pipe_out_data ^
                        head_meta.data;

                // CBC ENCRYPT
                else

                    user_out_data =
                        pipe_out_data;

            end

            // ----------------------------------------------------
            // STREAM MODES
            // ----------------------------------------------------

            MODE_CFB,
            MODE_OFB,
            MODE_CTR,
            MODE_GCM:

                user_out_data =
                    pipe_out_data ^
                    head_meta.data;

            default:

                user_out_data = pipe_out_data;

        endcase

    end

endmodule