module K_ADDER (
    input [7:0] A_i,
    input [7:0] B_i,
    input cin_i,

    output [7:0] Y_o,
    output cout_o
);

    wire [8:0] Y;

    assign Y = A_i + B_i + cin_i;
    assign Y_o = Y[7:0];
    assign cout_o = Y[8];

endmodule
