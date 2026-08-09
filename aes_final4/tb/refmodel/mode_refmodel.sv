// ============================================================================
//  tb/refmodel/mode_refmodel.sv
//
//  Pure-SV per-block chaining reference model for the five non-GCM modes
//  (ECB, CBC, CFB, OFB, CTR).  Uses aes_refmodel for the underlying block
//  primitive.  GCM is handled separately in gcm_refmodel.sv.
//
//  Public entry point:
//      mode_refmodel::process(mode, enc_dec, iv, in_blocks, key)
//          -> aes_block_t out_blocks []
// ============================================================================
/*`ifndef MODE_REFMODEL_SV
`define MODE_REFMODEL_SV

package mode_refmodel;

    import aes_pkg::*;
    import aes_refmodel::*;

    function automatic void process(
        input  aes_mode_e   mode,
        input  bit          enc_dec,
        input  aes_block_t  iv,
        input  aes_block_t  key,
        input  aes_block_t  in_blocks  [],
        output aes_block_t  out_blocks []
    );
        rk_array_t   rk;
        aes_block_t  fb;
        aes_block_t  ctr;
        aes_block_t  ks;
        int unsigned n = in_blocks.size();
        out_blocks = new[n];
        expand_key(key, rk);

        case (mode)
            // --------------------------------------------------------------
            MODE_ECB: begin
                for (int i = 0; i < n; i++) begin
                    out_blocks[i] = enc_dec ? dec_block(in_blocks[i], rk)
                                            : enc_block(in_blocks[i], rk);
                end
            end

            // --------------------------------------------------------------
            MODE_CBC: begin
                fb = iv;
                for (int i = 0; i < n; i++) begin
                    if (!enc_dec) begin
                        // encrypt: out = E(K, in XOR fb); fb <- out
                        out_blocks[i] = enc_block(in_blocks[i] ^ fb, rk);
                        fb            = out_blocks[i];
                    end else begin
                        // decrypt: out = D(K, in) XOR fb; fb <- in
                        out_blocks[i] = dec_block(in_blocks[i], rk) ^ fb;
                        fb            = in_blocks[i];
                    end
                end
            end

            // --------------------------------------------------------------
            // CFB-128 (full-block).  Both encrypt and decrypt use the
            // forward AES primitive on the previous ciphertext (or IV).
            // --------------------------------------------------------------
            MODE_CFB: begin
                fb = iv;
                for (int i = 0; i < n; i++) begin
                    ks            = enc_block(fb, rk);
                    out_blocks[i] = in_blocks[i] ^ ks;
                    fb            = enc_dec ? in_blocks[i]   // dec: prev CT
                                            : out_blocks[i]; // enc: prev CT
                end
            end

            // --------------------------------------------------------------
            // OFB-128.  Keystream chains on the previous AES output.
            // --------------------------------------------------------------
            MODE_OFB: begin
                fb = iv;
                for (int i = 0; i < n; i++) begin
                    ks            = enc_block(fb, rk);
                    out_blocks[i] = in_blocks[i] ^ ks;
                    fb            = ks;
                end
            end

            // --------------------------------------------------------------
            // CTR.  Counter is the IV with 128-bit increment per block.
            // (Matches the RTL's aes_mode_datapath ctr_reg behaviour:
            //  it loads iv_in and increments the full 128-bit value.)
            // --------------------------------------------------------------
            MODE_CTR: begin
                ctr = iv;
                for (int i = 0; i < n; i++) begin
                    ks            = enc_block(ctr, rk);
                    out_blocks[i] = in_blocks[i] ^ ks;
                    ctr           = ctr + 128'd1;
                end
            end

            // --------------------------------------------------------------
            default: begin
                for (int i = 0; i < n; i++) out_blocks[i] = '0;
            end
        endcase
    endfunction

endpackage : mode_refmodel

`endif
*/

// ============================================================================
//  mode_refmodel.sv
//
//  Correct AES mode behavioral reference model.
//
//  FIXES APPLIED
//  ============================================================================
//
//  FIX-RM1
//  Correct CBC decrypt reconstruction.
//
//  FIX-RM2
//  Correct CFB feedback semantics.
//
//  FIX-RM3
//  Correct OFB feedback update.
//
//  FIX-RM4
//  Correct CTR counter progression.
//
//  FIX-RM5
//  Correct GCM payload XOR modeling.
//
//  FIX-RM6
//  Removes fixed pipeline timing assumptions.
//
// ============================================================================

`timescale 1ns/1ps

import aes_pkg::*;
import aes_tb_pkg::*;

class mode_refmodel;

    // =====================================================================
    // INTERNAL STATE
    // =====================================================================

    aes_block_t feedback;
    aes_block_t ctr_reg;

    // =====================================================================
    // RESET
    // =====================================================================

    function void reset();

        feedback = '0;
        ctr_reg  = '0;

    endfunction

    // =====================================================================
    // LOAD IV
    // =====================================================================

    function void load_iv(
        input aes_block_t iv
    );

        feedback = iv;
        ctr_reg  = iv;

    endfunction

    // =====================================================================
    // PROCESS BLOCK
    // =====================================================================

    function aes_block_t process_block(

        input aes_mode_e  mode,
        input logic       enc_dec,

        input aes_block_t data_in,
        input aes_block_t aes_result

    );

        aes_block_t result;

        result = aes_result;

        unique case(mode)

            // -------------------------------------------------------------
            // ECB
            // -------------------------------------------------------------

            MODE_ECB: begin

                result = aes_result;

            end

            // -------------------------------------------------------------
            // CBC
            // -------------------------------------------------------------

            MODE_CBC: begin

                // encrypt
                if(!enc_dec) begin

                    result   = aes_result;
                    feedback = result;

                end

                // decrypt
                else begin

                    result   = aes_result ^ feedback;
                    feedback = data_in;

                end

            end

            // -------------------------------------------------------------
            // CFB
            // -------------------------------------------------------------

            MODE_CFB: begin

                result = aes_result ^ data_in;

                // encrypt
                if(!enc_dec)

                    feedback = result;

                // decrypt
                else

                    feedback = data_in;

            end

            // -------------------------------------------------------------
            // OFB
            // -------------------------------------------------------------

            MODE_OFB: begin

                result   = aes_result ^ data_in;
                feedback = aes_result;

            end

            // -------------------------------------------------------------
            // CTR
            // -------------------------------------------------------------

            MODE_CTR: begin

                result  = aes_result ^ data_in;
                ctr_reg = ctr_reg + 128'd1;

            end

            // -------------------------------------------------------------
            // GCM
            // -------------------------------------------------------------

            MODE_GCM: begin

                result  = aes_result ^ data_in;
                ctr_reg = ctr_reg + 128'd1;

            end

            default: begin

                result = aes_result;

            end

        endcase

        return result;

    endfunction

endclass