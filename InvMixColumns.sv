module InvMixColumns(res, inp);
    input  [127:0] inp;
    output [127:0] res;

    genvar i;
    generate
    for (i = 0; i < 4; i = i + 1)
    begin
        wire [7:0] s0 = inp[127-32*i : 120-32*i];
        wire [7:0] s1 = inp[119-32*i : 112-32*i];
        wire [7:0] s2 = inp[111-32*i : 104-32*i];
        wire [7:0] s3 = inp[103-32*i :  96-32*i];

        assign res[127-32*i : 120-32*i] =
            mul14(s0) ^ mul11(s1) ^ mul13(s2) ^ mul9(s3);

        assign res[119-32*i : 112-32*i] =
            mul9(s0)  ^ mul14(s1) ^ mul11(s2) ^ mul13(s3);

        assign res[111-32*i : 104-32*i] =
            mul13(s0) ^ mul9(s1)  ^ mul14(s2) ^ mul11(s3);

        assign res[103-32*i :  96-32*i] =
            mul11(s0) ^ mul13(s1) ^ mul9(s2)  ^ mul14(s3);
    end
    endgenerate

    // ---------- GF(2^8) helpers ----------
    function automatic [7:0] xtime(input [7:0] x);
        xtime = (x << 1) ^ (x[7] ? 8'h1B : 8'h00);
    endfunction

    function automatic [7:0] mul9(input [7:0] x);
        mul9 = xtime(xtime(xtime(x))) ^ x;
    endfunction

    function automatic [7:0] mul11(input [7:0] x);
        mul11 = xtime(xtime(xtime(x)) ^ x) ^ x;
    endfunction

    function automatic [7:0] mul13(input [7:0] x);
        mul13 = xtime(xtime(xtime(x) ^ x)) ^ x;
    endfunction

    function automatic [7:0] mul14(input [7:0] x);
        mul14 = xtime(xtime(xtime(x) ^ x) ^ x);
    endfunction

endmodule