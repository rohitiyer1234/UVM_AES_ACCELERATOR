`timescale 1ns/1ps
import aes_pkg::*;

module tb_key_system;


//////////////////////////////////////////////////////////////
// CLOCK
//////////////////////////////////////////////////////////////

logic clk;
logic reset;

initial clk=0;
always #5 clk=~clk;


//////////////////////////////////////////////////////////////
// DUT SIGNALS
//////////////////////////////////////////////////////////////

logic push;
aes_block_t key_in;

logic [1:0] bank_busy;

rk_store_t round_keys;

logic [1:0] bank_valid;
logic [1:0] bank_free;



key_system_top dut(.*);



//////////////////////////////////////////////////////////////
// SCOREBOARD
//////////////////////////////////////////////////////////////

typedef struct {

    aes_block_t key;
    rk_bank_t   expected_rk;

} key_item;


key_item expected_queue[$];


int pass_cnt;
int fail_cnt;
int cycle_count;


always_ff @(posedge clk)
cycle_count++;






//////////////////////////////////////////////////////////////
// AES basic typedefs (since aes_pkg removed)
//////////////////////////////////////////////////////////////

typedef logic [127:0] aes_block_t;
typedef logic [31:0]  aes_word_t;

typedef aes_block_t rk_bank_t [0:10];
typedef rk_bank_t   rk_store_t [0:1];


//////////////////////////////////////////////////////////////
// AES helper functions for KEY EXPANSION ONLY
//////////////////////////////////////////////////////////////

function automatic aes_word_t rotword(

    input aes_word_t w

);

    return {w[23:0], w[31:24]};

endfunction



function automatic logic [7:0] sbox_byte(

    input logic [7:0] a

);

    case(a)

8'h00: sbox_byte=8'h63; 8'h01: sbox_byte=8'h7c; 8'h02: sbox_byte=8'h77; 8'h03: sbox_byte=8'h7b;
8'h04: sbox_byte=8'hf2; 8'h05: sbox_byte=8'h6b; 8'h06: sbox_byte=8'h6f; 8'h07: sbox_byte=8'hc5;
8'h08: sbox_byte=8'h30; 8'h09: sbox_byte=8'h01; 8'h0a: sbox_byte=8'h67; 8'h0b: sbox_byte=8'h2b;
8'h0c: sbox_byte=8'hfe; 8'h0d: sbox_byte=8'hd7; 8'h0e: sbox_byte=8'hab; 8'h0f: sbox_byte=8'h76;

8'h10: sbox_byte=8'hca; 8'h11: sbox_byte=8'h82; 8'h12: sbox_byte=8'hc9; 8'h13: sbox_byte=8'h7d;
8'h14: sbox_byte=8'hfa; 8'h15: sbox_byte=8'h59; 8'h16: sbox_byte=8'h47; 8'h17: sbox_byte=8'hf0;
8'h18: sbox_byte=8'had; 8'h19: sbox_byte=8'hd4; 8'h1a: sbox_byte=8'ha2; 8'h1b: sbox_byte=8'haf;
8'h1c: sbox_byte=8'h9c; 8'h1d: sbox_byte=8'ha4; 8'h1e: sbox_byte=8'h72; 8'h1f: sbox_byte=8'hc0;

8'h20: sbox_byte=8'hb7; 8'h21: sbox_byte=8'hfd; 8'h22: sbox_byte=8'h93; 8'h23: sbox_byte=8'h26;
8'h24: sbox_byte=8'h36; 8'h25: sbox_byte=8'h3f; 8'h26: sbox_byte=8'hf7; 8'h27: sbox_byte=8'hcc;
8'h28: sbox_byte=8'h34; 8'h29: sbox_byte=8'ha5; 8'h2a: sbox_byte=8'he5; 8'h2b: sbox_byte=8'hf1;
8'h2c: sbox_byte=8'h71; 8'h2d: sbox_byte=8'hd8; 8'h2e: sbox_byte=8'h31; 8'h2f: sbox_byte=8'h15;

8'h30: sbox_byte=8'h04; 8'h31: sbox_byte=8'hc7; 8'h32: sbox_byte=8'h23; 8'h33: sbox_byte=8'hc3;
8'h34: sbox_byte=8'h18; 8'h35: sbox_byte=8'h96; 8'h36: sbox_byte=8'h05; 8'h37: sbox_byte=8'h9a;
8'h38: sbox_byte=8'h07; 8'h39: sbox_byte=8'h12; 8'h3a: sbox_byte=8'h80; 8'h3b: sbox_byte=8'he2;
8'h3c: sbox_byte=8'heb; 8'h3d: sbox_byte=8'h27; 8'h3e: sbox_byte=8'hb2; 8'h3f: sbox_byte=8'h75;

8'h40: sbox_byte=8'h09; 8'h41: sbox_byte=8'h83; 8'h42: sbox_byte=8'h2c; 8'h43: sbox_byte=8'h1a;
8'h44: sbox_byte=8'h1b; 8'h45: sbox_byte=8'h6e; 8'h46: sbox_byte=8'h5a; 8'h47: sbox_byte=8'ha0;
8'h48: sbox_byte=8'h52; 8'h49: sbox_byte=8'h3b; 8'h4a: sbox_byte=8'hd6; 8'h4b: sbox_byte=8'hb3;
8'h4c: sbox_byte=8'h29; 8'h4d: sbox_byte=8'he3; 8'h4e: sbox_byte=8'h2f; 8'h4f: sbox_byte=8'h84;

8'h50: sbox_byte=8'h53; 8'h51: sbox_byte=8'hd1; 8'h52: sbox_byte=8'h00; 8'h53: sbox_byte=8'hed;
8'h54: sbox_byte=8'h20; 8'h55: sbox_byte=8'hfc; 8'h56: sbox_byte=8'hb1; 8'h57: sbox_byte=8'h5b;
8'h58: sbox_byte=8'h6a; 8'h59: sbox_byte=8'hcb; 8'h5a: sbox_byte=8'hbe; 8'h5b: sbox_byte=8'h39;
8'h5c: sbox_byte=8'h4a; 8'h5d: sbox_byte=8'h4c; 8'h5e: sbox_byte=8'h58; 8'h5f: sbox_byte=8'hcf;

8'h60: sbox_byte=8'hd0; 8'h61: sbox_byte=8'hef; 8'h62: sbox_byte=8'haa; 8'h63: sbox_byte=8'hfb;
8'h64: sbox_byte=8'h43; 8'h65: sbox_byte=8'h4d; 8'h66: sbox_byte=8'h33; 8'h67: sbox_byte=8'h85;
8'h68: sbox_byte=8'h45; 8'h69: sbox_byte=8'hf9; 8'h6a: sbox_byte=8'h02; 8'h6b: sbox_byte=8'h7f;
8'h6c: sbox_byte=8'h50; 8'h6d: sbox_byte=8'h3c; 8'h6e: sbox_byte=8'h9f; 8'h6f: sbox_byte=8'ha8;

8'h70: sbox_byte=8'h51; 8'h71: sbox_byte=8'ha3; 8'h72: sbox_byte=8'h40; 8'h73: sbox_byte=8'h8f;
8'h74: sbox_byte=8'h92; 8'h75: sbox_byte=8'h9d; 8'h76: sbox_byte=8'h38; 8'h77: sbox_byte=8'hf5;
8'h78: sbox_byte=8'hbc; 8'h79: sbox_byte=8'hb6; 8'h7a: sbox_byte=8'hda; 8'h7b: sbox_byte=8'h21;
8'h7c: sbox_byte=8'h10; 8'h7d: sbox_byte=8'hff; 8'h7e: sbox_byte=8'hf3; 8'h7f: sbox_byte=8'hd2;

8'h80: sbox_byte=8'hcd; 8'h81: sbox_byte=8'h0c; 8'h82: sbox_byte=8'h13; 8'h83: sbox_byte=8'hec;
8'h84: sbox_byte=8'h5f; 8'h85: sbox_byte=8'h97; 8'h86: sbox_byte=8'h44; 8'h87: sbox_byte=8'h17;
8'h88: sbox_byte=8'hc4; 8'h89: sbox_byte=8'ha7; 8'h8a: sbox_byte=8'h7e; 8'h8b: sbox_byte=8'h3d;
8'h8c: sbox_byte=8'h64; 8'h8d: sbox_byte=8'h5d; 8'h8e: sbox_byte=8'h19; 8'h8f: sbox_byte=8'h73;

8'h90: sbox_byte=8'h60; 8'h91: sbox_byte=8'h81; 8'h92: sbox_byte=8'h4f; 8'h93: sbox_byte=8'hdc;
8'h94: sbox_byte=8'h22; 8'h95: sbox_byte=8'h2a; 8'h96: sbox_byte=8'h90; 8'h97: sbox_byte=8'h88;
8'h98: sbox_byte=8'h46; 8'h99: sbox_byte=8'hee; 8'h9a: sbox_byte=8'hb8; 8'h9b: sbox_byte=8'h14;
8'h9c: sbox_byte=8'hde; 8'h9d: sbox_byte=8'h5e; 8'h9e: sbox_byte=8'h0b; 8'h9f: sbox_byte=8'hdb;

8'ha0: sbox_byte=8'he0; 8'ha1: sbox_byte=8'h32; 8'ha2: sbox_byte=8'h3a; 8'ha3: sbox_byte=8'h0a;
8'ha4: sbox_byte=8'h49; 8'ha5: sbox_byte=8'h06; 8'ha6: sbox_byte=8'h24; 8'ha7: sbox_byte=8'h5c;
8'ha8: sbox_byte=8'hc2; 8'ha9: sbox_byte=8'hd3; 8'haa: sbox_byte=8'hac; 8'hab: sbox_byte=8'h62;
8'hac: sbox_byte=8'h91; 8'had: sbox_byte=8'h95; 8'hae: sbox_byte=8'he4; 8'haf: sbox_byte=8'h79;

8'hb0: sbox_byte=8'he7; 8'hb1: sbox_byte=8'hc8; 8'hb2: sbox_byte=8'h37; 8'hb3: sbox_byte=8'h6d;
8'hb4: sbox_byte=8'h8d; 8'hb5: sbox_byte=8'hd5; 8'hb6: sbox_byte=8'h4e; 8'hb7: sbox_byte=8'ha9;
8'hb8: sbox_byte=8'h6c; 8'hb9: sbox_byte=8'h56; 8'hba: sbox_byte=8'hf4; 8'hbb: sbox_byte=8'hea;
8'hbc: sbox_byte=8'h65; 8'hbd: sbox_byte=8'h7a; 8'hbe: sbox_byte=8'hae; 8'hbf: sbox_byte=8'h08;

8'hc0: sbox_byte=8'hba; 8'hc1: sbox_byte=8'h78; 8'hc2: sbox_byte=8'h25; 8'hc3: sbox_byte=8'h2e;
8'hc4: sbox_byte=8'h1c; 8'hc5: sbox_byte=8'ha6; 8'hc6: sbox_byte=8'hb4; 8'hc7: sbox_byte=8'hc6;
8'hc8: sbox_byte=8'he8; 8'hc9: sbox_byte=8'hdd; 8'hca: sbox_byte=8'h74; 8'hcb: sbox_byte=8'h1f;
8'hcc: sbox_byte=8'h4b; 8'hcd: sbox_byte=8'hbd; 8'hce: sbox_byte=8'h8b; 8'hcf: sbox_byte=8'h8a;

8'hd0: sbox_byte=8'h70; 8'hd1: sbox_byte=8'h3e; 8'hd2: sbox_byte=8'hb5; 8'hd3: sbox_byte=8'h66;
8'hd4: sbox_byte=8'h48; 8'hd5: sbox_byte=8'h03; 8'hd6: sbox_byte=8'hf6; 8'hd7: sbox_byte=8'h0e;
8'hd8: sbox_byte=8'h61; 8'hd9: sbox_byte=8'h35; 8'hda: sbox_byte=8'h57; 8'hdb: sbox_byte=8'hb9;
8'hdc: sbox_byte=8'h86; 8'hdd: sbox_byte=8'hc1; 8'hde: sbox_byte=8'h1d; 8'hdf: sbox_byte=8'h9e;

8'he0: sbox_byte=8'he1; 8'he1: sbox_byte=8'hf8; 8'he2: sbox_byte=8'h98; 8'he3: sbox_byte=8'h11;
8'he4: sbox_byte=8'h69; 8'he5: sbox_byte=8'hd9; 8'he6: sbox_byte=8'h8e; 8'he7: sbox_byte=8'h94;
8'he8: sbox_byte=8'h9b; 8'he9: sbox_byte=8'h1e; 8'hea: sbox_byte=8'h87; 8'heb: sbox_byte=8'he9;
8'hec: sbox_byte=8'hce; 8'hed: sbox_byte=8'h55; 8'hee: sbox_byte=8'h28; 8'hef: sbox_byte=8'hdf;

8'hf0: sbox_byte=8'h8c; 8'hf1: sbox_byte=8'ha1; 8'hf2: sbox_byte=8'h89; 8'hf3: sbox_byte=8'h0d;
8'hf4: sbox_byte=8'hbf; 8'hf5: sbox_byte=8'he6; 8'hf6: sbox_byte=8'h42; 8'hf7: sbox_byte=8'h68;
8'hf8: sbox_byte=8'h41; 8'hf9: sbox_byte=8'h99; 8'hfa: sbox_byte=8'h2d; 8'hfb: sbox_byte=8'h0f;
8'hfc: sbox_byte=8'hb0; 8'hfd: sbox_byte=8'h54; 8'hfe: sbox_byte=8'hbb; 8'hff: sbox_byte=8'h16;

default: sbox_byte = 8'h00;

endcase

endfunction



function automatic aes_word_t subword(

    input aes_word_t w

);

    subword[31:24] = sbox_byte(w[31:24]);
    subword[23:16] = sbox_byte(w[23:16]);
    subword[15:8]  = sbox_byte(w[15:8]);
    subword[7:0]   = sbox_byte(w[7:0]);

endfunction



function automatic logic [7:0] rcon(

    input int i

);

    case(i)

        1:  rcon = 8'h01;
        2:  rcon = 8'h02;
        3:  rcon = 8'h04;
        4:  rcon = 8'h08;
        5:  rcon = 8'h10;
        6:  rcon = 8'h20;
        7:  rcon = 8'h40;
        8:  rcon = 8'h80;
        9:  rcon = 8'h1B;
        10: rcon = 8'h36;

        default: rcon = 8'h00;

    endcase

endfunction

//////////////////////////////////////////////////////////////
// REFERENCE MODEL
//////////////////////////////////////////////////////////////

function automatic rk_bank_t ref_key_expand(

    input aes_block_t key

);

    rk_bank_t rk;

    aes_word_t w0,w1,w2,w3;

    aes_word_t g;

    rk[0] = key;

    for(int r=0;r<10;r++) begin

        {w0,w1,w2,w3} = rk[r];

        g = subword(rotword(w3))
            ^ {rcon(r+1),24'h0};

        rk[r+1][127:96] = w0 ^ g;
        rk[r+1][95:64]  = w1 ^ rk[r+1][127:96];
        rk[r+1][63:32]  = w2 ^ rk[r+1][95:64];
        rk[r+1][31:0]   = w3 ^ rk[r+1][63:32];

    end

    return rk;

endfunction



//////////////////////////////////////////////////////////////
// HELPER TASK
//////////////////////////////////////////////////////////////

task automatic push_key(input aes_block_t k);

    @(negedge clk);

    push   = 1;
    key_in = k;

    @(posedge clk);

    push = 0;

endtask



//////////////////////////////////////////////////////////////
// SCOREBOARD MONITOR
//////////////////////////////////////////////////////////////

always @(posedge clk)

for(int b=0;b<2;b++)

if(bank_valid[b]) begin

    automatic key_item item;

    item = expected_queue.pop_front();

    for(int r=0;r<=10;r++)

    begin

        if(round_keys[b][r] !== item.expected_rk[r]) begin

            fail_cnt++;

            $display(
            "FAIL bank=%0d round=%0d exp=%h got=%h",
            b,
            r,
            item.expected_rk[r],
            round_keys[b][r]
            );

        end

        else

            pass_cnt++;

    end

end



//////////////////////////////////////////////////////////////
// LAYER 1 DIRECTED TEST
//////////////////////////////////////////////////////////////

task automatic test_directed();

    automatic aes_block_t key;

    key =
    128'h2b7e151628aed2a6abf7158809cf4f3c;

    expected_queue.push_back(
        '{key, ref_key_expand(key)}
    );

    push_key(key);

    repeat(40) @(posedge clk);

endtask



//////////////////////////////////////////////////////////////
// LAYER 2 CONTINUOUS STREAM
//////////////////////////////////////////////////////////////

task automatic test_stream();

    for(int i=0;i<10;i++) begin

        automatic aes_block_t key;

        key =
        128'h11110000aaaa5555 ^ i;

        expected_queue.push_back(
            '{key, ref_key_expand(key)}
        );

        push_key(key);

    end

    repeat(200) @(posedge clk);

endtask



//////////////////////////////////////////////////////////////
// LAYER 3 BANK CONFLICT
//////////////////////////////////////////////////////////////

task automatic test_bank_conflict();

    for(int i=0;i<6;i++) begin

        automatic aes_block_t key;

        key =
        128'habcdef0000000000 ^ i;

        expected_queue.push_back(
            '{key, ref_key_expand(key)}
        );

        push_key(key);

    end


    //-------------------------------------
    // simulate pipeline occupying bank0
    //-------------------------------------

    bank_busy = 2'b01;

    repeat(80) @(posedge clk);

    bank_busy = 2'b00;

endtask



//////////////////////////////////////////////////////////////
// LAYER 4 RANDOM STRESS
//////////////////////////////////////////////////////////////

task automatic test_random();

    for(int i=0;i<30;i++) begin

        automatic aes_block_t key;

        key =
        {$urandom,$urandom,$urandom,$urandom};

        expected_queue.push_back(
            '{key, ref_key_expand(key)}
        );

        push_key(key);


        //---------------------------------
        // random pipeline stalls
        //---------------------------------

        bank_busy =
        $urandom_range(0,3);

    end

    repeat(400) @(posedge clk);

endtask



//////////////////////////////////////////////////////////////
// TEST SEQUENCE
//////////////////////////////////////////////////////////////

initial begin

    reset = 1;
    push  = 0;

    bank_busy = 0;

    pass_cnt = 0;
    fail_cnt = 0;
    cycle_count = 0;

    repeat(10) @(posedge clk);

    reset = 0;



    //-------------------------------------

    test_directed();

    test_stream();

    test_bank_conflict();

    test_random();



    //-------------------------------------

    $display(
        "FINAL RESULT → PASS=%0d FAIL=%0d",
        pass_cnt,
        fail_cnt
    );

    $finish;

end


endmodule