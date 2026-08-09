// ============================================================================
//  tb/interfaces/aes_ctrl_if.sv
//
//  Control side of aes_top: mode/enc_dec/iv_load/iv_in.
//  Reset is driven from tb_top (so it can be shared with every interface)
//  but exposed here for monitor convenience.
// ============================================================================
`timescale 1ns/1ps
import aes_pkg::*;

interface aes_ctrl_if (input logic clk, input logic reset);

    aes_mode_e   mode;
    logic        enc_dec;
    logic        iv_load;
    aes_block_t  iv_in;
    logic        busy;

    // ---------------------------------------------------------------
    // Synchronous sampling for monitors (post-edge)
    // Driving happens from the driver via the master clocking block.
    // ---------------------------------------------------------------
    clocking cb_drv @(posedge clk);
        default input #1step output #1ns;
        output mode;
        output enc_dec;
        output iv_load;
        output iv_in;
        input  busy;
    endclocking

    clocking cb_mon @(posedge clk);
        default input #1step;
        input mode;
        input enc_dec;
        input iv_load;
        input iv_in;
        input busy;
    endclocking

    modport DRV (clocking cb_drv, input reset);
    modport MON (clocking cb_mon, input reset);

endinterface
