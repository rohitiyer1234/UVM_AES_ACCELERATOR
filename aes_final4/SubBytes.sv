module SubBytes (
    input  [127:0] inp,    // 16 input bytes
    output [127:0] res     // 16 output bytes after S-box
);

    genvar i;
    // Unrolled byte-wise substitution through the sbox function
    logic [7:0] b [15:0];
    genvar k;

    // Explicit byte extraction
    assign {
        b[0],  b[1],  b[2],  b[3],
        b[4],  b[5],  b[6],  b[7],
        b[8],  b[9],  b[10], b[11],
        b[12], b[13], b[14], b[15]
    } = inp;
// Byte-wise S-box
    generate
    for (k = 0; k < 16; k = k + 1) begin : SB_BYTES
        assign res[127 - 8*k -: 8] = sbox(b[k]);
    end
    endgenerate



    //==============================================================
    // S-BOX FUNCTION (Top Level)
    // Using composite-field math:
    //   1. Apply isomorphism
    //   2. Split into GF(2^4) halves g1 || g0
    //   3. Compute various terms in GF(2^4)
    //   4. Compute inverse in GF(2^8) using tower fields
    //   5. Apply inverse isomorphism + affine transform
    //==============================================================
    function automatic [7:0] sbox(input [7:0] in_byte);

        reg [7:0] out_iso;
        reg [3:0] g0, g1;
        reg [3:0] t_mul, t_sq, t_sqv;
        reg [3:0] inv;
        reg [3:0] d0, d1;

        begin
            // Step 1: Isomorphic mapping to composite field
            out_iso = isomorph(in_byte);

            // Split into halves
            g1 = out_iso[7:4];
            g0 = out_iso[3:0];

            // Compute required intermediate GF(2^4) quantities
            t_mul  = gf4_mul(g1, g0);
            t_sq   = gf4_sq(g0);
            t_sqv  = gf4_sq_mul_v(g1);

            // Inversion in GF(2^4)
            inv = gf4_inv(t_mul ^ t_sq ^ t_sqv);

            // Reconstruction of GF(2^8) inverse in tower fields
            d1 = gf4_mul(g1, inv);
            d0 = gf4_mul(g0 ^ g1, inv);

            // Final affine transform + inverse isomorphism
            sbox = inv_isomorph_and_affine({d1, d0});
        end
    endfunction


    //==============================================================
    // ISOMORPHIC TRANSFORMATION
    //==============================================================
    function automatic [7:0] isomorph(input [7:0] a);
        begin
            isomorph[7] = a[5] ^ a[7];
            isomorph[6] = a[1] ^ a[5] ^ a[4] ^ a[6];
            isomorph[5] = a[3] ^ a[2] ^ a[5] ^ a[7];
            isomorph[4] = a[3] ^ a[2] ^ a[4] ^ a[7] ^ a[6];
            isomorph[3] = a[1] ^ a[2] ^ a[7] ^ a[6];
            isomorph[2] = a[3] ^ a[2] ^ a[7] ^ a[6];
            isomorph[1] = a[1] ^ a[4] ^ a[6];
            isomorph[0] = a[1] ^ a[0] ^ a[3] ^ a[2] ^ a[7];
        end
    endfunction


    //==============================================================
    // GF(2^4) SQUARING
    //==============================================================
    function automatic [3:0] gf4_sq(input [3:0] a);
        begin
            gf4_sq[3] = a[3];
            gf4_sq[2] = a[1] ^ a[3];
            gf4_sq[1] = a[2];
            gf4_sq[0] = a[0] ^ a[2];
        end
    endfunction


    //==============================================================
    // GF(2^4) SQUARING + MULTIPLY BY V TERM
    // (Used as part of inversion calculation)
    //==============================================================
    function automatic [3:0] gf4_sq_mul_v(input [3:0] a);

        reg [3:0] a_sq, a1, a2, a3;
        reg [3:0] p0, p1, p2;

        begin
            // Square
            a_sq[3] = a[3];
            a_sq[2] = a[1] ^ a[3];
            a_sq[1] = a[2];
            a_sq[0] = a[0] ^ a[2];

            p0 = a_sq;

            // Multiply via shift + reduction
            a1 = {a_sq[2:0],1'b0} ^ (a_sq[3] ? 4'b0011 : 4'b0000);
            p1 = p0;

            a2 = {a1[2:0],1'b0} ^ (a1[3] ? 4'b0011 : 4'b0000);
            p2 = p1 ^ a2;

            a3 = {a2[2:0],1'b0} ^ (a2[3] ? 4'b0011 : 4'b0000);

            gf4_sq_mul_v = p2 ^ a3;
        end
    endfunction


    //==============================================================
    // GF(2^4) MULTIPLICATION
    //==============================================================
    function automatic [3:0] gf4_mul(input [3:0] a, input [3:0] b);

        reg [3:0] a1, a2, a3;
        reg [3:0] p0, p1, p2;

        begin
            p0 = b[0] ? a : 4'b0000;
            a1 = {a[2:0],1'b0} ^ (a[3] ? 4'b0011 : 4'b0000);

            p1 = p0 ^ (b[1] ? a1 : 4'b0000);
            a2 = {a1[2:0],1'b0} ^ (a1[3] ? 4'b0011 : 4'b0000);

            p2 = p1 ^ (b[2] ? a2 : 4'b0000);
            a3 = {a2[2:0],1'b0} ^ (a2[3] ? 4'b0011 : 4'b0000);

            gf4_mul = p2 ^ (b[3] ? a3 : 4'b0000);
        end
    endfunction


    //==============================================================
    // GF(2^4) INVERSION
    //==============================================================
    function automatic [3:0] gf4_inv(input [3:0] a);
        begin
            gf4_inv[3] = (a[3] & a[2] & a[1] & a[0]) |
                         (~a[3] & ~a[2] & a[1]) |
                         (~a[3] &  a[2] & ~a[1]) |
                         ( a[3] & ~a[2] & ~a[0]) |
                         ( a[2] & ~a[1] & ~a[0]);

            gf4_inv[2] = (a[3] & a[2] & ~a[1] & a[0]) |
                         (~a[3] & a[2] & ~a[0]) |
                         ( a[3] & ~a[2] & ~a[0]) |
                         (~a[2] & a[1] & a[0]) |
                         (~a[3] & a[1] & a[0]);

            gf4_inv[1] = (a[3] & ~a[2] & ~a[1]) |
                         (~a[3] & a[1] & a[0]) |
                         (~a[3] & a[2] & a[0]) |
                         (a[3] &  a[2] & ~a[0]) |
                         (~a[3] & a[2] & a[1]);

            gf4_inv[0] = (a[3] & ~a[2] & ~a[1] & ~a[0]) |
                         (a[3] & ~a[2] &  a[1] &  a[0]) |
                         (~a[3] & ~a[1] & a[0]) |
                         (~a[3] &  a[1] & ~a[0]) |
                         (a[2] & a[1] & ~a[0]) |
                         (~a[3] & a[2] & ~a[1]);
        end
    endfunction


    //==============================================================
    // INVERSE ISOMORPHISM + AFFINE TRANSFORMATION (AES STANDARD)
    //==============================================================
    function automatic [7:0] inv_isomorph_and_affine(input [7:0] d);
        begin
            inv_isomorph_and_affine[7] = d[1] ^ d[2] ^ d[3] ^ d[7];
            inv_isomorph_and_affine[6] = ~(d[4] ^ d[7]);
            inv_isomorph_and_affine[5] = ~(d[1] ^ d[2] ^ d[7]);
            inv_isomorph_and_affine[4] = d[0] ^ d[1] ^ d[2] ^ d[4] ^ d[6] ^ d[7];
            inv_isomorph_and_affine[3] = d[0];
            inv_isomorph_and_affine[2] = d[0] ^ d[1] ^ d[3] ^ d[4];
            inv_isomorph_and_affine[1] = ~(d[0] ^ d[2] ^ d[7]);
            inv_isomorph_and_affine[0] = ~(d[0] ^ d[5] ^ d[6] ^ d[7]);
        end
    endfunction
endmodule