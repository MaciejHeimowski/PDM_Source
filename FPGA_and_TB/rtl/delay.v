module delay #(
    parameter WIDTH = 1,
    parameter CYCLES = 1
) (
    input clk_i,
    input nrst_i,

    input [WIDTH-1:0] in_i,
    output [WIDTH-1:0] out_o
);

    if (CYCLES == 0) begin : no_delay
        assign out_o = in_i;
    end else begin : delay
        integer i;
        reg [WIDTH-1:0] delay_stage[CYCLES-1:0];
        always @(negedge nrst_i, posedge clk_i) begin
            if (!nrst_i) begin
                for (i = 0; i < CYCLES; i = i + 1) begin
                    delay_stage[i] <= 0;
                end
            end else begin
                delay_stage[CYCLES - 1] <= in_i;
                for (i = 0; i < CYCLES - 1; i = i + 1) begin
                    delay_stage[i] <= delay_stage[i + 1];
                end
            end
        end

        assign out_o = delay_stage[0];
    end

endmodule
