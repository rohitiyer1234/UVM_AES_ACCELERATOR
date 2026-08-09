`timescale 1ns/1ps
import aes_pkg::*;


// ============================================================
// AES reference model aligned with RTL byte ordering
// ============================================================

function automatic logic [7:0] xtime(input logic [7:0] a);
    xtime = {a[6:0],1'b0} ^ (8'h1B & {8{a[7]}});
endfunction


function automatic logic [7:0] mul2(input logic [7:0] a);
    return xtime(a);
endfunction


function automatic logic [7:0] mul3(input logic [7:0] a);
    return xtime(a) ^ a;
endfunction


//-------------------------------------------------------------
// Behavioral SBOX (for golden reference only)
//-------------------------------------------------------------
function automatic logic [7:0] sbox_byte(input logic [7:0] a);

    case(a)

        8'h00: sbox_byte = 8'h63; 8'h01: sbox_byte = 8'h7c; 8'h02: sbox_byte = 8'h77; 8'h03: sbox_byte = 8'h7b;
        8'h04: sbox_byte = 8'hf2; 8'h05: sbox_byte = 8'h6b; 8'h06: sbox_byte = 8'h6f; 8'h07: sbox_byte = 8'hc5;
        8'h08: sbox_byte = 8'h30; 8'h09: sbox_byte = 8'h01; 8'h0a: sbox_byte = 8'h67; 8'h0b: sbox_byte = 8'h2b;
        8'h0c: sbox_byte = 8'hfe; 8'h0d: sbox_byte = 8'hd7; 8'h0e: sbox_byte = 8'hab; 8'h0f: sbox_byte = 8'h76;

        8'h10: sbox_byte = 8'hca; 8'h11: sbox_byte = 8'h82; 8'h12: sbox_byte = 8'hc9; 8'h13: sbox_byte = 8'h7d;
        8'h14: sbox_byte = 8'hfa; 8'h15: sbox_byte = 8'h59; 8'h16: sbox_byte = 8'h47; 8'h17: sbox_byte = 8'hf0;
        8'h18: sbox_byte = 8'had; 8'h19: sbox_byte = 8'hd4; 8'h1a: sbox_byte = 8'ha2; 8'h1b: sbox_byte = 8'haf;
        8'h1c: sbox_byte = 8'h9c; 8'h1d: sbox_byte = 8'ha4; 8'h1e: sbox_byte = 8'h72; 8'h1f: sbox_byte = 8'hc0;

        8'h20: sbox_byte = 8'hb7; 8'h21: sbox_byte = 8'hfd; 8'h22: sbox_byte = 8'h93; 8'h23: sbox_byte = 8'h26;
        8'h24: sbox_byte = 8'h36; 8'h25: sbox_byte = 8'h3f; 8'h26: sbox_byte = 8'hf7; 8'h27: sbox_byte = 8'hcc;
        8'h28: sbox_byte = 8'h34; 8'h29: sbox_byte = 8'ha5; 8'h2a: sbox_byte = 8'he5; 8'h2b: sbox_byte = 8'hf1;
        8'h2c: sbox_byte = 8'h71; 8'h2d: sbox_byte = 8'hd8; 8'h2e: sbox_byte = 8'h31; 8'h2f: sbox_byte = 8'h15;

        8'h30: sbox_byte = 8'h04; 8'h31: sbox_byte = 8'hc7; 8'h32: sbox_byte = 8'h23; 8'h33: sbox_byte = 8'hc3;
        8'h34: sbox_byte = 8'h18; 8'h35: sbox_byte = 8'h96; 8'h36: sbox_byte = 8'h05; 8'h37: sbox_byte = 8'h9a;
        8'h38: sbox_byte = 8'h07; 8'h39: sbox_byte = 8'h12; 8'h3a: sbox_byte = 8'h80; 8'h3b: sbox_byte = 8'he2;
        8'h3c: sbox_byte = 8'heb; 8'h3d: sbox_byte = 8'h27; 8'h3e: sbox_byte = 8'hb2; 8'h3f: sbox_byte = 8'h75;

        8'h40: sbox_byte = 8'h09; 8'h41: sbox_byte = 8'h83; 8'h42: sbox_byte = 8'h2c; 8'h43: sbox_byte = 8'h1a;
        8'h44: sbox_byte = 8'h1b; 8'h45: sbox_byte = 8'h6e; 8'h46: sbox_byte = 8'h5a; 8'h47: sbox_byte = 8'ha0;
        8'h48: sbox_byte = 8'h52; 8'h49: sbox_byte = 8'h3b; 8'h4a: sbox_byte = 8'hd6; 8'h4b: sbox_byte = 8'hb3;
        8'h4c: sbox_byte = 8'h29; 8'h4d: sbox_byte = 8'he3; 8'h4e: sbox_byte = 8'h2f; 8'h4f: sbox_byte = 8'h84;

        8'h50: sbox_byte = 8'h53; 8'h51: sbox_byte = 8'hd1; 8'h52: sbox_byte = 8'h00; 8'h53: sbox_byte = 8'hed;
        8'h54: sbox_byte = 8'h20; 8'h55: sbox_byte = 8'hfc; 8'h56: sbox_byte = 8'hb1; 8'h57: sbox_byte = 8'h5b;
        8'h58: sbox_byte = 8'h6a; 8'h59: sbox_byte = 8'hcb; 8'h5a: sbox_byte = 8'hbe; 8'h5b: sbox_byte = 8'h39;
        8'h5c: sbox_byte = 8'h4a; 8'h5d: sbox_byte = 8'h4c; 8'h5e: sbox_byte = 8'h58; 8'h5f: sbox_byte = 8'hcf;

        8'h60: sbox_byte = 8'hd0; 8'h61: sbox_byte = 8'hef; 8'h62: sbox_byte = 8'haa; 8'h63: sbox_byte = 8'hfb;
        8'h64: sbox_byte = 8'h43; 8'h65: sbox_byte = 8'h4d; 8'h66: sbox_byte = 8'h33; 8'h67: sbox_byte = 8'h85;
        8'h68: sbox_byte = 8'h45; 8'h69: sbox_byte = 8'hf9; 8'h6a: sbox_byte = 8'h02; 8'h6b: sbox_byte = 8'h7f;
        8'h6c: sbox_byte = 8'h50; 8'h6d: sbox_byte = 8'h3c; 8'h6e: sbox_byte = 8'h9f; 8'h6f: sbox_byte = 8'ha8;

        8'h70: sbox_byte = 8'h51; 8'h71: sbox_byte = 8'ha3; 8'h72: sbox_byte = 8'h40; 8'h73: sbox_byte = 8'h8f;
        8'h74: sbox_byte = 8'h92; 8'h75: sbox_byte = 8'h9d; 8'h76: sbox_byte = 8'h38; 8'h77: sbox_byte = 8'hf5;
        8'h78: sbox_byte = 8'hbc; 8'h79: sbox_byte = 8'hb6; 8'h7a: sbox_byte = 8'hda; 8'h7b: sbox_byte = 8'h21;
        8'h7c: sbox_byte = 8'h10; 8'h7d: sbox_byte = 8'hff; 8'h7e: sbox_byte = 8'hf3; 8'h7f: sbox_byte = 8'hd2;

        8'h80: sbox_byte = 8'hcd; 8'h81: sbox_byte = 8'h0c; 8'h82: sbox_byte = 8'h13; 8'h83: sbox_byte = 8'hec;
        8'h84: sbox_byte = 8'h5f; 8'h85: sbox_byte = 8'h97; 8'h86: sbox_byte = 8'h44; 8'h87: sbox_byte = 8'h17;
        8'h88: sbox_byte = 8'hc4; 8'h89: sbox_byte = 8'ha7; 8'h8a: sbox_byte = 8'h7e; 8'h8b: sbox_byte = 8'h3d;
        8'h8c: sbox_byte = 8'h64; 8'h8d: sbox_byte = 8'h5d; 8'h8e: sbox_byte = 8'h19; 8'h8f: sbox_byte = 8'h73;

        8'h90: sbox_byte = 8'h60; 8'h91: sbox_byte = 8'h81; 8'h92: sbox_byte = 8'h4f; 8'h93: sbox_byte = 8'hdc;
        8'h94: sbox_byte = 8'h22; 8'h95: sbox_byte = 8'h2a; 8'h96: sbox_byte = 8'h90; 8'h97: sbox_byte = 8'h88;
        8'h98: sbox_byte = 8'h46; 8'h99: sbox_byte = 8'hee; 8'h9a: sbox_byte = 8'hb8; 8'h9b: sbox_byte = 8'h14;
        8'h9c: sbox_byte = 8'hde; 8'h9d: sbox_byte = 8'h5e; 8'h9e: sbox_byte = 8'h0b; 8'h9f: sbox_byte = 8'hdb;

        8'ha0: sbox_byte = 8'he0; 8'ha1: sbox_byte = 8'h32; 8'ha2: sbox_byte = 8'h3a; 8'ha3: sbox_byte = 8'h0a;
        8'ha4: sbox_byte = 8'h49; 8'ha5: sbox_byte = 8'h06; 8'ha6: sbox_byte = 8'h24; 8'ha7: sbox_byte = 8'h5c;
        8'ha8: sbox_byte = 8'hc2; 8'ha9: sbox_byte = 8'hd3; 8'haa: sbox_byte = 8'hac; 8'hab: sbox_byte = 8'h62;
        8'hac: sbox_byte = 8'h91; 8'had: sbox_byte = 8'h95; 8'hae: sbox_byte = 8'he4; 8'haf: sbox_byte = 8'h79;

        8'hb0: sbox_byte = 8'he7; 8'hb1: sbox_byte = 8'hc8; 8'hb2: sbox_byte = 8'h37; 8'hb3: sbox_byte = 8'h6d;
        8'hb4: sbox_byte = 8'h8d; 8'hb5: sbox_byte = 8'hd5; 8'hb6: sbox_byte = 8'h4e; 8'hb7: sbox_byte = 8'ha9;
        8'hb8: sbox_byte = 8'h6c; 8'hb9: sbox_byte = 8'h56; 8'hba: sbox_byte = 8'hf4; 8'hbb: sbox_byte = 8'hea;
        8'hbc: sbox_byte = 8'h65; 8'hbd: sbox_byte = 8'h7a; 8'hbe: sbox_byte = 8'hae; 8'hbf: sbox_byte = 8'h08;

        8'hc0: sbox_byte = 8'hba; 8'hc1: sbox_byte = 8'h78; 8'hc2: sbox_byte = 8'h25; 8'hc3: sbox_byte = 8'h2e;
        8'hc4: sbox_byte = 8'h1c; 8'hc5: sbox_byte = 8'ha6; 8'hc6: sbox_byte = 8'hb4; 8'hc7: sbox_byte = 8'hc6;
        8'hc8: sbox_byte = 8'he8; 8'hc9: sbox_byte = 8'hdd; 8'hca: sbox_byte = 8'h74; 8'hcb: sbox_byte = 8'h1f;
        8'hcc: sbox_byte = 8'h4b; 8'hcd: sbox_byte = 8'hbd; 8'hce: sbox_byte = 8'h8b; 8'hcf: sbox_byte = 8'h8a;

        8'hd0: sbox_byte = 8'h70; 8'hd1: sbox_byte = 8'h3e; 8'hd2: sbox_byte = 8'hb5; 8'hd3: sbox_byte = 8'h66;
        8'hd4: sbox_byte = 8'h48; 8'hd5: sbox_byte = 8'h03; 8'hd6: sbox_byte = 8'hf6; 8'hd7: sbox_byte = 8'h0e;
        8'hd8: sbox_byte = 8'h61; 8'hd9: sbox_byte = 8'h35; 8'hda: sbox_byte = 8'h57; 8'hdb: sbox_byte = 8'hb9;
        8'hdc: sbox_byte = 8'h86; 8'hdd: sbox_byte = 8'hc1; 8'hde: sbox_byte = 8'h1d; 8'hdf: sbox_byte = 8'h9e;

        8'he0: sbox_byte = 8'he1; 8'he1: sbox_byte = 8'hf8; 8'he2: sbox_byte = 8'h98; 8'he3: sbox_byte = 8'h11;
        8'he4: sbox_byte = 8'h69; 8'he5: sbox_byte = 8'hd9; 8'he6: sbox_byte = 8'h8e; 8'he7: sbox_byte = 8'h94;
        8'he8: sbox_byte = 8'h9b; 8'he9: sbox_byte = 8'h1e; 8'hea: sbox_byte = 8'h87; 8'heb: sbox_byte = 8'he9;
        8'hec: sbox_byte = 8'hce; 8'hed: sbox_byte = 8'h55; 8'hee: sbox_byte = 8'h28; 8'hef: sbox_byte = 8'hdf;

        8'hf0: sbox_byte = 8'h8c; 8'hf1: sbox_byte = 8'ha1; 8'hf2: sbox_byte = 8'h89; 8'hf3: sbox_byte = 8'h0d;
        8'hf4: sbox_byte = 8'hbf; 8'hf5: sbox_byte = 8'he6; 8'hf6: sbox_byte = 8'h42; 8'hf7: sbox_byte = 8'h68;
        8'hf8: sbox_byte = 8'h41; 8'hf9: sbox_byte = 8'h99; 8'hfa: sbox_byte = 8'h2d; 8'hfb: sbox_byte = 8'h0f;
        8'hfc: sbox_byte = 8'hb0; 8'hfd: sbox_byte = 8'h54; 8'hfe: sbox_byte = 8'hbb; 8'hff: sbox_byte = 8'h16;

        default: sbox_byte = 8'h00;

    endcase

endfunction


//-------------------------------------------------------------
// Reference SubBytes
//-------------------------------------------------------------

function automatic aes_block_t ref_subbytes(aes_block_t s);

    for(int i=0;i<16;i++)
        s[127-8*i -:8] = sbox_byte(
            s[127-8*i -:8]
        );

    return s;

endfunction


//-------------------------------------------------------------
// Reference ShiftRows (matches ShiftRows.sv)
//-------------------------------------------------------------

function automatic aes_block_t ref_shiftrows(aes_block_t s);

    logic [7:0] b[15:0];

    {
        b[0],  b[1],  b[2],  b[3],
        b[4],  b[5],  b[6],  b[7],
        b[8],  b[9],  b[10], b[11],
        b[12], b[13], b[14], b[15]
    } = s;

    return {

        b[0],  b[5],  b[10], b[15],
        b[4],  b[9],  b[14], b[3],
        b[8],  b[13], b[2],  b[7],
        b[12], b[1],  b[6],  b[11]

    };

endfunction


//-------------------------------------------------------------
// Reference MixColumns (matches MixColumns.sv)
//-------------------------------------------------------------

function automatic aes_block_t ref_mixcolumns(aes_block_t s);

    for(int i=0;i<4;i++) begin

        logic [7:0] s0,s1,s2,s3;

        s0 = s[127-32*i -:8];
        s1 = s[119-32*i -:8];
        s2 = s[111-32*i -:8];
        s3 = s[103-32*i -:8];

        s[127-32*i -:8] = mul2(s0)^mul3(s1)^s2^s3;
        s[119-32*i -:8] = s0^mul2(s1)^mul3(s2)^s3;
        s[111-32*i -:8] = s0^s1^mul2(s2)^mul3(s3);
        s[103-32*i -:8] = mul3(s0)^s1^s2^mul2(s3);

    end

    return s;

endfunction


//-------------------------------------------------------------
// Full AES reference encryption
//-------------------------------------------------------------

function automatic aes_block_t ref_aes_enc(

    input aes_block_t pt,
    input rk_bank_t   rk

);

    aes_block_t st;

    st = pt ^ rk[0];

    for(int r=1;r<=10;r++) begin

        st = ref_subbytes(st);
        st = ref_shiftrows(st);

        if(r<10)
            st = ref_mixcolumns(st);

        st ^= rk[r];

    end

    return st;

endfunction



// ============================================================
// TESTBENCH
// ============================================================

module tb_encrypt_pipe03;


    //---------------------------------------------------------
    // signals
    //---------------------------------------------------------

    logic clk;
    logic reset;

    logic in_valid;
    logic in_ready;

    aes_block_t plaintext;
    logic current_bank;

    rk_store_t round_keys;

    aes_block_t ciphertext;

    logic out_valid;
    logic out_ready;

    logic [1:0] bank_busy;



    //---------------------------------------------------------
    // DUT
    //---------------------------------------------------------

    AES_Encrypt_Pipe03 dut (.*);



    //---------------------------------------------------------
    // clock
    //---------------------------------------------------------

    initial clk = 0;
    always #5 clk = ~clk;



    //---------------------------------------------------------
    // scoreboard tracking
    //---------------------------------------------------------

    aes_block_t exp_queue[$];

    int input_cycle[$];

    int latency[$];

    int cycle_cnt;

    int pass_cnt;
    int fail_cnt;



    always_ff @(posedge clk)
        cycle_cnt++;



    //---------------------------------------------------------
    // load known AES key schedule
    //---------------------------------------------------------

    task load_nist_keys();

        round_keys[0][0]  = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        round_keys[0][1]  = 128'ha0fafe1788542cb123a339392a6c7605;
        round_keys[0][2]  = 128'hf2c295f27a96b9435935807a7359f67f;
        round_keys[0][3]  = 128'h3d80477d4716fe3e1e237e446d7a883b;
        round_keys[0][4]  = 128'hef44a541a8525b7fb671253bdb0bad00;
        round_keys[0][5]  = 128'hd4d1c6f87c839d87caf2b8bc11f915bc;
        round_keys[0][6]  = 128'h6d88a37a110b3efddbf98641ca0093fd;
        round_keys[0][7]  = 128'h4e54f70e5f5fc9f384a64fb24ea6dc4f;
        round_keys[0][8]  = 128'head27321b58dbad2312bf5607f8d292f;
        round_keys[0][9]  = 128'hac7766f319fadc2128d12941575c006e;
        round_keys[0][10] = 128'hd014f9a8c9ee2589e13f0cc8b6630ca6;


        // dummy key set for bank1

        for(int i=0;i<=10;i++)
            round_keys[1][i] =
                128'hdeadbeefdeadbeefdeadbeefdeadbeef ^ i;

    endtask



    //---------------------------------------------------------
    // stimulus helper
    //---------------------------------------------------------

    task send_block(

        input aes_block_t pt,
        input logic       bk

    );

        @(negedge clk);

        in_valid     = 1;
        plaintext    = pt;
        current_bank = bk;

        @(posedge clk);

        if(in_ready) begin

            exp_queue.push_back(
                ref_aes_enc(pt, round_keys[bk])
            );

            input_cycle.push_back(cycle_cnt);

        end

        @(negedge clk);

        in_valid = 0;

    endtask



    //---------------------------------------------------------
    // output monitor
    //---------------------------------------------------------

    always @(posedge clk)

    if(out_valid && out_ready)

    begin

        aes_block_t exp =
            exp_queue.pop_front();

        int lat =
            cycle_cnt - input_cycle.pop_front();

        latency.push_back(lat);

        if(ciphertext === exp) begin

            pass_cnt++;

            $display(
                "PASS  ct=%h latency=%0d",
                ciphertext,
                lat
            );

        end

        else begin

            fail_cnt++;

            $display(
                "FAIL  got=%h exp=%h",
                ciphertext,
                exp
            );

        end

    end



    //---------------------------------------------------------
    // test sequence
    //---------------------------------------------------------

    initial begin

        reset      = 1;
        in_valid   = 0;
        out_ready  = 1;

        pass_cnt   = 0;
        fail_cnt   = 0;
        cycle_cnt  = 0;

        load_nist_keys();

        repeat(5) @(posedge clk);

        reset = 0;


        //---------------------------------
        // known vector
        //---------------------------------

        send_block(

            128'h6bc1bee22e409f96e93d7e117393172a,
            0

        );

        repeat(20) @(posedge clk);


        //---------------------------------
        // continuous pipeline
        //---------------------------------

        for(int i=0;i<20;i++)

            send_block(

                128'h00112233445566778899aabbccddeeff ^ i,
                i%2

            );

        repeat(40) @(posedge clk);


        //---------------------------------
        // random tests
        //---------------------------------

        for(int i=0;i<20;i++)

            send_block(

                {$urandom,$urandom,$urandom,$urandom},
                $urandom_range(0,1)

            );

        repeat(60) @(posedge clk);


        //---------------------------------

        $display(
            "PASS=%0d FAIL=%0d",
            pass_cnt,
            fail_cnt
        );

        $finish;

    end


endmodule