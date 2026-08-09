// ============================================================================
//  tb/interfaces/key_if.sv
//
//  Key system side of aes_top: key_push / key_data plus the debug bank
//  status outputs that the monitor uses to track bank state.
// ============================================================================
`timescale 1ns/1ps
import aes_pkg::*;

interface key_if (input logic clk, input logic reset);

    logic        key_push;
    aes_block_t  key_data;

    logic [1:0]  bank_valid;
    logic [1:0]  bank_busy;
    logic [1:0]  bank_free;

    clocking cb_drv @(posedge clk);
        default input #1step output #1ns;
        output key_push;
        output key_data;
        input  bank_valid;
        input  bank_busy;
        input  bank_free;
    endclocking

    clocking cb_mon @(posedge clk);
        default input #1step;
        input key_push;
        input key_data;
        input bank_valid;
        input bank_busy;
        input bank_free;
    endclocking

    modport DRV (clocking cb_drv, input reset);
    modport MON (clocking cb_mon, input reset);

endinterface
