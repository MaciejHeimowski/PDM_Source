module K_ALU (
    // Source register inputs
    input signed [7:0] src_a_i,
    input signed [7:0] src_b_i,

    // Carry-in input
    input cin_i,

    // Operation selection inputs
    input add_en_i, sub_en_i, and_en_i, or_en_i, xor_en_i, lsh_en_i, ash_en_i,

    // Destination register output
    output [7:0] dest_o,

    // Flag outputs
    output flag_C, flag_Z, flag_P, flag_S, flag_V
);

    wire [15:0] lshl_ext;
    wire [15:0] lshr_ext;
    wire [15:0] ashl_ext;
    wire [15:0] ashr_ext;

    assign lshr_ext = (src_a_i << 8) >> src_b_i[3:0];
    assign lshl_ext = src_a_i << -src_b_i[3:0];
    assign ashr_ext = (src_a_i << 8) >>> src_b_i[3:0];
    assign ashl_ext = src_a_i <<< -src_b_i[3:0];


    wire [7:0] adder_o;
    wire adder_cout;
    wire [7:0] adder_B;

    assign adder_B = sub_en_i ? ~src_b_i : src_b_i;

    K_ADDER adder_0(
        .A_i(src_a_i),
        .B_i(adder_B),
        .cin_i(cin_i),
        .Y_o(adder_o),
        .cout_o(adder_cout)
    );

    assign dest_o = add_en_i ? adder_o :
                    sub_en_i ? adder_o :
                    lsh_en_i ? ((src_b_i[3] == 0) ? lshr_ext[15:8] : lshl_ext[7:0]) :
                    ash_en_i ? ((src_b_i[3] == 0) ? ashr_ext[15:8] : ashl_ext[7:0]) :
                    xor_en_i ? src_a_i ^ src_b_i :
                    and_en_i ? src_a_i & src_b_i :
                    or_en_i  ? src_a_i | src_b_i : 0;
    
    assign flag_C = add_en_i ? adder_cout :
                    sub_en_i ? adder_cout :
                    lsh_en_i ? ((src_b_i[3] == 0) ? (lshr_ext[7:0] != 0) : (lshl_ext[15:8] != 0)) :
                    ash_en_i ? ((src_b_i[3] == 0) ? (ashr_ext[7:0] != 0) : (ashl_ext[15:8] != 0)) : 0;
    assign flag_Z = ~(|dest_o[7:0]);
    assign flag_P = dest_o[0];
    assign flag_S = dest_o[7];
    assign flag_V = add_en_i ? ((~src_a_i[7] & ~src_b_i[7] & dest_o[7]) | (src_a_i[7] & src_b_i[7] & ~dest_o[7])) :
                    sub_en_i ? ((~src_a_i[7] & src_b_i[7] & dest_o[7]) | (src_a_i[7] & ~src_b_i[7] & ~dest_o[7])) :
                    lsh_en_i ? (src_a_i[7] ^ dest_o[7]) :
                    ash_en_i ? (src_a_i[7] ^ dest_o[7]) : 0;

endmodule
