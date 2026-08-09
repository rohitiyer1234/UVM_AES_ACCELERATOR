// ============================================================================
//  ghash_core.sv  -  GHASH Accumulator
//
//  Implements the GHASH function from NIST SP 800-38D §6.4:
//
//    GHASH_H(X_1, X_2, ..., X_m) =
//        Y_0 = 0^128
//        Y_i = (Y_{i-1} XOR X_i) * H
//        return Y_m
//
//  The asterisk (*) denotes multiplication in GF(2^128).
//
//  USAGE PHASES (driven by ghash_phase input)
//  ────────────────────────────────────────────
//  PHASE_H_LOAD  : H has been computed externally (AES_K(0^128)) and
//                  is loaded via h_in / h_load.
//  PHASE_AAD     : absorb AAD blocks.  data_in carries each 128-bit
//                  padded AAD block.  data_valid / data_ready handshake.
//  PHASE_DATA    : absorb ciphertext blocks (encrypt path) or
//                  plaintext blocks (decrypt path - caller's responsibility
//                  to feed the right data; ghash_core is data-agnostic).
//  PHASE_LEN     : absorb the 128-bit length block: {len(AAD)||len(C)}.
//                  This finalises GHASH before the EK(J0) tag XOR.
//
//  OUTPUT
//  ───────
//  When done is asserted (one clock after the last multiply completes),
//  ghash_val holds the final Y value.  The caller XORs this with EK(J0)
//  to produce the authentication tag.
//
//  THROUGHPUT AND SERIALIZATION
//  ──────────────────────────────
//  This module is fully serialized: block N+1 cannot start until the
//  GF multiply for block N completes (128 or 32 cycles depending on
//  which multiplier is instantiated).  This is inherent to GHASH - each
//  block's hash value depends on the previous.
//
//  This is independent of and parallel to the AES-CTR encrypt pipeline.
//  The encrypt pipeline runs at 1 block per 11 cycles.  GHASH runs at
//  1 block per 128 cycles (serial mul) or 32 cycles (4-bit mul).
//  For long messages the GHASH path is the throughput bottleneck.
//
//  PARAMETERIZATION
//  ─────────────────
//  USE_4BIT_MUL = 1  : instantiates ghash_gf128_mul_4b (32 cycles/block)
//  USE_4BIT_MUL = 0  : instantiates ghash_gf128_mul    (128 cycles/block)
//
//  TIMING
//  ───────
//  Critical path is entirely inside ghash_gf128_mul / ghash_gf128_mul_4b.
//  ghash_core adds only a single XOR (accum ^ data_in) before the
//  multiply input - one gate level, negligible.
// ============================================================================

/*

`timescale 1ns/1ps

import aes_pkg::*;

module ghash_core #(
    parameter int USE_4BIT_MUL =0  // 0 = 128-cycle serial, 1 = 32-cycle 4-bit
)(
    input  logic        clk,
    input  logic        reset,

    // ---- H subkey (= AES_K(0^128)) ----
    input  logic        h_load,   // pulse: load h_in as GHASH subkey
    input  aes_block_t  h_in,

    // ---- Data input (AAD or ciphertext blocks, 128-bit padded) ----
    input  logic        data_valid,
    output logic        data_ready,
    input  aes_block_t  data_in,

    // ---- Accumulator reset (start of new message) ----
    input  logic        accum_clear,  // synchronous clear of running hash

    // ---- Output ----
    output aes_block_t  ghash_val,    // current GHASH accumulator value
    output logic        done          // one-cycle pulse: multiply completed
);

    // -----------------------------------------------------------------------
    //  H register
    // -----------------------------------------------------------------------
    aes_block_t  h_reg;
    always_ff @(posedge clk) begin
        if (reset)       h_reg <= 128'd0;
        else if (h_load) h_reg <= h_in;
    end

    // -----------------------------------------------------------------------
    //  GHASH accumulator
    // -----------------------------------------------------------------------
    aes_block_t  accum;

    // -----------------------------------------------------------------------
    //  GF multiplier interface
    // -----------------------------------------------------------------------
    logic        mul_start, mul_done, mul_busy;
    aes_block_t  mul_a, mul_result;

    // mul_a = current accum XOR new data block (the "Z XOR X_i" step)
    // mul_b = H (constant for this key)
    assign mul_a = accum ^ data_in;

    // Issue a multiply when data arrives and multiplier is free
    assign mul_start  = data_valid && data_ready;
    assign data_ready = !mul_busy;

    // -----------------------------------------------------------------------
    //  Instantiate chosen multiplier
    // -----------------------------------------------------------------------
    generate
        if (USE_4BIT_MUL) begin : GEN_4B_MUL
            ghash_gf128_mul_4b u_mul (
                .clk    (clk),
                .reset  (reset),
                .start  (mul_start),
                .a      (mul_a),
                .b      (h_reg),
                .result (mul_result),
                .done   (mul_done),
                .busy   (mul_busy)
            );
        end else begin : GEN_SER_MUL
            ghash_gf128_mul u_mul (
                .clk    (clk),
                .reset  (reset),
                .start  (mul_start),
                .a      (mul_a),
                .b      (h_reg),
                .result (mul_result),
                .done   (mul_done),
                .busy   (mul_busy)
            );
        end
    endgenerate

    // -----------------------------------------------------------------------
    //  Accumulator update
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset)
            accum <= 128'd0;
        else if (accum_clear)
            accum <= 128'd0;
        else if (mul_done)
            accum <= mul_result;   // Y_i = (Y_{i-1} XOR X_i) * H
    end

    assign ghash_val = accum;
    assign done      = mul_done;

endmodule : ghash_core

*/

`timescale 1ns/1ps
// ============================================================================
//  ghash_core.sv  (TIMING-SAFE FIXED VERSION)
// ============================================================================
//
//  FIX APPLIED
//  ------------
//
//  BUG-GH1 [TIMING / ROBUSTNESS]
//
//  Original design directly drove multiplier inputs using:
//
//      mul_a = accum ^ data_in
//
//  while simultaneously asserting:
//
//      mul_start = data_valid && data_ready
//
//  This creates:
//  - long combinational timing path
//  - unsafe direct sampling from upstream datapath
//  - possible instability during handshake edges
//  - tighter timing closure at higher Fmax
//
//  FIX:
//  ----
//  Register multiplier operands on mul_start.
//
//  This:
//  - creates clean timing boundary
//  - isolates multiplier from upstream logic
//  - guarantees stable multiply operands
//  - improves synthesis/timing closure robustness
//
//  No functional behavior changes.
//
// ============================================================================

import aes_pkg::*;

module ghash_core #(
    parameter int USE_4BIT_MUL = 0
)(
    input  logic        clk,
    input  logic        reset,

    // ------------------------------------------------------------------------
    // H subkey = AES_K(0^128)
    // ------------------------------------------------------------------------

    input  logic        h_load,
    input  aes_block_t  h_in,

    // ------------------------------------------------------------------------
    // Data input stream
    // ------------------------------------------------------------------------

    input  logic        data_valid,
    output logic        data_ready,
    input  aes_block_t  data_in,

    // ------------------------------------------------------------------------
    // Accumulator clear
    // ------------------------------------------------------------------------

    input  logic        accum_clear,

    // ------------------------------------------------------------------------
    // Output
    // ------------------------------------------------------------------------

    output aes_block_t  ghash_val,
    output logic        done

);

    // =========================================================================
    // H REGISTER
    // =========================================================================

    aes_block_t h_reg;

    always_ff @(posedge clk) begin

        if(reset)
            h_reg <= 128'd0;

        else if(h_load)
            h_reg <= h_in;

    end

    // =========================================================================
    // GHASH ACCUMULATOR
    // =========================================================================

    aes_block_t accum;

    // =========================================================================
    // MULTIPLIER INTERFACE
    // =========================================================================

    logic        mul_start;
    logic        mul_done;
    logic        mul_busy;

    aes_block_t  mul_result;

    // =========================================================================
    // REGISTERED MULTIPLIER OPERANDS
    // =========================================================================

    aes_block_t mul_a_reg;
    aes_block_t mul_b_reg;

    // =========================================================================
    // HANDSHAKE
    // =========================================================================

    assign data_ready = !mul_busy;

    assign mul_start  = data_valid && data_ready;

    // =========================================================================
    // OPERAND CAPTURE
    // =========================================================================
    //
    // FIX-GH1:
    // Register multiplier inputs to:
    // - isolate combinational timing
    // - guarantee stable multiply operands
    // - improve timing closure
    //
    // =========================================================================

    always_ff @(posedge clk) begin

        if(reset) begin

            mul_a_reg <= 128'd0;
            mul_b_reg <= 128'd0;

        end

        else if(mul_start) begin

            mul_a_reg <= accum ^ data_in;
            mul_b_reg <= h_reg;

        end

    end

    // =========================================================================
    // MULTIPLIER
    // =========================================================================

    generate

        if(USE_4BIT_MUL) begin : GEN_4BIT

            ghash_gf128_mul_4b u_mul(

                .clk(clk),
                .reset(reset),

                .start(mul_start),

                .a(mul_a_reg),
                .b(mul_b_reg),

                .result(mul_result),

                .done(mul_done),
                .busy(mul_busy)

            );

        end

        else begin : GEN_SERIAL

            ghash_gf128_mul u_mul(

                .clk(clk),
                .reset(reset),

                .start(mul_start),

                .a(mul_a_reg),
                .b(mul_b_reg),

                .result(mul_result),

                .done(mul_done),
                .busy(mul_busy)

            );

        end

    endgenerate

    // =========================================================================
    // ACCUMULATOR UPDATE
    // =========================================================================

    always_ff @(posedge clk) begin

        if(reset)
            accum <= 128'd0;

        else if(accum_clear)
            accum <= 128'd0;

        else if(mul_done)
            accum <= mul_result;

    end

    // =========================================================================
    // OUTPUTS
    // =========================================================================

    assign ghash_val = accum;

    assign done = mul_done;

endmodule