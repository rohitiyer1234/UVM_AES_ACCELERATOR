// ============================================================================
//  aes_axilite_top.sv  -  AES-128 Accelerator with AXI4-Lite Interface
//
//  This is the top-level module for PYNQ-Z2 / Zynq-7000 deployment.
//  Integrates: axilite_slave → axi_regs → axi_control → aes_top
//
//  PS ↔ PL Interface:
//    - AXI4-Lite slave for register-mapped control (PS is master)
//    - Active-low resetn (connected to PS reset controller)
//    - Single clock domain (100-200 MHz from PS PLL)
//
//  PS software flow:
//    1. Write KEY_Wn registers (0x10..0x1C)
//    2. Write CTRL_REG[2]=1, CTRL_REG[0]=1 (KEY_LOAD | START)
//    3. Poll STATUS[0] (BUSY) until clear
//    4. Write DATA_IN_Wn (0x20..0x2C)
//    5. Write CTRL_REG[0]=1 (START)
//    6. Poll STATUS[1] (DONE)
//    7. Read DATA_OUT_Wn (0x40..0x4C)
//
//  For PYNQ Python:
//    from pynq import Overlay, MMIO
//    ol = Overlay('aes_design.bit')
//    aes = MMIO(0x43C0_0000, 0x1000)
//
//  See docs/pynq/README_PYNQ.md for complete Python driver.
// ============================================================================
`timescale 1ns/1ps

import aes_pkg::*;

module aes_axilite_top #(
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 32
)(
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,

    // ---- AXI Write Address ----
    input  logic [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                           s_axi_awvalid,
    output logic                           s_axi_awready,

    // ---- AXI Write Data ----
    input  logic [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [3:0]                     s_axi_wstrb,
    input  logic                           s_axi_wvalid,
    output logic                           s_axi_wready,

    // ---- AXI Write Response ----
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // ---- AXI Read Address ----
    input  logic [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                           s_axi_arvalid,
    output logic                           s_axi_arready,

    // ---- AXI Read Data ----
    output logic [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                     s_axi_rresp,
    output logic                           s_axi_rvalid,
    input  logic                           s_axi_rready
);

    logic clk, resetn;
    assign clk    = s_axi_aclk;
    assign resetn = s_axi_aresetn;

    // AXI slave internal bus
    logic        wr_en, rd_en;
    logic [31:0] wr_addr, wr_data, rd_addr, rd_data;
    logic [3:0]  wr_strb;

    // Register file outputs
    logic [31:0] ctrl_reg, ctrl_reg2, mode_reg;
    logic [31:0] key_mem [0:3];
    logic [31:0] data_in_mem [0:3];
    logic [31:0] iv_mem [0:3];
    logic [31:0] status_reg;
    logic [31:0] data_out_mem [0:3];

    // AES core signals
    logic        aes_in_valid, aes_in_ready;
    logic [127:0] aes_data_in;
    logic        enc_dec_core;
    aes_mode_e   mode_core;
    logic        key_start_core;
    logic [127:0] key_core;
    logic        iv_load_core;
    logic [127:0] iv_core;
    logic        aes_out_valid;
    logic [127:0] aes_result;

    // Status feedback from AES core debug probes
    logic [1:0]  dbg_bank_valid, dbg_bank_free, dbg_bank_busy;
    logic        dbg_fifo_full, dbg_fifo_empty;

    // -----------------------------------------------------------------------
    //  AXI4-Lite Slave
    // -----------------------------------------------------------------------
    axilite_slave #(
        .ADDR_WIDTH (C_S_AXI_ADDR_WIDTH),
        .DATA_WIDTH (C_S_AXI_DATA_WIDTH)
    ) u_slave (
        .clk           (clk),
        .resetn        (resetn),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .wr_en         (wr_en),
        .wr_addr       (wr_addr),
        .wr_data       (wr_data),
        .wr_strb       (wr_strb),
        .rd_en         (rd_en),
        .rd_addr       (rd_addr),
        .rd_data       (rd_data)
    );

    // -----------------------------------------------------------------------
    //  Register File
    // -----------------------------------------------------------------------
    // Build status_reg from hardware signals
    logic [31:0] hw_status;
    assign hw_status = {
        27'b0,
        dbg_fifo_empty,             // [4]
        dbg_fifo_full,              // [3]
        |dbg_bank_valid,            // [2] KEY_READY
        status_reg[1],              // [1] DONE  (from FSM)
        status_reg[0]               // [0] BUSY  (from FSM)
    };

    axi_regs u_regs (
        .clk          (clk),
        .resetn       (resetn),
        .wr_en        (wr_en),
        .wr_addr      (wr_addr),
        .wr_data      (wr_data),
        .wr_strb      (wr_strb),
        .rd_en        (rd_en),
        .rd_addr      (rd_addr),
        .rd_data      (rd_data),
        .status_reg   (hw_status),
        .data_out_mem (data_out_mem),
        .ctrl_reg     (ctrl_reg),
        .ctrl_reg2    (ctrl_reg2),
        .mode_reg     (mode_reg),
        .key_mem      (key_mem),
        .data_in_mem  (data_in_mem),
        .iv_mem       (iv_mem)
    );

    // -----------------------------------------------------------------------
    //  Control FSM
    // -----------------------------------------------------------------------
    axi_control u_ctrl (
        .clk          (clk),
        .resetn       (resetn),
        .ctrl_reg     (ctrl_reg),
        .ctrl_reg2    (ctrl_reg2),
        .mode_reg     (mode_reg),
        .key_mem      (key_mem),
        .data_in_mem  (data_in_mem),
        .iv_mem       (iv_mem),
        .aes_done     (aes_out_valid),
        .aes_result   (aes_result),
        .status_reg   (status_reg),
        .data_out_mem (data_out_mem),
        .aes_in_valid (aes_in_valid),
        .aes_data_in  (aes_data_in),
        .enc_dec_out  (enc_dec_core),
        .mode_out     (mode_core),
        .key_start    (key_start_core),
        .key_out      (key_core),
        .iv_load      (iv_load_core),
        .iv_out       (iv_core)
    );

    // -----------------------------------------------------------------------
    //  AES Core
    // -----------------------------------------------------------------------
    aes_top u_aes (
        .clk              (clk),
        .reset            (!resetn),
        .enc_dec          (enc_dec_core),
        .mode             (mode_core),
        .iv_load          (iv_load_core),
        .iv_in            (iv_core),
        .in_valid         (aes_in_valid),
        .in_ready         (aes_in_ready),
        .data_in          (aes_data_in),
        .out_valid        (aes_out_valid),
        .out_ready        (1'b1),   // AXI-lite is non-streaming; always ready
        .data_out         (aes_result),
        .key_start        (key_start_core),
        .key              (key_core),
        .dbg_bank_valid   (dbg_bank_valid),
        .dbg_bank_free    (dbg_bank_free),
        .dbg_fifo_empty   (dbg_fifo_empty),
        .dbg_fifo_full    (dbg_fifo_full),
        .dbg_exp_done     (),
        .dbg_current_bank (),
        .dbg_bank_busy    (dbg_bank_busy)
    );

endmodule : aes_axilite_top