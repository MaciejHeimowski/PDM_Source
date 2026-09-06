module K_DECODER (
    input [3:0] opcode_i,
    output [15:0] onehot_o
);

    assign onehot_o = (1 << 15) >> opcode_i;

endmodule
