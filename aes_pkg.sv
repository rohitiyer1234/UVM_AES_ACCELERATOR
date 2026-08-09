// ============================================================================
//  aes_pkg.sv  -  AES-128 Package  (GCM Extension)
//
//  CHANGES FROM PREVIOUS VERSION
//  ──────────────────────────────
//  1. Added MODE_GCM = 3'd5  to aes_mode_e
//  2. Added GCM_TAG_BITS / GCM_TAG_BYTES constants
//  3. Added gcm_phase_e: FSM phase encoding used by aes_top and GCM controller
//  4. All original definitions preserved verbatim.
//
//  WHY GCM GETS ITS OWN PHASE ENUM
//  ────────────────────────────────
//  GCM is fundamentally a multi-phase protocol:
//    PHASE_GHASH_H   : generate H = AES_K(0^128)
//    PHASE_AAD       : absorb Additional Authenticated Data into GHASH
//    PHASE_PAYLOAD   : CTR encrypt + GHASH authentication in parallel
//    PHASE_TAG       : compute final tag = GHASH_result XOR AES_K(J0)
//  Encoding this as an enum keeps the FSM in aes_top clean and avoids
//  ad-hoc bit-fields.
// ============================================================================
`timescale 1ns/1ps

package aes_pkg;

    // -----------------------------------------------------------------------
    //  Core parameters  (unchanged)
    // -----------------------------------------------------------------------
    localparam int NUM_ROUNDS     = 10;
    localparam int PIPE_DEPTH     = NUM_ROUNDS + 1;
    localparam int NUM_BANKS      = 2;
    localparam int KEY_FIFO_DEPTH = 4;

    // GCM tag is always 128 bits per NIST SP 800-38D
    localparam int GCM_TAG_BITS  = 128;
    localparam int GCM_TAG_BYTES = 16;

    // -----------------------------------------------------------------------
    //  Type aliases  (unchanged)
    // -----------------------------------------------------------------------
    typedef logic [127:0] aes_block_t;
    typedef logic  [31:0] aes_word_t;
    typedef logic   [7:0] aes_byte_t;

    typedef aes_block_t rk_bank_t  [0:NUM_ROUNDS];
    typedef rk_bank_t   rk_store_t [0:NUM_BANKS-1];

    // -----------------------------------------------------------------------
    //  AES mode encoding
    //  3-bit field; 6 defined values, 2 reserved.
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {
        MODE_ECB = 3'd0,
        MODE_CBC = 3'd1,
        MODE_CFB = 3'd2,
        MODE_OFB = 3'd3,
        MODE_CTR = 3'd4,
        MODE_GCM = 3'd5   // NEW: Galois/Counter Mode
    } aes_mode_e;

    // -----------------------------------------------------------------------
    //  GCM FSM phase  (used in aes_top GCM controller)
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {
        GCM_IDLE     = 3'd0,   // waiting for start
        GCM_H_GEN    = 3'd1,   // encrypt(0^128) to derive H
        GCM_AAD      = 3'd2,   // absorb AAD blocks into GHASH
        GCM_PAYLOAD  = 3'd3,   // encrypt payload + GHASH(ciphertext)
        GCM_TAG_ENC  = 3'd4,   // encrypt J0 for final tag XOR
        GCM_DONE     = 3'd5    // tag ready, hold until consumed
    } gcm_phase_e;

    // -----------------------------------------------------------------------
    //  S-Box LUT  (inline function - used by key expansion and ref model)
    //  Full FIPS-197 table.
    // -----------------------------------------------------------------------
    function automatic logic [7:0] sbox_byte(input logic [7:0] a);
        case (a)
            8'h00:return 8'h63; 8'h01:return 8'h7c; 8'h02:return 8'h77; 8'h03:return 8'h7b;
            8'h04:return 8'hf2; 8'h05:return 8'h6b; 8'h06:return 8'h6f; 8'h07:return 8'hc5;
            8'h08:return 8'h30; 8'h09:return 8'h01; 8'h0a:return 8'h67; 8'h0b:return 8'h2b;
            8'h0c:return 8'hfe; 8'h0d:return 8'hd7; 8'h0e:return 8'hab; 8'h0f:return 8'h76;
            8'h10:return 8'hca; 8'h11:return 8'h82; 8'h12:return 8'hc9; 8'h13:return 8'h7d;
            8'h14:return 8'hfa; 8'h15:return 8'h59; 8'h16:return 8'h47; 8'h17:return 8'hf0;
            8'h18:return 8'had; 8'h19:return 8'hd4; 8'h1a:return 8'ha2; 8'h1b:return 8'haf;
            8'h1c:return 8'h9c; 8'h1d:return 8'ha4; 8'h1e:return 8'h72; 8'h1f:return 8'hc0;
            8'h20:return 8'hb7; 8'h21:return 8'hfd; 8'h22:return 8'h93; 8'h23:return 8'h26;
            8'h24:return 8'h36; 8'h25:return 8'h3f; 8'h26:return 8'hf7; 8'h27:return 8'hcc;
            8'h28:return 8'h34; 8'h29:return 8'ha5; 8'h2a:return 8'he5; 8'h2b:return 8'hf1;
            8'h2c:return 8'h71; 8'h2d:return 8'hd8; 8'h2e:return 8'h31; 8'h2f:return 8'h15;
            8'h30:return 8'h04; 8'h31:return 8'hc7; 8'h32:return 8'h23; 8'h33:return 8'hc3;
            8'h34:return 8'h18; 8'h35:return 8'h96; 8'h36:return 8'h05; 8'h37:return 8'h9a;
            8'h38:return 8'h07; 8'h39:return 8'h12; 8'h3a:return 8'h80; 8'h3b:return 8'he2;
            8'h3c:return 8'heb; 8'h3d:return 8'h27; 8'h3e:return 8'hb2; 8'h3f:return 8'h75;
            8'h40:return 8'h09; 8'h41:return 8'h83; 8'h42:return 8'h2c; 8'h43:return 8'h1a;
            8'h44:return 8'h1b; 8'h45:return 8'h6e; 8'h46:return 8'h5a; 8'h47:return 8'ha0;
            8'h48:return 8'h52; 8'h49:return 8'h3b; 8'h4a:return 8'hd6; 8'h4b:return 8'hb3;
            8'h4c:return 8'h29; 8'h4d:return 8'he3; 8'h4e:return 8'h2f; 8'h4f:return 8'h84;
            8'h50:return 8'h53; 8'h51:return 8'hd1; 8'h52:return 8'h00; 8'h53:return 8'hed;
            8'h54:return 8'h20; 8'h55:return 8'hfc; 8'h56:return 8'hb1; 8'h57:return 8'h5b;
            8'h58:return 8'h6a; 8'h59:return 8'hcb; 8'h5a:return 8'hbe; 8'h5b:return 8'h39;
            8'h5c:return 8'h4a; 8'h5d:return 8'h4c; 8'h5e:return 8'h58; 8'h5f:return 8'hcf;
            8'h60:return 8'hd0; 8'h61:return 8'hef; 8'h62:return 8'haa; 8'h63:return 8'hfb;
            8'h64:return 8'h43; 8'h65:return 8'h4d; 8'h66:return 8'h33; 8'h67:return 8'h85;
            8'h68:return 8'h45; 8'h69:return 8'hf9; 8'h6a:return 8'h02; 8'h6b:return 8'h7f;
            8'h6c:return 8'h50; 8'h6d:return 8'h3c; 8'h6e:return 8'h9f; 8'h6f:return 8'ha8;
            8'h70:return 8'h51; 8'h71:return 8'ha3; 8'h72:return 8'h40; 8'h73:return 8'h8f;
            8'h74:return 8'h92; 8'h75:return 8'h9d; 8'h76:return 8'h38; 8'h77:return 8'hf5;
            8'h78:return 8'hbc; 8'h79:return 8'hb6; 8'h7a:return 8'hda; 8'h7b:return 8'h21;
            8'h7c:return 8'h10; 8'h7d:return 8'hff; 8'h7e:return 8'hf3; 8'h7f:return 8'hd2;
            8'h80:return 8'hcd; 8'h81:return 8'h0c; 8'h82:return 8'h13; 8'h83:return 8'hec;
            8'h84:return 8'h5f; 8'h85:return 8'h97; 8'h86:return 8'h44; 8'h87:return 8'h17;
            8'h88:return 8'hc4; 8'h89:return 8'ha7; 8'h8a:return 8'h7e; 8'h8b:return 8'h3d;
            8'h8c:return 8'h64; 8'h8d:return 8'h5d; 8'h8e:return 8'h19; 8'h8f:return 8'h73;
            8'h90:return 8'h60; 8'h91:return 8'h81; 8'h92:return 8'h4f; 8'h93:return 8'hdc;
            8'h94:return 8'h22; 8'h95:return 8'h2a; 8'h96:return 8'h90; 8'h97:return 8'h88;
            8'h98:return 8'h46; 8'h99:return 8'hee; 8'h9a:return 8'hb8; 8'h9b:return 8'h14;
            8'h9c:return 8'hde; 8'h9d:return 8'h5e; 8'h9e:return 8'h0b; 8'h9f:return 8'hdb;
            8'ha0:return 8'he0; 8'ha1:return 8'h32; 8'ha2:return 8'h3a; 8'ha3:return 8'h0a;
            8'ha4:return 8'h49; 8'ha5:return 8'h06; 8'ha6:return 8'h24; 8'ha7:return 8'h5c;
            8'ha8:return 8'hc2; 8'ha9:return 8'hd3; 8'haa:return 8'hac; 8'hab:return 8'h62;
            8'hac:return 8'h91; 8'had:return 8'h95; 8'hae:return 8'he4; 8'haf:return 8'h79;
            8'hb0:return 8'he7; 8'hb1:return 8'hc8; 8'hb2:return 8'h37; 8'hb3:return 8'h6d;
            8'hb4:return 8'h8d; 8'hb5:return 8'hd5; 8'hb6:return 8'h4e; 8'hb7:return 8'ha9;
            8'hb8:return 8'h6c; 8'hb9:return 8'h56; 8'hba:return 8'hf4; 8'hbb:return 8'hea;
            8'hbc:return 8'h65; 8'hbd:return 8'h7a; 8'hbe:return 8'hae; 8'hbf:return 8'h08;
            8'hc0:return 8'hba; 8'hc1:return 8'h78; 8'hc2:return 8'h25; 8'hc3:return 8'h2e;
            8'hc4:return 8'h1c; 8'hc5:return 8'ha6; 8'hc6:return 8'hb4; 8'hc7:return 8'hc6;
            8'hc8:return 8'he8; 8'hc9:return 8'hdd; 8'hca:return 8'h74; 8'hcb:return 8'h1f;
            8'hcc:return 8'h4b; 8'hcd:return 8'hbd; 8'hce:return 8'h8b; 8'hcf:return 8'h8a;
            8'hd0:return 8'h70; 8'hd1:return 8'h3e; 8'hd2:return 8'hb5; 8'hd3:return 8'h66;
            8'hd4:return 8'h48; 8'hd5:return 8'h03; 8'hd6:return 8'hf6; 8'hd7:return 8'h0e;
            8'hd8:return 8'h61; 8'hd9:return 8'h35; 8'hda:return 8'h57; 8'hdb:return 8'hb9;
            8'hdc:return 8'h86; 8'hdd:return 8'hc1; 8'hde:return 8'h1d; 8'hdf:return 8'h9e;
            8'he0:return 8'he1; 8'he1:return 8'hf8; 8'he2:return 8'h98; 8'he3:return 8'h11;
            8'he4:return 8'h69; 8'he5:return 8'hd9; 8'he6:return 8'h8e; 8'he7:return 8'h94;
            8'he8:return 8'h9b; 8'he9:return 8'h1e; 8'hea:return 8'h87; 8'heb:return 8'he9;
            8'hec:return 8'hce; 8'hed:return 8'h55; 8'hee:return 8'h28; 8'hef:return 8'hdf;
            8'hf0:return 8'h8c; 8'hf1:return 8'ha1; 8'hf2:return 8'h89; 8'hf3:return 8'h0d;
            8'hf4:return 8'hbf; 8'hf5:return 8'he6; 8'hf6:return 8'h42; 8'hf7:return 8'h68;
            8'hf8:return 8'h41; 8'hf9:return 8'h99; 8'hfa:return 8'h2d; 8'hfb:return 8'h0f;
            8'hfc:return 8'hb0; 8'hfd:return 8'h54; 8'hfe:return 8'hbb; 8'hff:return 8'h16;
        endcase
    endfunction

endpackage : aes_pkg