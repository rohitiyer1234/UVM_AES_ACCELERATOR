// ============================================================================
//  key_fifo.sv  -  STEP 5b
//  Simple synchronous FIFO for raw 128-bit AES keys.
//  Depth is parameterisable (default 4).
//
//  No functional bugs in original; converted to SystemVerilog style.
//  Additional fix: wr_ptr/rd_ptr/count width is $clog2(DEPTH)+1 to avoid
//  overflow when DEPTH is a power of two (count must reach DEPTH, not wrap).
// ============================================================================
import aes_pkg::*;


module key_fifo #(
    parameter int DEPTH = aes_pkg::KEY_FIFO_DEPTH
)(
    input  logic        clk,
    input  logic        reset,

    input  logic        push,
    input  aes_pkg::aes_block_t  data_in,

    input  logic        pop,
    output aes_pkg::aes_block_t  data_out,

    output logic        empty,
    output logic        full
);
    import aes_pkg::*;

    localparam int PTR_W = $clog2(DEPTH) + 1;

    aes_block_t mem [0:DEPTH-1];
    logic [PTR_W-1:0] wr_ptr, rd_ptr, count;

    assign empty = (count == '0);
    assign full  = (count == PTR_W'(DEPTH));

   always_ff @(posedge clk) begin

    if(reset) begin
        wr_ptr   <= '0;
        rd_ptr   <= '0;
        count    <= '0;
        data_out <= '0;
    end
    else begin
        case ({push && !full, pop && !empty})
            // push only
            2'b10: begin
                mem[wr_ptr[PTR_W-2:0]] <= data_in;
                wr_ptr <= wr_ptr + 1'b1;
                count  <= count  + 1'b1;
            end
            // pop only
            2'b01: begin
                data_out <= mem[rd_ptr[PTR_W-2:0]];
                rd_ptr <= rd_ptr + 1'b1;
                count  <= count  - 1'b1;
            end
            // simultaneous push+pop
            2'b11: begin
                mem[wr_ptr[PTR_W-2:0]] <= data_in;
                data_out               <= mem[rd_ptr[PTR_W-2:0]];
                wr_ptr <= wr_ptr + 1'b1;
                rd_ptr <= rd_ptr + 1'b1;
            end
            default: ;
        endcase
    end
end
endmodule
