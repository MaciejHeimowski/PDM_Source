module memory #(
    parameter CAPACITY = 256,
    parameter WIDTH = 8,
    parameter IDX_BITS = $clog2(CAPACITY)
) (
    input clk_i,

    input [WIDTH-1:0] data_i,
    output [WIDTH-1:0] data_o,

    input read_i, write_i,

    input [IDX_BITS-1:0] write_addr_i,
    input [IDX_BITS-1:0] read_addr_i
);

    reg [WIDTH-1:0] memory [CAPACITY-1:0];

    reg [WIDTH-1:0] mem_buf;

    assign data_o = mem_buf;

    integer i;

    initial begin
        for(i = 0; i < 256; i = i + 1) begin
            memory[i] = 0;
        end 
    end

    always @(posedge clk_i) begin
        if (read_i) begin
            mem_buf <= memory[read_addr_i];
        end
        if (write_i) begin
            memory[write_addr_i] <= data_i;
        end
    end
    
endmodule
