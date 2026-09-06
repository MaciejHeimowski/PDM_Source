module K_REGS (
    // Clock input
    input clk_i,

    // Async reset
    input rst_i,

    // Destination register address input
    input [3:0] dest_addr_i,

    // Source registers address inputs
    input [3:0] src_a_addr_i,
    input [3:0] src_b_addr_i,

    // Registers update enable
    input update_en_i,

    // Destination register write enable
    input dest_write_en_i,

    // Flags write enable
    input flag_write_en_i,

    // Flag inputs
    input flag_C_i, flag_Z_i, flag_P_i, flag_S_i, flag_V_i,

    // Source registers read enable
    output reg [7:0] src_a_o,
    output reg [7:0] src_b_o,

    // Destination register write input
    input [7:0] dest_i,

    // Flag outputs
    output flag_C_o, flag_Z_o, flag_P_o, flag_S_o, flag_V_o,

    // Pointer output
    output [15:0] pointer_o
);

    // Special purpose register addresses
    localparam ZERO_ADDR = 4'b0000;
    localparam FLAG_ADDR = 4'b0001;
    localparam HPT_ADDR = 4'b0010;
    localparam LPT_ADDR = 4'b0011;
    
    reg [7:0] regs [15:1];
    
    integer i;

    // Flag outputs assignment
    assign {flag_V_o, flag_S_o, flag_P_o, flag_Z_o, flag_C_o} = regs[1][4:0];
    // Pointer output assignment
    assign pointer_o = {regs[2], regs[3]};

    
    always@(*) 
    begin
        case(src_a_addr_i)
            ZERO_ADDR : src_a_o = 0;
            FLAG_ADDR : src_a_o = regs[1];
            HPT_ADDR  : src_a_o = regs[2];
            LPT_ADDR  : src_a_o = regs[3];
            4'd4      : src_a_o = regs[4];
            4'd5      : src_a_o = regs[5];
            4'd6      : src_a_o = regs[6];
            4'd7      : src_a_o = regs[7];
            4'd8      : src_a_o = regs[8];
            4'd9      : src_a_o = regs[9];
            4'd10     : src_a_o = regs[10];
            4'd11     : src_a_o = regs[11];
            4'd12     : src_a_o = regs[12];
            4'd13     : src_a_o = regs[13];
            4'd14     : src_a_o = regs[14];
            4'd15     : src_a_o = regs[15];
            default   : src_a_o = 0;
        endcase
        
        case(src_b_addr_i)
            ZERO_ADDR : src_b_o = 0;
            FLAG_ADDR : src_b_o = regs[1];
            HPT_ADDR  : src_b_o = regs[2];
            LPT_ADDR  : src_b_o = regs[3];
            4'd4      : src_b_o = regs[4];
            4'd5      : src_b_o = regs[5];
            4'd6      : src_b_o = regs[6];
            4'd7      : src_b_o = regs[7];
            4'd8      : src_b_o = regs[8];
            4'd9      : src_b_o = regs[9];
            4'd10     : src_b_o = regs[10];
            4'd11     : src_b_o = regs[11];
            4'd12     : src_b_o = regs[12];
            4'd13     : src_b_o = regs[13];
            4'd14     : src_b_o = regs[14];
            4'd15     : src_b_o = regs[15];
            default   : src_b_o = 0;
        endcase
    end
    
    always @(posedge clk_i, posedge rst_i) begin
        // rst_i rising edge
        if (rst_i) begin
            // Reset all registers
            for(i = 1; i <= 15; i = i+1)
            begin
                regs[i] <= 0;
            end
        end 
        // clk_i rising edge
        else begin
            // If register update enabled
            if(update_en_i) begin
                // If only flag update is active, not registers, update just flags
                if (flag_write_en_i) begin
                    regs[1][4:0] <= {flag_V_i, flag_S_i, flag_P_i, flag_Z_i, flag_C_i};
                end
                // If destination write is enabled, update the destination register. If the flag register
                // is selected as the destination, the explicitly written value takes priority over the
                // implicit flag update values
                if (dest_write_en_i) begin
                    case(dest_addr_i)
                        FLAG_ADDR : regs[1] <= dest_i[4:0];
                        HPT_ADDR  : regs[2] <= dest_i;
                        LPT_ADDR  : regs[3] <= dest_i;
                        4'd4      : regs[4]  <= dest_i;
                        4'd5      : regs[5]  <= dest_i;
                        4'd6      : regs[6]  <= dest_i;
                        4'd7      : regs[7]  <= dest_i;
                        4'd8      : regs[8]  <= dest_i;
                        4'd9      : regs[9]  <= dest_i;
                        4'd10     : regs[10] <= dest_i;
                        4'd11     : regs[11] <= dest_i;
                        4'd12     : regs[12] <= dest_i;
                        4'd13     : regs[13] <= dest_i;
                        4'd14     : regs[14] <= dest_i;
                        4'd15     : regs[15] <= dest_i;
                        default   : ;
                    endcase
                end
            end
        end
    end

endmodule