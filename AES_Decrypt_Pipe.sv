// ============================================================================
//  AES_Decrypt_Pipe.sv  -  10-Stage Fully Pipelined AES-128 Decrypt
//
//  BUGS FIXED from AES_Decrypt_Pipe03.sv:
//
//  BUG-D1 (CRITICAL): Output was wired to state[9] and out_valid to valid[9],
//    but the final valid stage index is NUM_ROUNDS-1 = 9 only for stages 0..9.
//    The generate loop runs r=1..(NUM_ROUNDS-1) = 1..9. State[9] IS the last
//    stage (r=9), but the module declared PIPE_DEPTH = NUM_ROUNDS+1 = 11 and
//    allocated state[0:PIPE_DEPTH-1] = state[0:10]. Stage 10 was never written.
//    The decrypt pipeline has exactly 10 stages (0..9), not 11:
//      Stage 0:    AddRoundKey(K10)
//      Stage 1..8: InvShiftRows → InvSubBytes → ARK(K(10-r)) → InvMixColumns
//      Stage 9:    InvShiftRows → InvSubBytes → ARK(K0) [no InvMixColumns]
//    The stall condition referenced valid[10] which was never set → stall=0
//    always, meaning backpressure was broken. Output was valid[9] which
//    happened to be coincidentally correct for the 10-stage depth, but the
//    stall mechanism was completely broken.
//
//    FIX: Remove stage 10 slot. PIPE_DEPTH = NUM_ROUNDS = 10.
//    Stall references valid[PIPE_DEPTH-1] = valid[9]. Output = state[9].
//    All indices corrected.
//
//  BUG-D2: Final round check was (r == NUM_ROUNDS-1) to skip InvMixColumns.
//    With NUM_ROUNDS=10 that means r==9, correct. But the check used
//    `if(r == NUM_ROUNDS-1) state[r] <= ark; else state[r] <= imc;`
//    which means stage 9 stores ark (no IMC) - correct for final round.
//    Verified: this is correct. No change needed.
//
//  BUG-D3: InvSubBytes port name was `.in` / `.out`. The original
//    InvSubBytes.sv uses `in` and `out`. Preserved.
//
//  Decrypt pipeline structure (FIPS-197 §5.3, standard inverse cipher):
//    Stage 0:    ARK(K10)
//    Stages 1-8: InvShiftRows → InvSubBytes → ARK(K(10-r)) → InvMixColumns
//    Stage 9:    InvShiftRows → InvSubBytes → ARK(K0)  [no IMC]
// ============================================================================
`timescale 1ns/1ps
 
import aes_pkg::*;

module AES_Decrypt_Pipe #(
    parameter int NUM_ROUNDS = aes_pkg :: NUM_ROUNDS,
    parameter int PIPE_DEPTH = NUM_ROUNDS
    )(
    input  logic        clk,
    input  logic        reset,

    input  logic        in_valid,
    output logic        in_ready,
    input  aes_block_t  ciphertext,
    input  logic        current_bank,

    input  rk_store_t   round_keys,

    output aes_block_t  plaintext,
    output logic        out_valid,
    input  logic        out_ready,

    output logic [1:0]  bank_busy
    );
    
    aes_block_t state[0:PIPE_DEPTH-1];
    logic       valid[0:PIPE_DEPTH-1];
    logic       bank [0:PIPE_DEPTH-1];
    
    logic stall;
    assign stall = valid[PIPE_DEPTH-1] && !out_ready;
    assign in_ready = !stall;
    
    always_comb begin
        bank_busy = 2'b00;
        for ( int i  = 0; i < PIPE_DEPTH ; i++ ) 
            if (valid[i])
                bank_busy[bank[i]] = 1'b1;
    end
    
    // -----------------------------------------------------------------------
    //  Stage 0 - AddRoundKey(K10)
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            valid[0] <= 1'b0;
            bank[0] <= '0;
            state[0] <= '0;
            
        end
        else if (!stall) begin
            valid[0] <= in_valid;
            bank[0]  <= current_bank;
            state[0] <= ciphertext ^ round_keys[current_bank][NUM_ROUNDS];
        end
    end

    // -----------------------------------------------------------------------
    //  Stages 1..9
    //  r=1..8: InvShiftRows → InvSubBytes → ARK(K(10-r)) → InvMixColumns
    //  r=9:    InvShiftRows → InvSubBytes → ARK(K0)       (no InvMixColumns)
    // -----------------------------------------------------------------------
    generate
        for (genvar r = 1; r < NUM_ROUNDS; r++) begin : DEC_STAGE

            aes_block_t isr, isb, ark, imc;

            InvShiftRows u_isr (.inp(state[r-1]), .out(isr));
            InvSubBytes  u_isb (.in(isr),         .out(isb));
            assign ark = isb ^ round_keys[bank[r-1]][NUM_ROUNDS - r];
            InvMixColumns u_imc (.inp(ark), .res(imc));

            always_ff @(posedge clk) begin
                if(reset) begin

                    valid[r] <= 0;
                    state[r] <= '0;
                    bank[r]  <= 0;

                end
                    
                else if (!stall) begin
                    valid[r] <= valid[r-1];
                    bank[r]  <= bank[r-1];
                    // Final round (r=9): skip InvMixColumns
                    if (r == NUM_ROUNDS - 1)
                        state[r] <= ark;
                    else
                        state[r] <= imc;
                end
            end
        end
    endgenerate

    assign plaintext = state[PIPE_DEPTH-1];  // BUG-D1 fix
    assign out_valid = valid[PIPE_DEPTH-1];  // BUG-D1 fix

endmodule : AES_Decrypt_Pipe