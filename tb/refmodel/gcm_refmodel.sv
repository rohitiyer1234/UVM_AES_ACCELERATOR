// ============================================================================
//  tb/refmodel/gcm_refmodel.sv
//
//  Pure-SV AES-GCM-128 reference model per NIST SP 800-38D.  Computes:
//      - the CTR keystream (starting at inc32(J0))
//      - ciphertext = PT XOR keystream
//      - GHASH over AAD || pad || CT || pad || length-block
//      - tag = GHASH XOR E_K(J0)
//
//  Functions:
//      gcm_refmodel::ctr_encrypt(key, iv96, pt[], out ct[])
//      gcm_refmodel::compute_tag(key, iv96, aad[], ct[], out tag)
// ============================================================================
`ifndef GCM_REFMODEL_SV
`define GCM_REFMODEL_SV

package gcm_refmodel;

    import aes_pkg::*;
    import aes_refmodel::*;

    // -----------------------------------------------------------------
    // inc32: increment the low 32 bits, leave upper 96 untouched.
    // -----------------------------------------------------------------
    function automatic aes_block_t inc32(input aes_block_t v);
        return { v[127:32], v[31:0] + 32'd1 };
    endfunction

    // -----------------------------------------------------------------
    // GF(2^128) multiply with NIST polynomial p(x) = x^128 + x^7 + x^2 + x + 1.
    // Bit reflection convention: in NIST GCM, the LSB of the byte stream is
    // the highest-degree term of the polynomial.  This routine follows the
    // "right-shift" form used by the DUT's GHASH multiplier.
    // -----------------------------------------------------------------
    function automatic aes_block_t gf128_mul(input aes_block_t a,
                                             input aes_block_t b);
        aes_block_t z, v;
        z = '0;
        v = a;
        for (int i = 127; i >= 0; i--) begin
            // process b MSB-first: b[i] selects whether to accumulate v
            if (b[i]) z = z ^ v;
            // v = v * x in GF(2^128) per NIST: if LSB of v is 1, shift then
            // XOR with the reduction constant 0xE100..00; else just shift.
            if (v[0]) v = (v >> 1) ^ 128'hE100_0000_0000_0000_0000_0000_0000_0000;
            else       v =  v >> 1;
        end
        return z;
    endfunction

    // -----------------------------------------------------------------
    // GHASH over the byte stream X1..Xm (each 128 bits).
    // -----------------------------------------------------------------
    function automatic aes_block_t ghash(input aes_block_t  h,
                                         input aes_block_t  blocks []);
        aes_block_t y;
        y = '0;
        for (int i = 0; i < blocks.size(); i++) begin
            y = gf128_mul(y ^ blocks[i], h);
        end
        return y;
    endfunction

    // -----------------------------------------------------------------
    // CTR-mode encryption (or decryption - symmetric).
    // Starts at inc32(J0) where J0 = iv96 || 0^31 || 1.
    // -----------------------------------------------------------------
    function automatic void ctr_encrypt(input  logic [95:0]  iv96,
                                        input  aes_block_t   key,
                                        input  aes_block_t   pt [],
                                        output aes_block_t   ct []);
        rk_array_t  rk;
        aes_block_t ctr;
        aes_block_t ks;
        ct = new[pt.size()];
        expand_key(key, rk);
        ctr = { iv96, 32'h0000_0002 };  // inc32(J0)
        for (int i = 0; i < pt.size(); i++) begin
            ks    = enc_block(ctr, rk);
            ct[i] = pt[i] ^ ks;
            ctr   = inc32(ctr);
        end
    endfunction

    // -----------------------------------------------------------------
    // Compute the final GCM authentication tag.
    //
    // The DUT's RTL drives the orchestrator with length counters in bits
    // tracked from the AAD and PAYLOAD handshakes.  The length block fed
    // to GHASH is { aad_bits, payload_bits } big-endian.
    // -----------------------------------------------------------------
    function automatic aes_block_t compute_tag(input logic [95:0] iv96,
                                               input aes_block_t  key,
                                               input aes_block_t  aad [],
                                               input aes_block_t  ct  []);
        rk_array_t  rk;
        aes_block_t h;
        aes_block_t j0_enc;
        aes_block_t y;
        aes_block_t blocks [];
        int unsigned k = 0;
        int unsigned n = aad.size() + ct.size() + 1;
        expand_key(key, rk);

        // H = AES_K(0^128)
        h = enc_block(128'd0, rk);

        // EK(J0)
        j0_enc = enc_block({ iv96, 32'h0000_0001 }, rk);

        // Concatenate AAD || CT || lenblock
        blocks = new[n];
        for (int i = 0; i < aad.size(); i++) blocks[k++] = aad[i];
        for (int i = 0; i < ct.size();  i++) blocks[k++] = ct[i];
        blocks[k] = { 64'(aad.size() * 128), 64'(ct.size() * 128) };

        y = ghash(h, blocks);
        return y ^ j0_enc;
    endfunction

endpackage : gcm_refmodel

`endif
