// ============================================================================
//  aes_mode_datapath.sv  -  AES Multi-Mode Feedback & Pre/Post-Processing
//
//  Replaces the empty aes_mode_controller.v + partial aes_input_mux.v +
//  feedback_reg_128.v + ctr_reg_128.v with a single clean module.
//
//  Supported modes (aes_mode_e from aes_pkg):
//    ECB: Electronic Codebook
//    CBC: Cipher Block Chaining
//    CFB: Cipher Feedback
//    OFB: Output Feedback
//    CTR: Counter
//
//  Architecture:
//    This module sits between the system boundary and the AES core pipelines.
//    It pre-processes the plaintext/ciphertext going INTO the pipeline and
//    post-processes the output coming OUT of the pipeline.
//
//    The encrypt/decrypt pipelines always process AES blocks; mode handling
//    is purely in XOR pre/post and IV/counter state management.
//
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │  MODE      │  ENC input to AES  │  ENC output    │  DEC input       │
//  ├────────────┼────────────────────┼────────────────┼──────────────────┤
//  │  ECB       │  plaintext         │  ciphertext    │  ciphertext      │
//  │  CBC       │  PT ^ IV/prev_CT   │  ciphertext    │  ciphertext      │
//  │  CFB       │  IV/prev_CT        │  AES_out ^ PT  │  IV/prev_CT      │
//  │  OFB       │  IV/prev_AES_out   │  AES_out ^ PT  │  IV/prev_AES_out │
//  │  CTR       │  counter           │  AES_out ^ PT  │  counter         │
//  └──────────────────────────────────────────────────────────────────────┘
//
//  Pipeline note:
//    The AES encrypt/decrypt pipelines have 11/10 cycle latency. For feedback
//    modes (CBC, CFB, OFB), the feedback value must be updated only AFTER the
//    AES output is available. This means feedback modes are serialized: you
//    cannot start block N+1 until block N's AES output is available.
//    For ECB and CTR, blocks can be pipelined freely.
//
//  This module manages:
//    - IV register (loaded on iv_load pulse)
//    - Feedback register (updated from AES output when out_valid fires)
//    - Counter register (loaded on iv_load, incremented on each accepted input)
//    - Input pre-processing mux (what goes into the AES pipeline)
//    - Output post-processing XOR (for CFB/OFB/CTR)
//    - Serialization gate for feedback modes
// ============================================================================
`timescale 1ns/1ps

import aes_pkg::*;

module aes_mode_datapath (
    input  logic        clk,
    input  logic        reset,

    // ---- Configuration ----
    input  aes_mode_e   mode,
    input  logic        enc_dec,      // 0=encrypt, 1=decrypt

    // ---- IV / Counter load ----
    input  logic        iv_load,      // pulse: load iv_in into IV + counter
    input  aes_block_t  iv_in,

    // ---- Input from user (plaintext for enc, ciphertext for dec) ----
    input  logic        user_valid,
    output logic        user_ready,
    input  aes_block_t  user_data,

    // ---- Output to AES pipeline ----
    output logic        pipe_in_valid,
    input  logic        pipe_in_ready,
    output aes_block_t  pipe_in_data,

    // ---- Input from AES pipeline (raw AES block output) ----
    input  logic        pipe_out_valid,
    output logic        pipe_out_ready,
    input  aes_block_t  pipe_out_data,

    // ---- Output to user (ciphertext for enc, plaintext for dec) ----
    output logic        user_out_valid,
    input  logic        user_out_ready,
    output aes_block_t  user_out_data
);

    // -----------------------------------------------------------------------
    //  IV, feedback, and counter registers
    // -----------------------------------------------------------------------
    aes_block_t  iv_reg;        // stored IV
    aes_block_t  feedback;      // CBC: prev ciphertext; CFB/OFB: prev AES out
    aes_block_t  counter;       // CTR mode counter

    // Block accepted by pipeline this cycle
    logic        pipe_accept;
    assign pipe_accept = pipe_in_valid && pipe_in_ready;

    // Output accepted by user this cycle
    logic        out_accept;
    assign out_accept = pipe_out_valid && user_out_ready;

    // -----------------------------------------------------------------------
    //  IV register
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset)
            iv_reg <= '0;
        else if (iv_load)
            iv_reg <= iv_in;
    end

    // -----------------------------------------------------------------------
    //  Counter register (CTR mode)
    //  Loaded from iv_in on iv_load, incremented each time a block is
    //  accepted into the pipeline.
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset)
            counter <= '0;
        else if (iv_load)
            counter <= iv_in;
        else if (pipe_accept && (mode == MODE_CTR))
            counter <= counter + 128'd1;
    end

    // -----------------------------------------------------------------------
    //  Feedback register
    //  CBC enc:  updated to ciphertext (AES output) after each output
    //  CBC dec:  updated to ciphertext (user INPUT) after each input
    //  CFB/OFB:  updated to AES output after each output
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset)
            feedback <= '0;
        else if (iv_load)
            feedback <= iv_in;
        else begin
            case (mode)
                MODE_CBC: begin
                    if (enc_dec == 1'b0) begin
                        // Encrypt: feedback = ciphertext = AES output
                        if (out_accept)
                            feedback <= pipe_out_data;
                    end else begin
                        // Decrypt: feedback = ciphertext = user input
                        if (pipe_accept)
                            feedback <= user_data;
                    end
                end
                MODE_CFB: begin
                    // Both enc/dec: feedback = AES output (CFB uses encrypt
                    // pipeline direction always)
                    if (out_accept)
                        feedback <= pipe_out_data;
                end
                MODE_OFB: begin
                    // Both enc/dec: feedback = AES output
                    if (out_accept)
                        feedback <= pipe_out_data;
                end
                default: ; // ECB, CTR: no feedback
            endcase
        end
    end

    // -----------------------------------------------------------------------
    //  Serialization gate for feedback modes
    //  In CBC/CFB/OFB, block N+1 cannot enter the pipeline until block N
    //  has produced its output (feedback register updated). This serializes
    //  the throughput to 1 block per pipeline-latency cycles.
    //  ECB and CTR are not gated - full pipeline utilization.
    //
    //  Implementation: a simple "waiting" flag.
    //    - Set when a block is accepted into the pipeline (pipe_accept)
    //    - Cleared when the corresponding output is accepted (out_accept)
    //    For ECB/CTR: waiting is never set, so pipeline runs freely.
    // -----------------------------------------------------------------------
    logic feedback_waiting;

    always_ff @(posedge clk) begin
        if (reset)
            feedback_waiting <= 1'b0;
        else begin
            if (out_accept && feedback_waiting)
                feedback_waiting <= 1'b0;
            else if (pipe_accept && is_feedback_mode(mode))
                feedback_waiting <= 1'b1;
        end
    end

    function automatic logic is_feedback_mode(input aes_mode_e m);
        return (m == MODE_CBC) || (m == MODE_CFB) || (m == MODE_OFB);
    endfunction

    // -----------------------------------------------------------------------
    //  Input pre-processing mux
    //  Selects what block the AES pipeline actually encrypts/decrypts.
    // -----------------------------------------------------------------------
    aes_block_t  aes_pipe_input;

    always_comb begin
        case (mode)
            MODE_ECB: aes_pipe_input = user_data;
            MODE_CBC: begin
                if (enc_dec == 1'b0)
                    aes_pipe_input = user_data ^ feedback;  // PT ^ IV/prev_CT
                else
                    aes_pipe_input = user_data;             // CT passed directly
            end
            MODE_CFB: aes_pipe_input = feedback;    // always encrypt feedback
            MODE_OFB: aes_pipe_input = feedback;    // always encrypt feedback
            MODE_CTR: aes_pipe_input = counter;     // always encrypt counter
            default:  aes_pipe_input = user_data;
        endcase
    end

    // -----------------------------------------------------------------------
    //  Output post-processing
    //  For CFB/OFB/CTR: XOR AES output with user data to get final output.
    //  For ECB/CBC enc: AES output IS the ciphertext.
    //  For CBC dec:     AES output ^ feedback = plaintext.
    // -----------------------------------------------------------------------
    // We need the user_data that MATCHES this pipeline output.
    // Since the pipeline is serialized in feedback modes, a simple register
    // capturing user_data at pipe_accept is sufficient.
    aes_block_t  input_capture;  // user_data captured when block entered pipe
    always_ff @(posedge clk) begin
        if (pipe_accept)
            input_capture <= user_data;
    end

    always_comb begin
        case (mode)
            MODE_ECB: user_out_data = pipe_out_data;
            MODE_CBC: begin
                if (enc_dec == 1'b0)
                    user_out_data = pipe_out_data;          // ciphertext
                else
                    user_out_data = pipe_out_data ^ feedback; // plaintext
            end
            MODE_CFB: user_out_data = pipe_out_data ^ input_capture;
            MODE_OFB: user_out_data = pipe_out_data ^ input_capture;
            MODE_CTR: user_out_data = pipe_out_data ^ input_capture;
            default:  user_out_data = pipe_out_data;
        endcase
    end

    // -----------------------------------------------------------------------
    //  Handshake routing
    // -----------------------------------------------------------------------
    // User can push data when: pipeline ready AND not waiting for feedback
    assign user_ready    = pipe_in_ready && !(feedback_waiting && is_feedback_mode(mode));
    assign pipe_in_valid = user_valid    && !(feedback_waiting && is_feedback_mode(mode));
    assign pipe_in_data  = aes_pipe_input;

    // Output side: direct pass-through handshake
    assign user_out_valid = pipe_out_valid;
    assign pipe_out_ready = user_out_ready;

endmodule : aes_mode_datapath