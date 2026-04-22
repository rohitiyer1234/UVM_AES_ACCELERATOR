// ============================================================================
//  axi_regs.sv  -  AES Accelerator AXI4-Lite Register File
//
//  STATUS: Original axi_regs.v had the module declared TWICE with different
//  port styles (array vs flat) - compilation error. Fixed: single clean module
//  using packed arrays throughout.
//
//  FULL REGISTER MAP (base address configured by Vivado block design):
//  ┌────────┬──────────────┬───┬──────────────────────────────────────────┐
//  │ Offset │ Name         │R/W│ Description                              │
//  ├────────┼──────────────┼───┼──────────────────────────────────────────┤
//  │ 0x00   │ CTRL_REG     │ W │ [0] START: pulse to begin operation      │
//  │        │              │   │ [1] ENC_DEC: 0=encrypt, 1=decrypt        │
//  │        │              │   │ [2] KEY_LOAD: pulse to push key to FIFO  │
//  │        │              │   │ [7:5] MODE: 0=ECB,1=CBC,2=CFB,3=OFB,4=CTR│
//  │ 0x04   │ CTRL_REG2    │ W │ [0] IV_LOAD: load IV registers           │
//  │        │              │   │ [1] SOFT_RESET: soft reset (self-clear)  │
//  │ 0x08   │ STATUS_REG   │ R │ [0] BUSY: operation in progress          │
//  │        │              │   │ [1] DONE: last operation complete        │
//  │        │              │   │ [2] KEY_READY: key bank valid            │
//  │        │              │   │ [3] FIFO_FULL: key FIFO full             │
//  │        │              │   │ [4] FIFO_EMPTY: key FIFO empty           │
//  │ 0x0C   │ MODE_REG     │ W │ [2:0] AES mode (mirrors CTRL[7:5])       │
//  │ 0x10   │ KEY_W0       │ W │ Key [127:96]                             │
//  │ 0x14   │ KEY_W1       │ W │ Key [95:64]                              │
//  │ 0x18   │ KEY_W2       │ W │ Key [63:32]                              │
//  │ 0x1C   │ KEY_W3       │ W │ Key [31:0]                               │
//  │ 0x20   │ DATA_IN_W0   │ W │ Input block [127:96]                     │
//  │ 0x24   │ DATA_IN_W1   │ W │ Input block [95:64]                      │
//  │ 0x28   │ DATA_IN_W2   │ W │ Input block [63:32]                      │
//  │ 0x2C   │ DATA_IN_W3   │ W │ Input block [31:0]                       │
//  │ 0x30   │ IV_W0        │ W │ IV / counter [127:96]                    │
//  │ 0x34   │ IV_W1        │ W │ IV / counter [95:64]                     │
//  │ 0x38   │ IV_W2        │ W │ IV / counter [63:32]                     │
//  │ 0x3C   │ IV_W3        │ W │ IV / counter [31:0]                      │
//  │ 0x40   │ DATA_OUT_W0  │ R │ Output block [127:96]                    │
//  │ 0x44   │ DATA_OUT_W1  │ R │ Output block [95:64]                     │
//  │ 0x48   │ DATA_OUT_W2  │ R │ Output block [63:32]                     │
//  │ 0x4C   │ DATA_OUT_W3  │ R │ Output block [31:0]                      │
//  └────────┴──────────────┴───┴──────────────────────────────────────────┘
// ============================================================================
`timescale 1ns/1ps

module axi_regs (
    input  logic        clk,
    input  logic        resetn,

    // ---- Internal bus from axilite_slave ----
    input  logic        wr_en,
    input  logic [31:0] wr_addr,
    input  logic [31:0] wr_data,
    input  logic [3:0]  wr_strb,

    input  logic        rd_en,
    input  logic [31:0] rd_addr,
    output logic [31:0] rd_data,

    // ---- Status inputs (from hardware) ----
    input  logic [31:0] status_reg,
    input  logic [31:0] data_out_mem [0:3],

    // ---- Config outputs (to hardware) ----
    output logic [31:0] ctrl_reg,
    output logic [31:0] ctrl_reg2,
    output logic [31:0] mode_reg,
    output logic [31:0] key_mem     [0:3],
    output logic [31:0] data_in_mem [0:3],
    output logic [31:0] iv_mem      [0:3]
);

    always_ff @(posedge clk) begin
        if (!resetn) begin
            ctrl_reg  <= 32'd0;
            ctrl_reg2 <= 32'd0;
            mode_reg  <= 32'd0;
            for (int i = 0; i < 4; i++) begin
                key_mem[i]     <= 32'd0;
                data_in_mem[i] <= 32'd0;
                iv_mem[i]      <= 32'd0;
            end
        end else begin
            // Self-clear pulses: START, KEY_LOAD, IV_LOAD, SOFT_RESET
            ctrl_reg[0] <= 1'b0;   // START
            ctrl_reg[2] <= 1'b0;   // KEY_LOAD
            ctrl_reg2[0] <= 1'b0;  // IV_LOAD
            ctrl_reg2[1] <= 1'b0;  // SOFT_RESET

            if (wr_en) begin
                case (wr_addr[7:0])
                    8'h00: ctrl_reg   <= wr_data;
                    8'h04: ctrl_reg2  <= wr_data;
                    8'h0C: mode_reg   <= wr_data;
                    8'h10: key_mem[0] <= wr_data;
                    8'h14: key_mem[1] <= wr_data;
                    8'h18: key_mem[2] <= wr_data;
                    8'h1C: key_mem[3] <= wr_data;
                    8'h20: data_in_mem[0] <= wr_data;
                    8'h24: data_in_mem[1] <= wr_data;
                    8'h28: data_in_mem[2] <= wr_data;
                    8'h2C: data_in_mem[3] <= wr_data;
                    8'h30: iv_mem[0]  <= wr_data;
                    8'h34: iv_mem[1]  <= wr_data;
                    8'h38: iv_mem[2]  <= wr_data;
                    8'h3C: iv_mem[3]  <= wr_data;
                    default: ;
                endcase
            end
        end
    end

    // Read path (registered for timing)
    always_ff @(posedge clk) begin
        if (!resetn)
            rd_data <= 32'd0;
        else if (rd_en) begin
            case (rd_addr[7:0])
                8'h00: rd_data <= ctrl_reg;
                8'h04: rd_data <= ctrl_reg2;
                8'h08: rd_data <= status_reg;
                8'h0C: rd_data <= mode_reg;
                8'h40: rd_data <= data_out_mem[0];
                8'h44: rd_data <= data_out_mem[1];
                8'h48: rd_data <= data_out_mem[2];
                8'h4C: rd_data <= data_out_mem[3];
                default: rd_data <= 32'd0;
            endcase
        end
    end

endmodule : axi_regs