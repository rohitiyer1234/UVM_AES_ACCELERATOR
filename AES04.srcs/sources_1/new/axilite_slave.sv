// ============================================================================
//  axilite_slave.sv  -  AXI4-Lite Slave Interface
//
//  STATUS: Original axilite_slave.v had the entire module body DUPLICATED
//  (same module declared twice) - this is a compilation error. Fixed by
//  keeping the single correct implementation.
//
//  Implements AXI4-Lite slave protocol:
//    - Write address + write data channels accepted independently
//    - Write response (BRESP) issued after both AW and W are received
//    - Read address captured → rd_en pulse → rdata registered one cycle later
//
//  Internal register interface:
//    wr_en   - one-cycle write strobe (address + data already latched)
//    wr_addr - latched write address
//    wr_data - latched write data
//    wr_strb - byte enable
//    rd_en   - one-cycle read strobe
//    rd_addr - latched read address
//    rd_data - registered read data from register file (captured by slave)
//
//  Timing: All AXI handshakes are registered (no combinational paths from
//  s_axi_*valid to s_axi_*ready), ensuring clean Vivado timing closure.
// ============================================================================
`timescale 1ns/1ps

module axilite_slave #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input  logic                    clk,
    input  logic                    resetn,

    // ---- AXI Write Address ----
    input  logic [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  logic                    s_axi_awvalid,
    output logic                    s_axi_awready,

    // ---- AXI Write Data ----
    input  logic [DATA_WIDTH-1:0]   s_axi_wdata,
    input  logic [3:0]              s_axi_wstrb,
    input  logic                    s_axi_wvalid,
    output logic                    s_axi_wready,

    // ---- AXI Write Response ----
    output logic [1:0]              s_axi_bresp,
    output logic                    s_axi_bvalid,
    input  logic                    s_axi_bready,

    // ---- AXI Read Address ----
    input  logic [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  logic                    s_axi_arvalid,
    output logic                    s_axi_arready,

    // ---- AXI Read Data ----
    output logic [DATA_WIDTH-1:0]   s_axi_rdata,
    output logic [1:0]              s_axi_rresp,
    output logic                    s_axi_rvalid,
    input  logic                    s_axi_rready,

    // ---- Internal register interface ----
    output logic                    wr_en,
    output logic [ADDR_WIDTH-1:0]   wr_addr,
    output logic [DATA_WIDTH-1:0]   wr_data,
    output logic [3:0]              wr_strb,

    output logic                    rd_en,
    output logic [ADDR_WIDTH-1:0]   rd_addr,
    input  logic [DATA_WIDTH-1:0]   rd_data
);

    logic aw_seen, w_seen;

    always_ff @(posedge clk) begin
        if (!resetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= '0;
            wr_en         <= 1'b0;
            rd_en         <= 1'b0;
            aw_seen       <= 1'b0;
            w_seen        <= 1'b0;
        end else begin
            wr_en <= 1'b0;
            rd_en <= 1'b0;

            // ---- Write Address ----
            s_axi_awready <= !aw_seen;
            if (s_axi_awvalid && s_axi_awready) begin
                wr_addr <= s_axi_awaddr;
                aw_seen <= 1'b1;
            end

            // ---- Write Data ----
            s_axi_wready <= !w_seen;
            if (s_axi_wvalid && s_axi_wready) begin
                wr_data <= s_axi_wdata;
                wr_strb <= s_axi_wstrb;
                w_seen  <= 1'b1;
            end

            // ---- Write Complete ----
            if (aw_seen && w_seen && !s_axi_bvalid) begin
                wr_en        <= 1'b1;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;  // OKAY
                aw_seen      <= 1'b0;
                w_seen       <= 1'b0;
            end
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            // ---- Read Address ----
            s_axi_arready <= !s_axi_rvalid;
            if (s_axi_arvalid && s_axi_arready) begin
                rd_addr      <= s_axi_araddr;
                rd_en        <= 1'b1;
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
            end

            // ---- Read Data ----
            if (s_axi_rvalid) begin
                s_axi_rdata <= rd_data;
                if (s_axi_rready)
                    s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule : axilite_slave