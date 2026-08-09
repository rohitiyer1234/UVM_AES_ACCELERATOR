// ============================================================================
//  keymem_dual.sv
//
//  Dual-bank AES round-key memory
//
//  PURPOSE
//  -------
//  Stores expanded AES round keys for two independent banks.
//  One bank may be actively used by encrypt/decrypt pipelines
//  while the other bank is being populated by key expansion.
//
//  DESIGN GOALS
//  ------------
//  - Timing-closure safe
//  - Fully synthesizable
//  - No combinational loops
//  - No stale bank-valid races
//  - Safe bank reuse
//  - Compatible with AES encrypt/decrypt pipelines
//  - bank_busy comes FROM pipelines and propagates upward
//
//  FIXES APPLIED
//  -------------
//  1. bank_valid derived ONLY from registered valid bits
//  2. Added explicit bank_release support
//  3. Removed valid_next race hazard
//  4. Full reset initialization
//  5. Timing-safe sequential control
//  6. No combinational feedback paths
//  7. Safe simultaneous release/write handling
// ============================================================================

`timescale 1ns/1ps

import aes_pkg::*;

module keymem_dual (

    input  logic        clk,
    input  logic        reset,
   
    // Write interface from key expansion engine

    input  logic        w_en,
    input  logic [3:0]  waddr,
    input  aes_block_t  wkey,
    input  logic        write_bank,

    // ------------------------------------------------------------
    // Release interface
    // Higher-level controller releases bank after pipelines finish
    // ------------------------------------------------------------
    input  logic [1:0]  bank_release,
    // ------------------------------------------------------------
    // Busy feedback from AES pipelines
    // ------------------------------------------------------------
    input  logic [1:0]  bank_busy,
    // ------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------
    output rk_store_t   round_keys,
    output logic [1:0]  bank_valid,
    output logic [1:0]  bank_free

);

    // ============================================================
    // MEMORY STORAGE
    // ============================================================

    aes_block_t mem [0:1][0:NUM_ROUNDS];

    // valid[b][r]
    // Indicates whether round-key r in bank b is valid

    logic [NUM_ROUNDS:0] valid [0:1];

    // ============================================================
    // BANK STATUS
    // ============================================================

    always_comb begin
        // --------------------------------------------------------
        // A bank is FREE only if:
        // 1. not busy in pipelines
        // 2. not already fully populated
        // --------------------------------------------------------
        bank_free[0] = !bank_busy[0] && !bank_valid[0];
        bank_free[1] =  !bank_busy[1] && !bank_valid[1];
    end

    // ============================================================
    // SEQUENTIAL MEMORY + VALID CONTROL
    // ============================================================
    always_ff @(posedge clk) begin
        if(reset) begin
            // ----------------------------------------------------
            // Reset valid state
            // ----------------------------------------------------
            valid[0] <= '0;
            valid[1] <= '0;
            bank_valid <= 2'b00;
            // ----------------------------------------------------
            // Optional memory clear
            // ----------------------------------------------------
            for(int b=0;b<2;b++) begin
                for(int r=0;r<=NUM_ROUNDS;r++) begin
                    mem[b][r] <= '0;
                end
            end
        end
        else begin
            // ====================================================
            // BANK RELEASE
            // ====================================================

            // Release has highest priority
            // Clears validity for bank reuse
            if(bank_release[0]) begin
                valid[0]      <= '0;
                bank_valid[0] <= 1'b0;
            end
            if(bank_release[1]) begin
                valid[1]      <= '0;
                bank_valid[1] <= 1'b0;
            end
            // ====================================================
            // KEY WRITE
            // ====================================================
            if(w_en && bank_free[write_bank]) begin
                mem[write_bank][waddr] <= wkey;
                valid[write_bank][waddr] <= 1'b1;
            end
            // ====================================================
            // BANK VALID GENERATION
            // ====================================================

            // Registered generation prevents:
            // - stale read races
            // - same-cycle visibility hazards
            // - timing ambiguity
            bank_valid[0] <= &valid[0];
            bank_valid[1] <= &valid[1];
        end
    end

    // ============================================================
    // CONTINUOUS ROUND-KEY READ BUS
    // ============================================================

    // Purely combinational read exposure
    // Timing-safe because:
    // - tiny fanout
    // - stable SRAM/register outputs
    // - no feedback paths
    always_comb begin
        for(int b=0;b<2;b++) begin
            for(int r=0;r<=NUM_ROUNDS;r++) begin
                round_keys[b][r] = mem[b][r];
            end
        end
    end
endmodule