import aes_pkg::*;

/*module keymem_dual(
    input  logic        clk,
    input  logic        reset,

    // ---- Write interface (from key expansion) ----
    input  logic        w_en,
    input  logic [3:0]  waddr,
    input  aes_block_t  wkey,
    input  logic        write_bank,

    // ---- Bank usage tracking ----
    input  logic [1:0]  bank_busy,          // BUG-2 fix: packed 2-bit

    // ---- Round-key read bus (BUG-1 fix: SV typedef) ----
    output rk_store_t   round_keys,

    // ---- Bank status ----
    output logic [1:0]  bank_valid,
    output logic [1:0]  bank_free
);
    
    // Storage
    
    aes_block_t mem [0:1][0:NUM_ROUNDS];
    logic [10:0] valid [0:1];
    
    
    // -----------------------------------------------------------------------
    //  bank_free: bank is not busy AND not already loaded
    // -----------------------------------------------------------------------
    assign bank_free[0] = !bank_busy[0] && !bank_valid[0];
    assign bank_free[1] = !bank_busy[1] && !bank_valid[1];

    // -----------------------------------------------------------------------
    //  BUG-3 FIX: compute valid_next combinationally so bank_valid sees
    //  the post-write state one cycle later (registered cleanly).
    //  valid_next[b] = valid[b] | (current write mask if it targets bank b)
    // -----------------------------------------------------------------------
    logic [10:0] valid_next [0:1];

    always_comb begin
        valid_next[0] = valid[0];
        valid_next[1] = valid[1];
        if (w_en && bank_free[write_bank])
            valid_next[write_bank][waddr] = 1'b1;
    end
    
    
    // -----------------------------------------------------------------------
    //  Sequential write + bank_valid update
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            valid[0]      <= 11'b0;
            valid[1]      <= 11'b0;
            bank_valid    <= 2'b00;
            for (int b = 0; b < 2; b++)
                for (int k = 0; k <= NUM_ROUNDS; k++)
                    mem[b][k] <= '0;
        end else begin
            if (w_en && bank_free[write_bank]) begin
                mem[write_bank][waddr] <= wkey;
                valid[write_bank]      <= valid_next[write_bank];
            end
            // BUG-3 fix: bank_valid uses valid_next (includes this cycle's write)
            bank_valid[0] <= &valid_next[0];
            bank_valid[1] <= &valid_next[1];
        end
    end

    // -----------------------------------------------------------------------
    //  Read port: continuous assignment from mem[]
    // -----------------------------------------------------------------------
    always_comb begin
        for (int b = 0; b < 2; b++)
            for (int k = 0; k <= NUM_ROUNDS; k++)
                round_keys[b][k] = mem[b][k];
    end


endmodule 
*/

module keymem_dual(

    input  logic clk,
    input  logic reset,

    input  logic        w_en,
    input  logic [3:0]  waddr,
    input  aes_block_t  wkey,

    input  logic        write_bank,

    input  logic [1:0]  bank_busy,
    output rk_store_t   round_keys,
    output logic [1:0]  bank_valid,
    output logic [1:0]  bank_free

);


aes_block_t mem [2][NUM_ROUNDS+1];
logic [10:0] valid [2];
logic [10:0] valid_next [2];
//-------------------------------------
// bank availability
//-------------------------------------
assign bank_free[0] =
        !bank_busy[0]
    &&  !bank_valid[0];
assign bank_free[1] =
        !bank_busy[1]
    &&  !bank_valid[1];
//-------------------------------------
// predict next valid state
//-------------------------------------

always_comb begin
    valid_next = valid;
    if(w_en && bank_free[write_bank])
        valid_next[write_bank][waddr] = 1;
end
//-------------------------------------
// sequential write
//-------------------------------------
always_ff @(posedge clk) begin
    if(reset) begin
        valid[0] <= 0;
        valid[1] <= 0;
        bank_valid <= 0;
        for(int b=0;b<2;b++)
            for(int r=0;r<=NUM_ROUNDS;r++)
                mem[b][r] <= 0;
    end
    else begin

        if(w_en && bank_free[write_bank]) begin
            mem[write_bank][waddr] <= wkey;
            valid[write_bank] <= valid_next[write_bank];
        end
        bank_valid[0] <= &valid_next[0];
        bank_valid[1] <= &valid_next[1];
    end
end



//-------------------------------------
// continuous read bus
//-------------------------------------

always_comb begin
    for(int b=0;b<2;b++)
        for(int r=0;r<=NUM_ROUNDS;r++)
            round_keys[b][r] = mem[b][r];

end

endmodule
