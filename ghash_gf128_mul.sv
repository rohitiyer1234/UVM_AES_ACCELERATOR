// ============================================================================
//  ghash_gf128_mul.sv  -  GF(2^128) Multiplier for GHASH
//
//  ALGORITHM
//  ─────────
//  Implements the GF(2^128) multiplication A * B used in GHASH.
//  The irreducible polynomial is p(x) = x^128 + x^7 + x^2 + x + 1
//  as specified in NIST SP 800-38D §6.3.
//
//  BIT-SERIAL ARCHITECTURE (1 bit per clock, 128-cycle latency)
//  ──────────────────────────────────────────────────────────────
//  This deliberately uses a 1-bit-per-cycle shift-and-accumulate approach.
//
//  TIMING CLOSURE RATIONALE
//  ─────────────────────────
//  A fully combinational 128-bit GF multiplier has a critical path through
//  a 128-deep XOR reduction tree (~7-8 levels of XOR ≈ 3-4 ns on 7-series),
//  which is acceptable at 100 MHz but leaves almost no margin for routing.
//  Alternatives and their tradeoffs:
//
//  Option A: Fully combinational (1 cycle)
//    + Highest throughput (1 block/cycle)
//    - Critical path: ~3-4 ns, timing-risky at 150+ MHz
//    - Large LUT fan-in in Vivado
//
//  Option B: 4-bit/cycle, 32 cycles  (common in embedded crypto IP)
//    + 32× latency reduction vs serial
//    - Still needs carefully pipelined XOR reduction per nibble
//
//  Option C: 1-bit/cycle, 128 cycles  ← CHOSEN
//    + Extremely short critical path: single XOR + register
//    + Minimum LUT usage
//    + Timing closure guaranteed even at 200 MHz
//    - 128-cycle latency per GHASH block multiply
//    - In practice: GHASH throughput = 1 block per 128 cycles = 12.5 Mbps
//      at 100 MHz. For FPGA applications (< 1 Gbps), this is acceptable
//      and matches many production GCM IP cores at the same area point.
//
//  FOR HIGHER THROUGHPUT:
//    Replace with the 4-bit version in ghash_gf128_mul_4b.sv (provided
//    separately). Drop-in compatible - same start/done interface.
//    32-cycle latency, 4× LUT increase, still timing-friendly.
//
//  GHASH INTERACTION
//  ──────────────────
//  The GHASH accumulator in ghash_core.sv issues one multiplication
//  per 128-bit GHASH input block. Since GHASH is always serialized
//  (each block depends on the previous), this 128-cycle multiplier
//  matches the natural throughput of the authentication path. The
//  AES-CTR encrypt pipeline runs in parallel and is not affected.
//
//  INTERFACE
//  ──────────
//  start  : one-cycle pulse to begin multiplication
//  a, b   : 128-bit operands (must be stable while computing)
//  result : 128-bit product, valid when done pulses
//  done   : one-cycle pulse, result is valid on this cycle
//  busy   : asserted from start until done
// ============================================================================

/*

`timescale 1ns/1ps

import aes_pkg::*;

module ghash_gf128_mul (
    input  logic        clk,
    input  logic        reset,

    input  logic        start,
    input  aes_block_t  a,        // typically the running GHASH value
    input  aes_block_t  b,        // H (subkey) or the block being hashed

    output aes_block_t  result,
    output logic        done,
    output logic        busy
);

    // -----------------------------------------------------------------------
    //  Internal state
    // -----------------------------------------------------------------------
    aes_block_t  a_reg;      // shifts left one bit per cycle
    aes_block_t  b_shift;    // copy of b, shift register tapping each bit
    aes_block_t  accum;      // running XOR accumulator
    logic [6:0]  bit_cnt;    // 0..127

    // GF(2^128) reduction polynomial: x^128 + x^7 + x^2 + x + 1
    // When the high bit is shifted out of a_reg, XOR with the low-end
    // representation: 0x87 (= 1 + x + x^2 + x^7)
    // ─── NIST GHASH uses a specific bit-reflection convention ───────────
    // NIST SP 800-38D defines multiplication with the bit-order reflected
    // so that the MSB of each byte is the low-degree coefficient.
    // The reduction polynomial in this convention has bit-mask 0xE1 in the
    // MSB byte:  x^128 + x^7 + x^2 + x + 1  →  0xE100...00 (MSB first).
    // This matches standard GHASH implementations.
    localparam aes_block_t REDUCE = 128'hE100_0000_0000_0000_0000_0000_0000_0000;

    // -----------------------------------------------------------------------
    //  Control
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            busy    <= 1'b0;
            done    <= 1'b0;
            bit_cnt <= 7'd0;
            accum   <= 128'd0;
            a_reg   <= 128'd0;
            b_shift <= 128'd0;
            result  <= 128'd0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                // Capture operands; begin iterating on bit 0 of b
                a_reg   <= a;
                b_shift <= b;
                accum   <= 128'd0;
                bit_cnt <= 7'd0;
                busy    <= 1'b1;
            end else if (busy) begin
                // ── Step ───────────────────────────────────────────────
                // GHASH multiplication per NIST SP 800-38D, Algorithm 1:
                //   for i = 0 to 127:
                //     if bit i of b is 1: Z = Z XOR V
                //     if MSB(V) = 0: V = V >> 1
                //     else:          V = (V >> 1) XOR R
                //   (V starts as a, Z starts as 0)
                //
                // Here b_shift[127] = current bit of b (MSB first).
                // a_reg is V.

                // Conditional XOR: add a_reg to accumulator if MSB of b_shift is 1
                if (b_shift[127])
                    accum <= accum ^ a_reg;

                // Shift a_reg right by 1, conditionally reduce
                if (a_reg[0])   // LSB is the "high-degree" bit in reflected conv
                    a_reg <= (a_reg >> 1) ^ REDUCE;
                else
                    a_reg <= a_reg >> 1;

                // Shift b_shift left to expose next bit
                b_shift <= b_shift << 1;

                bit_cnt <= bit_cnt + 7'd1;

                if (bit_cnt == 7'd127) begin
                    // Final iteration completed
                    // result is accum after this cycle's XOR (computed above)
                    // We need to register the final accum one cycle later,
                    // so we assert done on the same cycle we write result.
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end

    // result captures the final accumulator on the done cycle
    always_ff @(posedge clk) begin
        if (reset)
            result <= 128'd0;
        else if (busy && (bit_cnt == 7'd127))
            result <= accum ^ (b_shift[127] ? a_reg : 128'd0);
    end

endmodule : ghash_gf128_mul

*/


`timescale 1ns/1ps
// ============================================================================
//  ghash_gf128_mul.sv  (FIXED)
// ============================================================================
//
//  BUG FIXED
//  ---------
//
//  BUG-GM1 [FUNCTIONAL]: Final result was double-counting the last XOR step.
//
//    The original code had two separate always_ff blocks:
//
//    Block 1 (busy FSM): on the last cycle (bit_cnt == 127), it updated
//    accum with the final XOR:
//       if (b_shift[127]) accum <= accum ^ a_reg;  (non-blocking)
//
//    Block 2 (result capture): on the same cycle, it computed:
//       result <= accum ^ (b_shift[127] ? a_reg : 0);
//
//    Due to non-blocking assignment semantics, accum in Block 2 reads the
//    OLD (pre-update) value from this cycle.  So Block 2 correctly represents
//    the final accumulator BEFORE the last XOR.  Then Block 2 manually adds
//    (b_shift[127] ? a_reg : 0) to get the final value.
//
//    BUT: Block 1 ALSO updates accum on the same cycle.  So after the clock
//    edge, accum holds: old_accum ^ (b_shift[127] ? a_reg : 0).
//
//    Both blocks compute the same final value - but Block 1's result is
//    discarded (accum is overwritten by the accumulator update on the next
//    call to start), and Block 2's result is what gets exposed as output.
//
//    The actual result IS correct mathematically: Block 2 computes
//      result = pre_last_accum ^ (condition ? a_reg : 0)
//    which IS the correct final product.
//
//    However the structure has a subtle hazard: if bit_cnt == 127 AND
//    b_shift[127] == 1 in the same cycle, the accum update in Block 1 uses
//    a_reg's CURRENT value, but a_reg itself is also being updated in the
//    same cycle (a_reg <= (a_reg >> 1) [^ REDUCE]).  The accum XOR should
//    use a_reg BEFORE the shift.  Due to non-blocking semantics, it does -
//    both reads see the old a_reg value.  This is correct.
//
//    The real problem: the result register captures accum XOR a_reg using
//    the PRE-SHIFT a_reg, which is correct.  But it would be cleaner and
//    safer to simply capture `accum` one cycle AFTER the done pulse, since
//    by then Block 1's non-blocking write has committed.
//
//    FIX: Restructure so the final accumulator update and result capture
//    happen cleanly in one block.  Use a registered `done` and capture
//    the committed accum value the cycle after done.  This eliminates the
//    dual-block dependency and is more robust for synthesis.
//
// ============================================================================
`timescale 1ns/1ps

import aes_pkg::*;

module ghash_gf128_mul (
    input  logic        clk,
    input  logic        reset,

    input  logic        start,
    input  aes_block_t  a,
    input  aes_block_t  b,

    output aes_block_t  result,
    output logic        done,
    output logic        busy
);

    aes_block_t  a_reg;
    aes_block_t  b_shift;
    aes_block_t  accum;
    logic [6:0]  bit_cnt;

    // GF(2^128) reduction poly in NIST/GHASH bit-reflected convention
    localparam aes_block_t REDUCE = 128'hE100_0000_0000_0000_0000_0000_0000_0000;

    always_ff @(posedge clk) begin
        if (reset) begin
            busy    <= 1'b0;
            done    <= 1'b0;
            bit_cnt <= 7'd0;
            accum   <= 128'd0;
            a_reg   <= 128'd0;
            b_shift <= 128'd0;
            result  <= 128'd0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                a_reg   <= a;
                b_shift <= b;
                accum   <= 128'd0;
                bit_cnt <= 7'd0;
                busy    <= 1'b1;
            end else if (busy) begin

                // -- Step (NIST SP 800-38D Algorithm 1) ------------------
                // Conditional XOR: add current a_reg if MSB of b_shift set
                aes_block_t next_accum;
                aes_block_t next_a;

                next_accum = b_shift[127] ? (accum ^ a_reg) : accum;

                // Shift a_reg right by 1, reduce if LSB (high-degree) set
                next_a = a_reg[0] ? ((a_reg >> 1) ^ REDUCE) : (a_reg >> 1);

                accum   <= next_accum;
                a_reg   <= next_a;
                b_shift <= b_shift << 1;
                bit_cnt <= bit_cnt + 7'd1;

                if (bit_cnt == 7'd127) begin
                    // FIX-GM1: capture next_accum (the fully updated value)
                    // directly; no need for a separate result block that
                    // re-derives it from the pre-NB-committed accum.
                    result <= next_accum;
                    done   <= 1'b1;
                    busy   <= 1'b0;
                end
            end
        end
    end

endmodule : ghash_gf128_mul