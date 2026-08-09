// ============================================================================
//  ghash_gf128_mul_4b.sv  -  4-bit/cycle GF(2^128) Multiplier
//
//  DROP-IN REPLACEMENT for ghash_gf128_mul.sv
//  Same ports, same start/done/busy semantics.
//  32-cycle latency instead of 128. 4× LUT increase.
//
//  ARCHITECTURE
//  ─────────────
//  Processes 4 bits of b per clock cycle.
//  Per nibble, computes 4 partial products (b[3]*a_shifted[3..0]) and
//  XORs them into the accumulator. a_shifted is pre-multiplied by x^0..x^3
//  (i.e. a, a*x, a*x^2, a*x^3 in GF(2^128)) for the current nibble.
//
//  Each x-multiply is a 1-bit shift + conditional XOR with REDUCE -
//  a critical path of: 1 register + 1 MUX + 1 XOR. Very short.
//  Four such shifts plus a 4-input XOR tree = ~2 gate levels.
//
//  TIMING
//  ───────
//  At 100 MHz on Artix-7, this comfortably closes timing.
//  The 4-wide XOR tree (4 × 128-bit) maps to ~3-4 LUT levels - minimal
//  compared to the 128-wide tree of a fully combinational multiplier.
//
//  USE THIS when:
//    - Message throughput > ~50 Mbps at 100 MHz is required
//    - You have slightly more area budget than the serial version
//
//  USE ghash_gf128_mul.sv when:
//    - Minimum LUT count matters (small devices, tight placement)
//    - Throughput < 50 Mbps is acceptable
// ============================================================================
`timescale 1ns/1ps

import aes_pkg::*;

module ghash_gf128_mul_4b (
    input  logic        clk,
    input  logic        reset,

    input  logic        start,
    input  aes_block_t  a,
    input  aes_block_t  b,

    output aes_block_t  result,
    output logic        done,
    output logic        busy
);

    localparam aes_block_t REDUCE = 128'hE100_0000_0000_0000_0000_0000_0000_0000;

    aes_block_t  v;          // current value of shifted 'a'
    aes_block_t  b_reg;      // b, consumed 4 bits per cycle from MSB
    aes_block_t  accum;
    logic [4:0]  nibble_cnt; // 0..31

    // -----------------------------------------------------------------------
    //  One GF(2^128) x-multiply step (V → V*x mod p)
    // -----------------------------------------------------------------------
    function automatic aes_block_t gf_xtime(input aes_block_t v_in);
        if (v_in[0])    // LSB = highest-degree coefficient (reflected bit order)
            return (v_in >> 1) ^ REDUCE;
        else
            return  v_in >> 1;
    endfunction

    // -----------------------------------------------------------------------
    //  Main FSM
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            busy       <= 1'b0;
            done       <= 1'b0;
            nibble_cnt <= 5'd0;
            accum      <= 128'd0;
            v          <= 128'd0;
            b_reg      <= 128'd0;
            result     <= 128'd0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                v          <= a;
                b_reg      <= b;
                accum      <= 128'd0;
                nibble_cnt <= 5'd0;
                busy       <= 1'b1;
            end else if (busy) begin
                // ── Process 4 bits of b_reg from MSB ─────────────────
                // Compute v0=v, v1=v*x, v2=v*x^2, v3=v*x^3
                // Conditionally XOR into accum based on b_reg[127:124]
                aes_block_t v0, v1, v2, v3;
                aes_block_t new_accum;
                logic [3:0] nibble;

                v0     = v;
                v1     = gf_xtime(v0);
                v2     = gf_xtime(v1);
                v3     = gf_xtime(v2);
                nibble = b_reg[127:124];

                new_accum = accum;
                if (nibble[3]) new_accum = new_accum ^ v0;
                if (nibble[2]) new_accum = new_accum ^ v1;
                if (nibble[1]) new_accum = new_accum ^ v2;
                if (nibble[0]) new_accum = new_accum ^ v3;

                accum  <= new_accum;
                v      <= gf_xtime(gf_xtime(gf_xtime(gf_xtime(v))));  // v * x^4
                b_reg  <= b_reg << 4;
                nibble_cnt <= nibble_cnt + 5'd1;

                if (nibble_cnt == 5'd31) begin
                    result <= new_accum;
                    done   <= 1'b1;
                    busy   <= 1'b0;
                end
            end
        end
    end

endmodule : ghash_gf128_mul_4b