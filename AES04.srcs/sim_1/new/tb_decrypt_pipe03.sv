`timescale 1ns/1ps
import aes_pkg::*;

///////////////////////////////////////////////////////////////
// reference GF math
///////////////////////////////////////////////////////////////

function automatic logic [7:0] xtime(input logic [7:0] a);
    xtime = {a[6:0],1'b0} ^ (8'h1B & {8{a[7]}});
endfunction

function automatic logic [7:0] mul9(input logic [7:0] a);
    return xtime(xtime(xtime(a))) ^ a;
endfunction

function automatic logic [7:0] mul11(input logic [7:0] a);
    return xtime(xtime(xtime(a)) ^ a) ^ a;
endfunction

function automatic logic [7:0] mul13(input logic [7:0] a);
    return xtime(xtime(xtime(a) ^ a)) ^ a;
endfunction

function automatic logic [7:0] mul14(input logic [7:0] a);
    return xtime(xtime(xtime(a) ^ a) ^ a);
endfunction


///////////////////////////////////////////////////////////////
// reference inverse transformations
///////////////////////////////////////////////////////////////

function automatic logic [7:0] inv_sbox_byte(input logic [7:0] a);

    case(a)

                8'h00: inv_sbox_byte = 8'h52; 8'h01: inv_sbox_byte = 8'h09;
                8'h02: inv_sbox_byte = 8'h6A; 8'h03: inv_sbox_byte = 8'hD5;
                8'h04: inv_sbox_byte = 8'h30; 8'h05: inv_sbox_byte = 8'h36;
                8'h06: inv_sbox_byte = 8'hA5; 8'h07: inv_sbox_byte = 8'h38;
                8'h08: inv_sbox_byte = 8'hBF; 8'h09: inv_sbox_byte = 8'h40;
                8'h0A: inv_sbox_byte = 8'hA3; 8'h0B: inv_sbox_byte = 8'h9E;
                8'h0C: inv_sbox_byte = 8'h81; 8'h0D: inv_sbox_byte = 8'hF3;
                8'h0E: inv_sbox_byte = 8'hD7; 8'h0F: inv_sbox_byte = 8'hFB;

                8'h10: inv_sbox_byte = 8'h7C; 8'h11: inv_sbox_byte = 8'hE3;
                8'h12: inv_sbox_byte = 8'h39; 8'h13: inv_sbox_byte = 8'h82;
                8'h14: inv_sbox_byte = 8'h9B; 8'h15: inv_sbox_byte = 8'h2F;
                8'h16: inv_sbox_byte = 8'hFF; 8'h17: inv_sbox_byte = 8'h87;
                8'h18: inv_sbox_byte = 8'h34; 8'h19: inv_sbox_byte = 8'h8E;
                8'h1A: inv_sbox_byte = 8'h43; 8'h1B: inv_sbox_byte = 8'h44;
                8'h1C: inv_sbox_byte = 8'hC4; 8'h1D: inv_sbox_byte = 8'hDE;
                8'h1E: inv_sbox_byte = 8'hE9; 8'h1F: inv_sbox_byte = 8'hCB;

                8'h20: inv_sbox_byte = 8'h54; 8'h21: inv_sbox_byte = 8'h7B;
                8'h22: inv_sbox_byte = 8'h94; 8'h23: inv_sbox_byte = 8'h32;
                8'h24: inv_sbox_byte = 8'hA6; 8'h25: inv_sbox_byte = 8'hC2;
                8'h26: inv_sbox_byte = 8'h23; 8'h27: inv_sbox_byte = 8'h3D;
                8'h28: inv_sbox_byte = 8'hEE; 8'h29: inv_sbox_byte = 8'h4C;
                8'h2A: inv_sbox_byte = 8'h95; 8'h2B: inv_sbox_byte = 8'h0B;
                8'h2C: inv_sbox_byte = 8'h42; 8'h2D: inv_sbox_byte = 8'hFA;
                8'h2E: inv_sbox_byte = 8'hC3; 8'h2F: inv_sbox_byte = 8'h4E;

                8'h30: inv_sbox_byte = 8'h08; 8'h31: inv_sbox_byte = 8'h2E;
                8'h32: inv_sbox_byte = 8'hA1; 8'h33: inv_sbox_byte = 8'h66;
                8'h34: inv_sbox_byte = 8'h28; 8'h35: inv_sbox_byte = 8'hD9;
                8'h36: inv_sbox_byte = 8'h24; 8'h37: inv_sbox_byte = 8'hB2;
                8'h38: inv_sbox_byte = 8'h76; 8'h39: inv_sbox_byte = 8'h5B;
                8'h3A: inv_sbox_byte = 8'hA2; 8'h3B: inv_sbox_byte = 8'h49;
                8'h3C: inv_sbox_byte = 8'h6D; 8'h3D: inv_sbox_byte = 8'h8B;
                8'h3E: inv_sbox_byte = 8'hD1; 8'h3F: inv_sbox_byte = 8'h25;

                8'h40: inv_sbox_byte = 8'h72; 8'h41: inv_sbox_byte = 8'hF8;
                8'h42: inv_sbox_byte = 8'hF6; 8'h43: inv_sbox_byte = 8'h64;
                8'h44: inv_sbox_byte = 8'h86; 8'h45: inv_sbox_byte = 8'h68;
                8'h46: inv_sbox_byte = 8'h98; 8'h47: inv_sbox_byte = 8'h16;
                8'h48: inv_sbox_byte = 8'hD4; 8'h49: inv_sbox_byte = 8'hA4;
                8'h4A: inv_sbox_byte = 8'h5C; 8'h4B: inv_sbox_byte = 8'hCC;
                8'h4C: inv_sbox_byte = 8'h5D; 8'h4D: inv_sbox_byte = 8'h65;
                8'h4E: inv_sbox_byte = 8'hB6; 8'h4F: inv_sbox_byte = 8'h92;

                8'h50: inv_sbox_byte = 8'h6C; 8'h51: inv_sbox_byte = 8'h70;
                8'h52: inv_sbox_byte = 8'h48; 8'h53: inv_sbox_byte = 8'h50;
                8'h54: inv_sbox_byte = 8'hFD; 8'h55: inv_sbox_byte = 8'hED;
                8'h56: inv_sbox_byte = 8'hB9; 8'h57: inv_sbox_byte = 8'hDA;
                8'h58: inv_sbox_byte = 8'h5E; 8'h59: inv_sbox_byte = 8'h15;
                8'h5A: inv_sbox_byte = 8'h46; 8'h5B: inv_sbox_byte = 8'h57;
                8'h5C: inv_sbox_byte = 8'hA7; 8'h5D: inv_sbox_byte = 8'h8D;
                8'h5E: inv_sbox_byte = 8'h9D; 8'h5F: inv_sbox_byte = 8'h84;

                8'h60: inv_sbox_byte = 8'h90; 8'h61: inv_sbox_byte = 8'hD8;
                8'h62: inv_sbox_byte = 8'hAB; 8'h63: inv_sbox_byte = 8'h00;
                8'h64: inv_sbox_byte = 8'h8C; 8'h65: inv_sbox_byte = 8'hBC;
                8'h66: inv_sbox_byte = 8'hD3; 8'h67: inv_sbox_byte = 8'h0A;
                8'h68: inv_sbox_byte = 8'hF7; 8'h69: inv_sbox_byte = 8'hE4;
                8'h6A: inv_sbox_byte = 8'h58; 8'h6B: inv_sbox_byte = 8'h05;
                8'h6C: inv_sbox_byte = 8'hB8; 8'h6D: inv_sbox_byte = 8'hB3;
                8'h6E: inv_sbox_byte = 8'h45; 8'h6F: inv_sbox_byte = 8'h06;

                8'h70: inv_sbox_byte = 8'hD0; 8'h71: inv_sbox_byte = 8'h2C;
                8'h72: inv_sbox_byte = 8'h1E; 8'h73: inv_sbox_byte = 8'h8F;
                8'h74: inv_sbox_byte = 8'hCA; 8'h75: inv_sbox_byte = 8'h3F;
                8'h76: inv_sbox_byte = 8'h0F; 8'h77: inv_sbox_byte = 8'h02;
                8'h78: inv_sbox_byte = 8'hC1; 8'h79: inv_sbox_byte = 8'hAF;
                8'h7A: inv_sbox_byte = 8'hBD; 8'h7B: inv_sbox_byte = 8'h03;
                8'h7C: inv_sbox_byte = 8'h01; 8'h7D: inv_sbox_byte = 8'h13;
                8'h7E: inv_sbox_byte = 8'h8A; 8'h7F: inv_sbox_byte = 8'h6B;

                8'h80: inv_sbox_byte = 8'h3A; 8'h81: inv_sbox_byte = 8'h91;
                8'h82: inv_sbox_byte = 8'h11; 8'h83: inv_sbox_byte = 8'h41;
                8'h84: inv_sbox_byte = 8'h4F; 8'h85: inv_sbox_byte = 8'h67;
                8'h86: inv_sbox_byte = 8'hDC; 8'h87: inv_sbox_byte = 8'hEA;
                8'h88: inv_sbox_byte = 8'h97; 8'h89: inv_sbox_byte = 8'hF2;
                8'h8A: inv_sbox_byte = 8'hCF; 8'h8B: inv_sbox_byte = 8'hCE;
                8'h8C: inv_sbox_byte = 8'hF0; 8'h8D: inv_sbox_byte = 8'hB4;
                8'h8E: inv_sbox_byte = 8'hE6; 8'h8F: inv_sbox_byte = 8'h73;

                8'h90: inv_sbox_byte = 8'h96; 8'h91: inv_sbox_byte = 8'hAC;
                8'h92: inv_sbox_byte = 8'h74; 8'h93: inv_sbox_byte = 8'h22;
                8'h94: inv_sbox_byte = 8'hE7; 8'h95: inv_sbox_byte = 8'hAD;
                8'h96: inv_sbox_byte = 8'h35; 8'h97: inv_sbox_byte = 8'h85;
                8'h98: inv_sbox_byte = 8'hE2; 8'h99: inv_sbox_byte = 8'hF9;
                8'h9A: inv_sbox_byte = 8'h37; 8'h9B: inv_sbox_byte = 8'hE8;
                8'h9C: inv_sbox_byte = 8'h1C; 8'h9D: inv_sbox_byte = 8'h75;
                8'h9E: inv_sbox_byte = 8'hDF; 8'h9F: inv_sbox_byte = 8'h6E;

                8'hA0: inv_sbox_byte = 8'h47; 8'hA1: inv_sbox_byte = 8'hF1;
                8'hA2: inv_sbox_byte = 8'h1A; 8'hA3: inv_sbox_byte = 8'h71;
                8'hA4: inv_sbox_byte = 8'h1D; 8'hA5: inv_sbox_byte = 8'h29;
                8'hA6: inv_sbox_byte = 8'hC5; 8'hA7: inv_sbox_byte = 8'h89;
                8'hA8: inv_sbox_byte = 8'h6F; 8'hA9: inv_sbox_byte = 8'hB7;
                8'hAA: inv_sbox_byte = 8'h62; 8'hAB: inv_sbox_byte = 8'h0E;
                8'hAC: inv_sbox_byte = 8'hAA; 8'hAD: inv_sbox_byte = 8'h18;
                8'hAE: inv_sbox_byte = 8'hBE; 8'hAF: inv_sbox_byte = 8'h1B;

                8'hB0: inv_sbox_byte = 8'hFC; 8'hB1: inv_sbox_byte = 8'h56;
                8'hB2: inv_sbox_byte = 8'h3E; 8'hB3: inv_sbox_byte = 8'h4B;
                8'hB4: inv_sbox_byte = 8'hC6; 8'hB5: inv_sbox_byte = 8'hD2;
                8'hB6: inv_sbox_byte = 8'h79; 8'hB7: inv_sbox_byte = 8'h20;
                8'hB8: inv_sbox_byte = 8'h9A; 8'hB9: inv_sbox_byte = 8'hDB;
                8'hBA: inv_sbox_byte = 8'hC0; 8'hBB: inv_sbox_byte = 8'hFE;
                8'hBC: inv_sbox_byte = 8'h78; 8'hBD: inv_sbox_byte = 8'hCD;
                8'hBE: inv_sbox_byte = 8'h5A; 8'hBF: inv_sbox_byte = 8'hF4;

                8'hC0: inv_sbox_byte = 8'h1F; 8'hC1: inv_sbox_byte = 8'hDD;
                8'hC2: inv_sbox_byte = 8'hA8; 8'hC3: inv_sbox_byte = 8'h33;
                8'hC4: inv_sbox_byte = 8'h88; 8'hC5: inv_sbox_byte = 8'h07;
                8'hC6: inv_sbox_byte = 8'hC7; 8'hC7: inv_sbox_byte = 8'h31;
                8'hC8: inv_sbox_byte = 8'hB1; 8'hC9: inv_sbox_byte = 8'h12;
                8'hCA: inv_sbox_byte = 8'h10; 8'hCB: inv_sbox_byte = 8'h59;
                8'hCC: inv_sbox_byte = 8'h27; 8'hCD: inv_sbox_byte = 8'h80;
                8'hCE: inv_sbox_byte = 8'hEC; 8'hCF: inv_sbox_byte = 8'h5F;

                8'hD0: inv_sbox_byte = 8'h60; 8'hD1: inv_sbox_byte = 8'h51;
                8'hD2: inv_sbox_byte = 8'h7F; 8'hD3: inv_sbox_byte = 8'hA9;
                8'hD4: inv_sbox_byte = 8'h19; 8'hD5: inv_sbox_byte = 8'hB5;
                8'hD6: inv_sbox_byte = 8'h4A; 8'hD7: inv_sbox_byte = 8'h0D;
                8'hD8: inv_sbox_byte = 8'h2D; 8'hD9: inv_sbox_byte = 8'hE5;
                8'hDA: inv_sbox_byte = 8'h7A; 8'hDB: inv_sbox_byte = 8'h9F;
                8'hDC: inv_sbox_byte = 8'h93; 8'hDD: inv_sbox_byte = 8'hC9;
                8'hDE: inv_sbox_byte = 8'h9C; 8'hDF: inv_sbox_byte = 8'hEF;

                8'hE0: inv_sbox_byte = 8'hA0; 8'hE1: inv_sbox_byte = 8'hE0;
                8'hE2: inv_sbox_byte = 8'h3B; 8'hE3: inv_sbox_byte = 8'h4D;
                8'hE4: inv_sbox_byte = 8'hAE; 8'hE5: inv_sbox_byte = 8'h2A;
                8'hE6: inv_sbox_byte = 8'hF5; 8'hE7: inv_sbox_byte = 8'hB0;
                8'hE8: inv_sbox_byte = 8'hC8; 8'hE9: inv_sbox_byte = 8'hEB;
                8'hEA: inv_sbox_byte = 8'hBB; 8'hEB: inv_sbox_byte = 8'h3C;
                8'hEC: inv_sbox_byte = 8'h83; 8'hED: inv_sbox_byte = 8'h53;
                8'hEE: inv_sbox_byte = 8'h99; 8'hEF: inv_sbox_byte = 8'h61;

                8'hF0: inv_sbox_byte = 8'h17; 8'hF1: inv_sbox_byte = 8'h2B;
                8'hF2: inv_sbox_byte = 8'h04; 8'hF3: inv_sbox_byte = 8'h7E;
                8'hF4: inv_sbox_byte = 8'hBA; 8'hF5: inv_sbox_byte = 8'h77;
                8'hF6: inv_sbox_byte = 8'hD6; 8'hF7: inv_sbox_byte = 8'h26;
                8'hF8: inv_sbox_byte = 8'hE1; 8'hF9: inv_sbox_byte = 8'h69;
                8'hFA: inv_sbox_byte = 8'h14; 8'hFB: inv_sbox_byte = 8'h63;
                8'hFC: inv_sbox_byte = 8'h55; 8'hFD: inv_sbox_byte = 8'h21;
                8'hFE: inv_sbox_byte = 8'h0C; 8'hFF: inv_sbox_byte = 8'h7D;

        default: inv_sbox_byte = 8'h00;

    endcase

endfunction


function automatic aes_block_t ref_inv_shiftrows(aes_block_t s);

    logic [7:0] b[15:0];

    {
        b[0], b[1], b[2], b[3],
        b[4], b[5], b[6], b[7],
        b[8], b[9], b[10], b[11],
        b[12],b[13],b[14],b[15]
    } = s;

    return {

        b[0],  b[13], b[10], b[7],
        b[4],  b[1],  b[14], b[11],
        b[8],  b[5],  b[2],  b[15],
        b[12], b[9],  b[6],  b[3]

    };

endfunction


function automatic aes_block_t ref_inv_subbytes(aes_block_t s);

    for(int i=0;i<16;i++)
        s[127-8*i -:8] =
            inv_sbox_byte_byte(s[127-8*i -:8]);

    return s;

endfunction


function automatic aes_block_t ref_inv_mixcolumns(aes_block_t s);

    for(int i=0;i<4;i++) begin

        logic [7:0] s0,s1,s2,s3;

        s0 = s[127-32*i -:8];
        s1 = s[119-32*i -:8];
        s2 = s[111-32*i -:8];
        s3 = s[103-32*i -:8];

        s[127-32*i -:8] =
            mul14(s0)^mul11(s1)^mul13(s2)^mul9(s3);

        s[119-32*i -:8] =
            mul9(s0)^mul14(s1)^mul11(s2)^mul13(s3);

        s[111-32*i -:8] =
            mul13(s0)^mul9(s1)^mul14(s2)^mul11(s3);

        s[103-32*i -:8] =
            mul11(s0)^mul13(s1)^mul9(s2)^mul14(s3);

    end

    return s;

endfunction


///////////////////////////////////////////////////////////////
// full AES inverse cipher golden model
///////////////////////////////////////////////////////////////

function automatic aes_block_t ref_aes_dec(

    input aes_block_t ct,
    input rk_bank_t rk

);

    aes_block_t st;

    st = ct ^ rk[10];

    for(int r=9; r>=1; r--) begin

        st = ref_inv_shiftrows(st);
        st = ref_inv_subbytes(st);

        st ^= rk[r];

        if(r>1)
            st = ref_inv_mixcolumns(st);

    end

    return st;

endfunction



///////////////////////////////////////////////////////////////
// TESTBENCH
///////////////////////////////////////////////////////////////

module tb_decrypt_pipe03;


logic clk;
logic reset;

logic in_valid;
logic in_ready;

aes_block_t ciphertext;
logic current_bank;

rk_store_t round_keys;

aes_block_t plaintext;

logic out_valid;
logic out_ready;

logic [1:0] bank_busy;



AES_Decrypt_Pipe03 dut (.*);



///////////////////////////////////////////////////////////////
// clock
///////////////////////////////////////////////////////////////

initial clk = 0;
always #5 clk = ~clk;



///////////////////////////////////////////////////////////////
// scoreboard
///////////////////////////////////////////////////////////////

aes_block_t exp_queue[$];
int input_cycle[$];
int latency[$];

int cycle_cnt;
int pass_cnt;
int fail_cnt;


always_ff @(posedge clk)
    cycle_cnt++;



///////////////////////////////////////////////////////////////
// load key schedule
///////////////////////////////////////////////////////////////

task load_keys();

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

    for(int i=0;i<=10;i++)
        round_keys[1][i] =
            128'hdeadbeefdeadbeefdeadbeefdeadbeef ^ i;

endtask



///////////////////////////////////////////////////////////////
// stimulus helper
///////////////////////////////////////////////////////////////

task send_block(

    input aes_block_t ct,
    input logic bk

);

    @(negedge clk);

    in_valid     = 1;
    ciphertext   = ct;
    current_bank = bk;

    @(posedge clk);

    if(in_ready) begin

        exp_queue.push_back(
            ref_aes_dec(ct, round_keys[bk])
        );

        input_cycle.push_back(cycle_cnt);

    end

    @(negedge clk);

    in_valid = 0;

endtask



///////////////////////////////////////////////////////////////
// monitor
///////////////////////////////////////////////////////////////

always @(posedge clk)

if(out_valid && out_ready)

begin

    aes_block_t exp =
        exp_queue.pop_front();

    int lat =
        cycle_cnt - input_cycle.pop_front();

    latency.push_back(lat);

    if(plaintext === exp)

    begin

        pass_cnt++;

        $display(
            "PASS pt=%h latency=%0d",
            plaintext,
            lat
        );

    end

    else

    begin

        fail_cnt++;

        $display(
            "FAIL got=%h exp=%h",
            plaintext,
            exp
        );

    end

end



///////////////////////////////////////////////////////////////
// test sequence
///////////////////////////////////////////////////////////////

initial begin

    reset      = 1;
    in_valid   = 0;
    out_ready  = 1;

    pass_cnt   = 0;
    fail_cnt   = 0;
    cycle_cnt  = 0;

    load_keys();

    repeat(5) @(posedge clk);

    reset = 0;


    //--------------------------------------------------
    // directed test (known AES vector)
    //--------------------------------------------------

    send_block(
        128'h3ad77bb40d7a3660a89ecaf32466ef97,
        0
    );


    repeat(20) @(posedge clk);


    //--------------------------------------------------
    // continuous pipeline
    //--------------------------------------------------

    for(int i=0;i<20;i++)

        send_block(

            128'h00112233445566778899aabbccddeeff ^ i,
            i%2

        );


    repeat(40) @(posedge clk);


    //--------------------------------------------------
    // random stress
    //--------------------------------------------------

    for(int i=0;i<30;i++)

        send_block(

            {$urandom,$urandom,$urandom,$urandom},
            $urandom_range(0,1)

        );


    repeat(80) @(posedge clk);


    //--------------------------------------------------

    $display(
        "DECRYPT PASS=%0d FAIL=%0d",
        pass_cnt,
        fail_cnt
    );

    $finish;

end


endmodule