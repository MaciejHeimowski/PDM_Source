module K_PC (
    // Clock input
    input clk_i,

    // Async reset
    input rst_i,

    // Interrupt input
    input int_i,

    // Program counter update enable
    input update_en_i,

    // Branch enable (0 - count, 1 - branch)
    input branch_en_i,
    // Branch mode input (0 - absolute, 1 - relative)
    input branch_mode_i,

    // Absolute branch address input
    input [15:0] branch_abs_addr_i,
    // Relative branch address input
    input [7:0] branch_rel_addr_i,
    
    // Instruction address output
    output reg [15:0] instr_addr_o
);

    wire [15:0] branch_rel_addr_extended = $signed(branch_rel_addr_i);

    reg int_prev;
    reg int_pending;

    wire int_rising;
    assign int_rising = ~int_prev & int_i;

    always @(posedge clk_i, posedge rst_i) begin
        // rst_i rising edge
        if (rst_i) begin
            int_prev <= 1'b0;
            int_pending <= 1'b0;
            instr_addr_o <= 16'b0;
        end 
        // clk_i rising edge
        else begin
            // Capture an interrupt edge even while memory has stalled execution.
            int_prev <= int_i;

            // If register update enabled
            if(update_en_i) begin
                // The current instruction completes on this edge
                if (int_pending | int_rising) begin
                    instr_addr_o <= 16'b0;
                    int_pending <= 1'b0;
                end
                // If branch is enabled, the counter is updated with the target address
                else if (branch_en_i) begin
                    if (branch_mode_i)
                        instr_addr_o <= instr_addr_o + branch_rel_addr_extended;
                    else
                        instr_addr_o <= branch_abs_addr_i;
                end
                // Otherwise, the count continues
                else begin
                    // + 2, because each instruction is 2 bytes long, and addressing
                    // has a 1 byte resolution
                    instr_addr_o <= instr_addr_o + 2;
                end
            end else if (int_rising) begin
                int_pending <= 1'b1;
            end
        end
    end

endmodule
