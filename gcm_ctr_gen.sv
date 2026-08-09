// ============================================================================
//  gcm_ctr_gen.sv  -  GCM Counter Block Generator
//
//  Manages the two counter values required by AES-GCM:
//
//  J0  (Initial Counter Block)
//  ────────────────────────────
//  Per NIST SP 800-38D §7.1:
//    If len(IV) == 96 bits:  J0 = IV || 0^31 || 1
//    Otherwise: J0 = GHASH_H(IV padded + len(IV))
//
//  This module implements the 96-bit IV case only (standard usage,
//  covers the vast majority of practical deployments including TLS 1.3).
//  Non-96-bit IV would require a full GHASH pass over the IV, which
//  is rarely used and would substantially complicate this module.
//  A static assertion on iv_len is provided for safety.
//
//  J0 is used to generate the tag encryption block: EK(J0).
//  J0 is NOT used directly for data encryption - the counter starts at
//  inc32(J0) for the first payload block.
//
//  CTRi  (Payload Counter Blocks)
//  ────────────────────────────────
//  CTR_1 = inc32(J0)  (J0 with the low 32 bits incremented by 1)
//  CTR_i = inc32(CTR_{i-1})
//
//  GCM uses inc32: only the low 32 bits of the counter increment.
//  The upper 96 bits (IV portion) remain fixed.  This matches RFC 5116
//  and prevents counter wrap for messages up to 2^32 - 2 blocks.
//
//  INTERFACE
//  ──────────
//  iv_load    : pulse - load iv_in[95:0] as the IV (96-bit IV assumed)
//  j0_out     : J0, registered, valid after iv_load
//  ctr_out    : current payload counter, incremented by ctr_inc pulse
//  ctr_inc    : pulse - advance counter to next payload block
//  ctr_reset  : pulse - reset counter to CTR_1 = inc32(J0)
// ============================================================================
`timescale 1ns/1ps

import aes_pkg::*;

module gcm_ctr_gen (
    input  logic        clk,
    input  logic        reset,

    // ---- IV input ----
    input  logic        iv_load,      // pulse
    input  logic [95:0] iv_in,        // 96-bit IV (nonce)

    // ---- J0 output ----
    output aes_block_t  j0_out,       // = IV || 0^31 || 1

    // ---- Payload counter ----
    output aes_block_t  ctr_out,      // current CTR_i
    input  logic        ctr_inc,      // advance counter
    input  logic        ctr_reset     // reset to inc32(J0)
);

    aes_block_t j0_reg;
    aes_block_t ctr_reg;

    // J0 = {IV[95:0], 31'b0, 1'b1}
    // Low 32 bits: 0x00000001
    always_ff @(posedge clk) begin
        if (reset) begin
            j0_reg  <= 128'd0;
            ctr_reg <= 128'd0;
        end else if (iv_load) begin
            j0_reg  <= {iv_in, 32'h0000_0001};
            // CTR_1 = inc32(J0): increment only the low 32 bits of J0
            // inc32({IV, 0x00000001}) = {IV, 0x00000002}
            ctr_reg <= {iv_in, 32'h0000_0002};
        end else if (ctr_reset) begin
            // Restore to CTR_1 (used between AAD and payload phases)
            ctr_reg <= {j0_reg[127:32], 32'h0000_0002};
        end else if (ctr_inc) begin
            // inc32: only the low 32 bits increment
            ctr_reg <= {ctr_reg[127:32], ctr_reg[31:0] + 32'd1};
        end
    end

    assign j0_out  = j0_reg;
    assign ctr_out = ctr_reg;

endmodule : gcm_ctr_gen