`timescale 1ns/1ps
import aes_pkg::*;

module key_system_top(

    input  logic clk,
    input  logic reset,

    input  logic push,
    input  aes_block_t key_in,

    //---------------------------------
    // pipeline feedback
    //---------------------------------

    input  logic [1:0] bank_busy,

    //---------------------------------
    // outputs
    //---------------------------------

    output rk_store_t round_keys,

    output logic [1:0] bank_valid,
    output logic [1:0] bank_free

);


//---------------------------------------------------------
// fifo signals
//---------------------------------------------------------

logic fifo_empty;
logic fifo_full;

logic fifo_pop;

aes_block_t fifo_key;


//---------------------------------------------------------
// controller signals
//---------------------------------------------------------

logic exp_start;
logic write_bank;
logic key_ready;

logic exp_done;


//---------------------------------------------------------
// expansion signals
//---------------------------------------------------------

logic w_en;
logic [3:0] waddr;
aes_block_t wkey;

logic expand_enable;


//---------------------------------------------------------
// modules
//---------------------------------------------------------

key_fifo fifo( .clk(clk), .reset(reset), .push(push), .data_in(key_in), .pop(fifo_pop),.data_out(fifo_key), .empty(fifo_empty), .full(fifo_full));

key_controller ctrl( .clk(clk), .reset(reset), .key_valid(!fifo_empty), .key_ready(fifo_pop),.bank_free(bank_free),.bank_valid(bank_valid),.exp_done(exp_done), .exp_start(exp_start),.write_bank(write_bank));

assign expand_enable = bank_free[write_bank];

AES_Key_Expansion_128 expand( .clk(clk), .reset(reset), .exp_start(exp_start),.expand_enable(expand_enable), .key_in(fifo_key), .w_en(w_en), .waddr(waddr), .wkey(wkey), .done(exp_done));

keymem_dual keymem( .clk(clk), .reset(reset), .w_en(w_en), .waddr(waddr),.wkey(wkey), .write_bank(write_bank), .bank_busy(bank_busy), .round_keys(round_keys), .bank_valid(bank_valid), .bank_free(bank_free));

endmodule