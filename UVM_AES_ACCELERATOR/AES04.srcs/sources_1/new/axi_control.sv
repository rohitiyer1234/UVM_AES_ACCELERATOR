// ============================================================================
//  axi_control.sv  -  AES Accelerator Control FSM
//
//  STATUS: Original axi_control.v had a second copy commented out with a
//  different port set. Unified into one clean module. FSM logic preserved.
//
//  This module bridges the register file outputs to the AES core interface:
//    - Detects START pulse in ctrl_reg
//    - Latches data_in, key, mode, enc_dec, iv into pipeline-compatible signals
//    - Drives key_start and iv_load pulses to the core
//    - Monitors aes_done → captures output → sets DONE in status_reg
//
//  FSM states:
//    IDLE: waiting for START
//    KEY:  one-cycle key push to FIFO (if KEY_LOAD set)
//    IV:   one-cycle IV load (if IV_LOAD set and non-ECB mode)
//    RUN:  waiting for aes_done (AES pipeline processing)
//    DONE: output ready, waiting for START to clear
// ============================================================================
`timescale 1ns/1ps

import aes_pkg::*;

module axi_control (
    input  logic        clk,
    input  logic        resetn,

    // ---- From register file ----
    input  logic [31:0] ctrl_reg,
    input  logic [31:0] ctrl_reg2,
    input  logic [31:0] mode_reg,
    input  logic [31:0] key_mem     [0:3],
    input  logic [31:0] data_in_mem [0:3],
    input  logic [31:0] iv_mem      [0:3],

    // ---- AES pipeline status ----
    input  logic        aes_done,
    input  logic [127:0] aes_result,

    // ---- To register file (status + output) ----
    output logic [31:0] status_reg,
    output logic [31:0] data_out_mem [0:3],

    // ---- To AES core ----
    output logic        aes_in_valid,
    output logic [127:0] aes_data_in,
    output logic        enc_dec_out,
    output aes_mode_e   mode_out,
    output logic        key_start,
    output logic [127:0] key_out,
    output logic        iv_load,
    output logic [127:0] iv_out
);

    typedef enum logic [2:0] {
        S_IDLE = 3'd0,
        S_KEY  = 3'd1,
        S_IV   = 3'd2,
        S_RUN  = 3'd3,
        S_DONE = 3'd4
    } fsm_t;

    fsm_t state;

    // Latched copies of config for current transaction
    logic [127:0] lat_data_in;
    logic [127:0] lat_key;
    logic [127:0] lat_iv;
    logic         lat_enc_dec;
    logic [2:0]   lat_mode;
    logic         lat_key_load;
    logic         lat_iv_load;

    always_ff @(posedge clk) begin
        if (!resetn) begin
            state        <= S_IDLE;
            status_reg   <= 32'd0;
            aes_in_valid <= 1'b0;
            key_start    <= 1'b0;
            iv_load      <= 1'b0;
            for (int i = 0; i < 4; i++) data_out_mem[i] <= 32'd0;
        end else begin
            aes_in_valid <= 1'b0;
            key_start    <= 1'b0;
            iv_load      <= 1'b0;

            case (state)
                S_IDLE: begin
                    status_reg[0] <= 1'b0;  // BUSY
                    status_reg[1] <= 1'b0;  // DONE

                    if (ctrl_reg[0]) begin  // START
                        // Latch all config
                        lat_data_in  <= {data_in_mem[0], data_in_mem[1],
                                         data_in_mem[2], data_in_mem[3]};
                        lat_key      <= {key_mem[0], key_mem[1],
                                         key_mem[2], key_mem[3]};
                        lat_iv       <= {iv_mem[0], iv_mem[1],
                                         iv_mem[2], iv_mem[3]};
                        lat_enc_dec  <= ctrl_reg[1];
                        lat_mode     <= mode_reg[2:0];
                        lat_key_load <= ctrl_reg[2];
                        lat_iv_load  <= ctrl_reg2[0];

                        status_reg[0] <= 1'b1;  // BUSY

                        if (ctrl_reg[2])
                            state <= S_KEY;
                        else if (ctrl_reg2[0] && (mode_reg[2:0] != 3'd0))
                            state <= S_IV;
                        else begin
                            aes_in_valid <= 1'b1;
                            state        <= S_RUN;
                        end
                    end
                end

                S_KEY: begin
                    // Push key to FIFO for one cycle
                    key_start <= 1'b1;
                    key_out   <= lat_key;
                    if (lat_iv_load && (lat_mode != 3'd0))
                        state <= S_IV;
                    else begin
                        aes_in_valid <= 1'b1;
                        state        <= S_RUN;
                    end
                end

                S_IV: begin
                    iv_load <= 1'b1;
                    iv_out  <= lat_iv;
                    aes_in_valid <= 1'b1;
                    state <= S_RUN;
                end

                S_RUN: begin
                    status_reg[0] <= 1'b1;
                    if (aes_done) begin
                        data_out_mem[0] <= aes_result[127:96];
                        data_out_mem[1] <= aes_result[95:64];
                        data_out_mem[2] <= aes_result[63:32];
                        data_out_mem[3] <= aes_result[31:0];
                        status_reg[0]   <= 1'b0;
                        status_reg[1]   <= 1'b1;  // DONE
                        state           <= S_DONE;
                    end
                end

                S_DONE: begin
                    if (!ctrl_reg[0])
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign aes_data_in  = lat_data_in;
    assign enc_dec_out  = lat_enc_dec;
    assign mode_out     = aes_mode_e'(lat_mode);

endmodule : axi_control