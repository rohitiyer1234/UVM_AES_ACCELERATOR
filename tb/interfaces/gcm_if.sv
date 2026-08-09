// ============================================================================
//  tb/interfaces/gcm_if.sv
//
//  GCM side of aes_top: gcm_iv, AAD stream, payload_last strobe and tag.
// ============================================================================
`timescale 1ns/1ps
import aes_pkg::*;

interface gcm_if (input logic clk, input logic reset);

    logic [95:0] gcm_iv;
    logic        aad_valid;
    logic        aad_ready;
    aes_block_t  aad_data;
    logic        aad_last;
    logic        payload_last;

    logic        tag_valid;
    aes_block_t  tag_out;
    aes_block_t  expected_tag;
    logic        tag_match;

    clocking cb_drv @(posedge clk);
        default input #1step output #1ns;
        output gcm_iv;
        output aad_valid;
        output aad_data;
        output aad_last;
        output payload_last;
        output expected_tag;
        input  aad_ready;
        input  tag_valid;
        input  tag_out;
        input  tag_match;
    endclocking

    clocking cb_mon @(posedge clk);
        default input #1step;
        input gcm_iv;
        input aad_valid;
        input aad_ready;
        input aad_data;
        input aad_last;
        input payload_last;
        input tag_valid;
        input tag_out;
        input expected_tag;
        input tag_match;
    endclocking

    modport DRV (clocking cb_drv, input reset);
    modport MON (clocking cb_mon, input reset);

endinterface
