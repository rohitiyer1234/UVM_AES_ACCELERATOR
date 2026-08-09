// ============================================================================
//  AES_Encrypt_Pipe.sv  -  11-Stage Fully Pipelined AES-128 Encrypt
//
//  BUGS FIXED from AES_Encrpt_Pipe03.sv:
//
//  BUG-E1: `PIPE_DEPTH` used as array bound but never declared as a local
//    parameter. The original relied on importing it from aes_pkg, but since
//    it's used as a static array size in the module body, it must be a local
//    parameter or the import must be explicit. Fixed: localparam PIPE_DEPTH.
//
//  BUG-E2: Stage r (1..9) applies MixColumns to ALL rounds including round 9.
//    Round 9 result feeds the final stage (stage 10) which must receive the
//    post-MixColumns value. The final round (stage 10) must NOT apply
//    MixColumns. The generate loop goes r=1..9, and the final stage is
//    hardcoded outside the loop. This is correct - the loop stages 1..9
//    all apply MixColumns including stage 9, and stage 10 (final) is the
//    separate always_ff block. However stage 9 SHOULD apply MixColumns
//    (it feeds stage 10 which does SubBytes+ShiftRows+ARK without MC).
//    CONFIRMED CORRECT: loop r=1..9 all apply MC, stage 10 does not. OK.
//
//  BUG-E3: The generate loop ends at r < 10 (i.e., r=1..9). Stage 10
//    is the separate final block. This is correct for AES-128.
//    But: the final block uses state[NUM_ROUNDS-1] = state[9] as its input,
//    which is the output of the last generate iteration (r=9). Correct.
//
//  NO LOGIC CHANGES to pipeline stages. Only structural fixes:
//    - Added localparam PIPE_DEPTH
//    - stall condition references valid[PIPE_DEPTH-1] (was valid[10])
//    - bank_busy loop uses PIPE_DEPTH
//    - Renamed module to AES_Encrypt_Pipe (dropped "03")
//    - SubBytes port: inp→inp, res→res (already correct)
//    - ShiftRows port: inp→inp, out→out (already correct)
//    - MixColumns port: inp→inp, res→res (already correct)
// ============================================================================
`timescale 1ns/1ps

import aes_pkg::*;

module AES_Encrypt_Pipe #(
    parameter int NUM_ROUNDS = 10
)(
    input  logic        clk,
    input  logic        reset,

    input  logic        in_valid,
    output logic        in_ready,
    input  aes_block_t  plaintext,
    input  logic        current_bank,

    input  rk_store_t   round_keys,

    output aes_block_t  ciphertext,
    output logic        out_valid,
    input  logic        out_ready,

    output logic [1:0]  bank_busy
);

    localparam int PIPE_DEPTH = NUM_ROUNDS + 1;  // BUG-E1 fix

    aes_block_t state [0:PIPE_DEPTH-1];
    logic       valid [0:PIPE_DEPTH-1];
    logic       bank  [0:PIPE_DEPTH-1];

    logic stall;
    assign stall    = valid[PIPE_DEPTH-1] && !out_ready;
    assign in_ready = !stall;

    // bank_busy: which key banks have live data in the pipeline
    always_comb begin
        bank_busy = 2'b00;
        for (int i = 0; i < PIPE_DEPTH; i++)
            if (valid[i])
                bank_busy[bank[i]] = 1'b1;
    end

    // -----------------------------------------------------------------------
    //  Stage 0 - AddRoundKey(K0)
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset)
            valid[0] <= 1'b0;
        else if (!stall) begin
            valid[0] <= in_valid;
            bank[0]  <= current_bank;
            state[0] <= plaintext ^ round_keys[current_bank][0];
        end
    end

    // -----------------------------------------------------------------------
    //  Stages 1..9 - SubBytes → ShiftRows → MixColumns → AddRoundKey(Kr)
    // -----------------------------------------------------------------------
    generate
        for (genvar r = 1; r < NUM_ROUNDS; r++) begin : ENC_STAGE

            aes_block_t sb, sr, mc;

            SubBytes  u_sb (.inp(state[r-1]), .res(sb));
            ShiftRows u_sr (.inp(sb),         .out(sr));
            MixColumns u_mc(.inp(sr),         .res(mc));

            always_ff @(posedge clk) begin
                if (reset)
                    valid[r] <= 1'b0;
                else if (!stall) begin
                    valid[r] <= valid[r-1];
                    bank[r]  <= bank[r-1];
                    state[r] <= mc ^ round_keys[bank[r-1]][r];
                end
            end
        end
    endgenerate

    // -----------------------------------------------------------------------
    //  Stage 10 (final) - SubBytes → ShiftRows → AddRoundKey(K10)
    //  MixColumns omitted per FIPS-197 final round.
    // -----------------------------------------------------------------------
    aes_block_t sb_final, sr_final;

    SubBytes  u_sb_final (.inp(state[NUM_ROUNDS-1]), .res(sb_final));
    ShiftRows u_sr_final (.inp(sb_final),            .out(sr_final));

    always_ff @(posedge clk) begin
        if (reset)
            valid[NUM_ROUNDS] <= 1'b0;
        else if (!stall) begin
            valid[NUM_ROUNDS] <= valid[NUM_ROUNDS-1];
            bank[NUM_ROUNDS]  <= bank[NUM_ROUNDS-1];
            state[NUM_ROUNDS] <= sr_final ^ round_keys[bank[NUM_ROUNDS-1]][NUM_ROUNDS];
        end
    end

    assign ciphertext = state[NUM_ROUNDS];
    assign out_valid  = valid[NUM_ROUNDS];

endmodule : AES_Encrypt_Pipe