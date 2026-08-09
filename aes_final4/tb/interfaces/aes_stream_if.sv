// ============================================================================
//  tb/interfaces/aes_stream_if.sv
//
//  Data-stream side of aes_top:
//      in_valid / in_ready / data_in
//      out_valid / out_ready / data_out
// ============================================================================
`timescale 1ns/1ps
import aes_pkg::*;

interface aes_stream_if (input logic clk, input logic reset);

    logic        in_valid;
    logic        in_ready;
    aes_block_t  data_in;

    logic        out_valid;
    logic        out_ready;
    aes_block_t  data_out;

    clocking cb_drv @(posedge clk);
        default input #1step output #1ns;
        output in_valid;
        output data_in;
        input  in_ready;
        output out_ready;
        input  out_valid;
        input  data_out;
    endclocking

    clocking cb_mon @(posedge clk);
        default input #1step;
        input in_valid;
        input in_ready;
        input data_in;
        input out_valid;
        input out_ready;
        input data_out;
    endclocking

    modport DRV (clocking cb_drv, input reset);
    modport MON (clocking cb_mon, input reset);

endinterface
