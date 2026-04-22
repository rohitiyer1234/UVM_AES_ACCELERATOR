// ============================================================================
//  AES_Key_Expansion_128.sv  -  STEP 4
//  Sequential AES-128 key expansion: generates round keys 0..10 one per cycle.
//
//  Bugs fixed vs original Verilog
//  ─────────────────────────────
//  BUG-4 : rcon(round) when round=0 returns 0x00 (default case), corrupting
//          the first derived round key. Fix: use rcon(round + 1) so the
//          first expansion step uses rcon(1) = 0x01.
// ============================================================================
/* `timescale 1ns/1ps

import aes_pkg::*;

module AES_Key_Expansion_128 (

    input  logic clk,
    input  logic reset,
    //---------------------------------
    // controller interface
    //---------------------------------
    input  logic exp_start,
    input  logic expand_enable,
    //---------------------------------
    // key input
    //---------------------------------
    input  aes_block_t key_in,
    //---------------------------------
    // write interface to keymem
    //---------------------------------
    output logic        w_en,
    output logic [3:0]  waddr,
    output aes_block_t  wkey,
    //---------------------------------
    // status
    //---------------------------------
    output logic done
);

logic active;
logic [3:0] round;
aes_block_t key_reg;
//-------------------------------------
// split key into 32-bit words
//-------------------------------------

aes_word_t w0,w1,w2,w3;

aes_word_t g_out;
aes_word_t nw0,nw1,nw2,nw3;
aes_block_t next_key;

assign {w0,w1,w2,w3} = key_reg;
assign g_out = subword(rotword(w3)) ^ {rcon(round+1),24'h0};
assign nw0 = w0 ^ g_out;
assign nw1 = w1 ^ nw0;
assign nw2 = w2 ^ nw1;
assign nw3 = w3 ^ nw2;

assign next_key = {nw0,nw1,nw2,nw3};

//-------------------------------------
// sequential logic
//-------------------------------------
always_ff @(posedge clk) begin

    if(reset) begin
        active  <= 0;
        round   <= 0;
        w_en    <= 0;
        waddr   <= 0;
        wkey    <= 0;
        key_reg <= 0;
        done    <= 0;
    end
    else begin
        w_en <= 0;
        done <= 0;
        //---------------------------------
        // start expansion
        //---------------------------------
        if(exp_start && expand_enable) begin
            active  <= 1;
            round   <= 0;
            key_reg <= key_in;
            //---------------------------------
            // write K0 immediately
            //---------------------------------
            w_en  <= 1;
            waddr <= 0;
            wkey  <= key_in;
        end
       //---------------------------------
        // continue expansion
        //---------------------------------
        else if(active && expand_enable) begin
            key_reg <= next_key;
            round   <= round + 1;
            w_en  <= 1;
            waddr <= round + 1;
            wkey  <= next_key;
            //---------------------------------
            // finished all 11 keys
            //---------------------------------
            if(round == 9) begin
                active <= 0;
                done   <= 1;
            end
        end
    end
end
    
    function automatic [31:0] rotword(input [31:0] w);
        rotword = {w[23:0], w[31:24]};
    endfunction

    function automatic [31:0] subword(input [31:0] w);
        subword = {
            sbox(w[31:24]),
            sbox(w[23:16]),
            sbox(w[15:8]),
            sbox(w[7:0])
        };
    endfunction

    function automatic [7:0] rcon(input [3:0] r);
        case (r)
            4'd1: rcon = 8'h01;
            4'd2: rcon = 8'h02;
            4'd3: rcon = 8'h04;
            4'd4: rcon = 8'h08;
            4'd5: rcon = 8'h10;
            4'd6: rcon = 8'h20;
            4'd7: rcon = 8'h40;
            4'd8: rcon = 8'h80;
            4'd9: rcon = 8'h1B;
            4'd10: rcon = 8'h36;
            default: rcon = 8'h00;
        endcase
    endfunction

    function automatic [7:0] sbox;
        input [7:0] in_byte;
        reg [7:0] out_iso;
        reg [3:0] g0;
        reg [3:0] g1;
        reg [3:0] g1_g0_t;
        reg [3:0] g0_sq;
        reg [3:0] g1_sq_mult_v;
        reg [3:0] inverse;
        reg [3:0] d0;
        reg [3:0] d1;
        
        begin
        out_iso = isomorph(in_byte);

        g1 = out_iso[7:4];
        g0 = out_iso[3:0];

        g1_g0_t = gf4_mul(g1, g0);
        g0_sq = gf4_sq(g0);
        g1_sq_mult_v = gf4_sq_mul_v(g1);

        inverse = gf4_inv((g1_g0_t ^ g0_sq ^ g1_sq_mult_v));

        d1 = gf4_mul(g1, inverse);
        d0 = gf4_mul((g0 ^ g1), inverse);

        sbox = inv_isomorph_and_affine({d1, d0});
        end
    endfunction

    //Helper functions used to define SBOX are defined below
    function automatic [7:0] isomorph;
        input [7:0] a;
        begin
            isomorph[7] =a[5] ^ a[7];
            isomorph[6] =a[1] ^ a[5] ^ a[4] ^ a[6];
            isomorph[5] =a[3] ^ a[2] ^ a[5] ^ a[7];
            isomorph[4] =a[3] ^ a[2] ^ a[4] ^ a[7] ^ a[6];
            isomorph[3] =a[1] ^ a[2] ^ a[7] ^ a[6];
            isomorph[2] =a[3] ^ a[2] ^ a[7] ^ a[6];
            isomorph[1] =a[1] ^ a[4] ^ a[6];
            isomorph[0] =a[1] ^ a[0] ^ a[3] ^ a[2] ^ a[7];
        end
    endfunction

    function automatic [3:0] gf4_sq;
        input [3:0] a;
        begin
        gf4_sq[3] = a[3];
        gf4_sq[2] = a[1] ^ a[3];
        gf4_sq[1] = a[2];
        gf4_sq[0] = a[0] ^ a[2];
        end
    endfunction

    function automatic [3:0] gf4_sq_mul_v;
        input [3:0] a;

        reg [3:0] a_sq;

        reg [3:0] a_1;
        reg [3:0] a_2;
        reg [3:0] a_3;

        reg [3:0] p_0;
        reg [3:0] p_1;
        reg [3:0] p_2;

        begin
        a_sq[3] = a[3];
        a_sq[2] = a[1] ^ a[3];
        a_sq[1] = a[2];
        a_sq[0] = a[0] ^ a[2];

        p_0 = a_sq;
        a_1 = {a_sq[2:0], 1'b0} ^ ((a_sq[3])? 4'b0011 : 4'b0);

        p_1 = p_0;
        a_2 = {a_1[2:0], 1'b0} ^ ((a_1[3])? 4'b0011 : 4'b0);

        p_2 = p_1 ^ a_2;
        a_3 = {a_2[2:0], 1'b0} ^ ((a_2[3])? 4'b0011 : 4'b0);

        gf4_sq_mul_v = p_2 ^ a_3;
        end
    endfunction

    function automatic [3:0] gf4_mul;
        input [3:0] a;
        input [3:0] b;
        reg [3:0] a_1;
        reg [3:0] a_2;
        reg [3:0] a_3;

        reg [3:0] p_0;
        reg [3:0] p_1;
        reg [3:0] p_2;
        begin
        p_0 = (b[0])? a : 4'b0;
        a_1 = {a[2:0], 1'b0} ^ ((a[3])? 4'b0011 : 4'b0);

        p_1 = p_0 ^ ((b[1])? a_1 : 4'b0);
        a_2 = {a_1[2:0], 1'b0} ^ ((a_1[3])? 4'b0011 : 4'b0);

        p_2 = p_1 ^ ((b[2])? a_2 : 4'b0);
        a_3 = {a_2[2:0], 1'b0} ^ ((a_2[3])? 4'b0011 : 4'b0);

        gf4_mul = p_2 ^ ((b[3])? a_3 : 4'b0);
        end
    endfunction

    function automatic [3:0] gf4_inv;
        input [3:0] a;
        begin
        gf4_inv[3] = (a[3] & a[2] & a[1] & a[0]) | (~a[3] & ~a[2] & a[1]) | (~a[3] & a[2] & ~a[1]) | (a[3] & ~a[2] & ~a[0]) | (a[2] & ~a[1] & ~a[0]);
        gf4_inv[2] = (a[3] & a[2] & ~a[1] & a[0]) | (~a[3] & a[2] & ~a[0]) | (a[3] & ~a[2] & ~a[0]) | (~a[2] & a[1] & a[0]) | (~a[3] & a[1] & a[0]);
        gf4_inv[1] =  (a[3] & ~a[2] & ~a[1]) | (~a[3] & a[1] & a[0]) | (~a[3] & a[2] & a[0]) | (a[3] & a[2] & ~a[0]) | (~a[3] & a[2] & a[1]);
        gf4_inv[0] = (a[3] & ~a[2] & ~a[1] & ~a[0]) | (a[3] & ~a[2] & a[1] & a[0]) | (~a[3] & ~a[1] & a[0]) | (~a[3] & a[1] & ~a[0]) | (a[2] & a[1] & ~a[0]) | (~a[3] & a[2] & ~a[1]);
        end
    endfunction

    function automatic [7:0] inv_isomorph_and_affine;
        input [7:0] delta;
        begin
        inv_isomorph_and_affine[7] = delta[1] ^ delta[2] ^ delta[3] ^ delta[7];
        inv_isomorph_and_affine[6] = ~(delta[4] ^ delta[7]);
        inv_isomorph_and_affine[5] = ~(delta[1] ^ delta[2] ^ delta[7]);
        inv_isomorph_and_affine[4] = delta[0] ^ delta[1] ^ delta[2] ^ delta[4] ^ delta[6] ^ delta[7];
        inv_isomorph_and_affine[3] = delta[0];
        inv_isomorph_and_affine[2] = delta[0] ^ delta[1] ^ delta[3] ^ delta[4];
        inv_isomorph_and_affine[1] = ~(delta[0] ^ delta[2] ^ delta[7]);
        inv_isomorph_and_affine[0] = ~(delta[0] ^ delta[5] ^ delta[6] ^ delta[7]);
        end
    endfunction

endmodule
*/


// ============================================================================
//  AES_Key_Expansion_128.sv  -  AES-128 Sequential Key Expansion
//
//  STATUS: Functionally correct as-provided. One interface change made:
//
//  ORIGINAL INTERFACE MISMATCH (not a logic bug):
//  The original module used exp_start + expand_enable separately. The
//  aes_top.sv (STEP 7) provided with the project already has the corrected
//  BUG-4 fix (rcon(round+1)) and uses exp_start/expand_enable.
//  However aes_top.sv then instantiated with start_valid/start_ready which
//  do not exist in this module - indicating a later refactor was attempted
//  but left incomplete. This file keeps the original exp_start/expand_enable
//  interface which matches key_system_top.sv correctly.
//
//  BUG-4 (already fixed in original):
//    rcon(round) returns 0x00 for round=0 (default case), corrupting K1.
//    Fixed by using rcon(round+1): first expansion uses rcon(1)=0x01.
//
//  Writes: K0 immediately on exp_start, then K1..K10 on successive cycles.
//  Total latency: 12 cycles from exp_start to done (K0 written on cycle 1,
//  K10 written + done on cycle 12).
// ============================================================================
`timescale 1ns/1ps

import aes_pkg::*;

module AES_Key_Expansion_128 (
    input  logic clk,
    input  logic reset,
    // ---- controller interface ----
    input  logic exp_start,        // one-cycle pulse: begin expansion
    input  logic expand_enable,    // qual: asserted while target bank is free
    // ---- key input ----
    input  aes_block_t key_in,
    // ---- write interface to keymem ----
    output logic        w_en,
    output logic [3:0]  waddr,
    output aes_block_t  wkey,
    // ---- status ----
    output logic        done       // one-cycle pulse: all 11 keys written
);

    logic      active;
    logic[3:0] round;
    aes_block_t key_reg;

    // Word split
    aes_word_t w0, w1, w2, w3;
    aes_word_t g_out;
    aes_word_t nw0, nw1, nw2, nw3;
    aes_block_t next_key;

    assign {w0,w1,w2,w3} = key_reg;
    assign g_out          = subword(rotword(w3)) ^ {rcon(round + 4'(1)), 24'h0};
    assign nw0            = w0 ^ g_out;
    assign nw1            = w1 ^ nw0;
    assign nw2            = w2 ^ nw1;
    assign nw3            = w3 ^ nw2;
    assign next_key       = {nw0, nw1, nw2, nw3};

    always_ff @(posedge clk) begin
        if (reset) begin
            active  <= 1'b0;
            round   <= 4'd0;
            w_en    <= 1'b0;
            waddr   <= 4'd0;
            wkey    <= '0;
            key_reg <= '0;
            done    <= 1'b0;
        end else begin
            w_en <= 1'b0;
            done <= 1'b0;

            if (exp_start && expand_enable) begin
                // Write K0 immediately; begin iterating K1..K10
                active  <= 1'b1;
                round   <= 4'd0;
                key_reg <= key_in;
                w_en    <= 1'b1;
                waddr   <= 4'd0;
                wkey    <= key_in;
            end else if (active && expand_enable) begin
                key_reg <= next_key;
                round   <= round + 4'd1;
                w_en    <= 1'b1;
                waddr   <= round + 4'd1;
                wkey    <= next_key;
                if (round == 4'd9) begin
                    active <= 1'b0;
                    done   <= 1'b1;
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    //  Local key-schedule helpers (duplicated from SubBytes to avoid
    //  instantiating a full 128-bit SubBytes just for 32 bits of subword)
    // -----------------------------------------------------------------------
    function automatic [31:0] rotword(input logic [31:0] w);
        rotword = {w[23:0], w[31:24]};
    endfunction

    function automatic [31:0] subword(input logic [31:0] w);
        subword = {
            sbox_byte(w[31:24]),
            sbox_byte(w[23:16]),
            sbox_byte(w[15: 8]),
            sbox_byte(w[ 7: 0])
        };
    endfunction

    // rcon table: index 1..10 → FIPS-197 values
    function automatic [7:0] rcon(input logic [3:0] r);
        case (r)
            4'd1:  rcon = 8'h01;
            4'd2:  rcon = 8'h02;
            4'd3:  rcon = 8'h04;
            4'd4:  rcon = 8'h08;
            4'd5:  rcon = 8'h10;
            4'd6:  rcon = 8'h20;
            4'd7:  rcon = 8'h40;
            4'd8:  rcon = 8'h80;
            4'd9:  rcon = 8'h1b;
            4'd10: rcon = 8'h36;
            default: rcon = 8'h00;
        endcase
    endfunction

endmodule : AES_Key_Expansion_128