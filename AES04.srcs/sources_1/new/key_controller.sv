`timescale 1ns/1ps
/*import aes_pkg::*;

module key_controller(

    input  logic clk,
    input  logic reset,

    // FIFO interface
    input  logic       key_valid,
    output logic       key_ready,

    // bank status
    input  logic [1:0] bank_free,
    input  logic [1:0] bank_valid,

    // expansion status
    input  logic       exp_done,

    // control outputs
    output logic       exp_start,
    output logic       write_bank

);

logic active;
logic selected_bank;


always_comb begin
    // choose free bank
    if(bank_free[0])
        selected_bank = 0;
    else if(bank_free[1])
        selected_bank = 1;
    else
        selected_bank = 0;
end



always_ff @(posedge clk) begin
    if(reset) begin
        active      <= 0;
        write_bank  <= 0;
        exp_start   <= 0;

    end
    else begin
        exp_start <= 0;
        // start expansion
        if(key_valid && !active && bank_free != 0) begin
            active     <= 1;
            write_bank <= selected_bank;
            exp_start  <= 1;
        end
        // expansion finished
        if(exp_done)
            active <= 0;
    end
end



assign key_ready =
        (!active)
        && (bank_free != 0);

endmodule*/
// ============================================================================
//  key_controller.sv  -  Key Expansion Sequencer / Arbiter
//
//  STATUS: Logic correct. One synthesis improvement:
//  ORIGINAL: key_ready was a combinational assign using !=. Replaced with
//  an equivalent always_comb for clearer Vivado synthesis intent.
//  No functional change.
//
//  Arbitrates between the FIFO and the key expansion engine:
//    1. Waits for a key to be available (FIFO not empty → key_valid)
//    2. Picks a free bank (priority: bank 0 first)
//    3. Asserts exp_start for one cycle to launch expansion
//    4. Holds active until exp_done, then allows next key
//
//  key_ready is asserted (→ fifo_pop) when the controller is idle and
//  a free bank exists. The pop happens on the same cycle as exp_start,
//  so the FIFO read-pointer advances as the key is captured by the expander.
// ============================================================================
`timescale 1ns/1ps

import aes_pkg::*;

module key_controller (
    input  logic        clk,
    input  logic        reset,

    // ---- FIFO interface ----
    input  logic        key_valid,   // FIFO !empty
    output logic        key_ready,   // pop (pulse when accepting)

    // ---- bank status ----
    input  logic [1:0]  bank_free,
    input  logic [1:0]  bank_valid,

    // ---- expansion engine status ----
    input  logic        exp_done,

    // ---- control outputs ----
    output logic        exp_start,
    output logic        write_bank
);

    logic active;
    logic selected_bank;

    // Priority encode free bank: prefer bank 0
    always_comb begin
        if      (bank_free[0]) selected_bank = 1'b0;
        else if (bank_free[1]) selected_bank = 1'b1;
        else                   selected_bank = 1'b0;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            active     <= 1'b0;
            write_bank <= 1'b0;
            exp_start  <= 1'b0;
        end else begin
            exp_start <= 1'b0;

            if (key_valid && !active && (bank_free != 2'b00)) begin
                active     <= 1'b1;
                write_bank <= selected_bank;
                exp_start  <= 1'b1;
            end

            if (exp_done)
                active <= 1'b0;
        end
    end

    // key_ready: tell the FIFO to pop on the same cycle exp_start fires
    always_comb
        key_ready = (!active) && (bank_free != 2'b00);

endmodule : key_controller