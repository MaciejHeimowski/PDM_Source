module KAMP_top (
    ///////////////////////////
    // CLOCK, RESET & ENABLE //
    ///////////////////////////

    // Processor clock input
    input clk_i,
    // Async reset
    input rst_i,

    // Enable
    input cpu_en_i,

    //////////////////////////
    // PROGRAM MEMORY PORTS //
    //////////////////////////

    // Instruction address output
    output [15:0] instr_addr_o,

    // Instruction valid input
    input instr_valid_i,

    // Instruction input
    input [15:0] instr_i,

    // Branch output
    output branch_o,


    ///////////////////////
    // DATA MEMORY PORTS //
    ///////////////////////

    // Data address output
    output [15:0] data_addr_o,

    // Data store enable output
    output data_store_en_o,
    // Data load enable output
    output data_load_en_o,

    // Data valid input
    input data_valid_i,
    // Data store complete input
    input data_store_complete_i,

    // Data output
    output [7:0] data_o,
    // Data input
    input [7:0] data_i,

    ////////////////////
    // INTERRUPT PORT //
    ////////////////////

    // Interrupt input
    input int_i
);

    // Instruction bit groups
    wire [3:0] instr_opcode;
    wire [3:0] instr_bits_11_8;
    wire [3:0] instr_bits_7_4;
    wire [3:0] instr_bits_3_0;

    // Instruction selection nets
    wire ctrl_ext;
    wire ctrl_add;
    wire ctrl_sub;
    wire ctrl_addc;
    wire ctrl_subc;
    wire ctrl_and;
    wire ctrl_or;
    wire ctrl_xor;
    wire ctrl_lsh;
    wire ctrl_ash;
    wire ctrl_li;
    wire ctrl_addi;
    wire ctrl_ld;
    wire ctrl_st;
    wire ctrl_br;
    wire ctrl_b;

    // Source registers outputs
    wire [7:0] regs_src_a;
    wire [7:0] regs_src_b;

    // Source registers address inputs
    wire [3:0] regs_src_a_addr;
    wire [3:0] regs_src_b_addr;

    // Destination register input
    wire [7:0] regs_dest;

    // Destination register address input
    wire [3:0] regs_dest_addr;

    // Flags write enable
    wire regs_flag_write_en;
    
    // Destination register write enable
    wire regs_dest_write_en;

    // Pointer registers output
    wire [15:0] regs_pointer;

    // Immediate
    wire [7:0] alu_immediate;

    // ALU source inputs
    wire [7:0] alu_src_a;
    wire [7:0] alu_src_b;

    // ALU destination output
    wire [7:0] alu_dest;
    
    // ALU flag outputs
    wire alu_flag_C, alu_flag_Z, alu_flag_P, alu_flag_S, alu_flag_V;

    // Flags committed to the register file
    wire regs_flag_C, regs_flag_Z, regs_flag_P, regs_flag_S, regs_flag_V;

    // ALU carry-in
    wire alu_cin;

    // ALU operations enable
    wire alu_add_en, alu_sub_en, alu_and_en, alu_or_en, alu_xor_en, alu_ash_en, alu_lsh_en;

    // Flags register condition outputs
    wire cond_flag_C, cond_flag_Z, cond_flag_P, cond_flag_S, cond_flag_V;

    // Condition code
    wire [3:0] cond_code;

    // Condition met
    wire cond_met;

    // Program counter branch enable
    wire pc_branch_en;

    // Program counter branch mode
    wire pc_branch_mode;
    // Program counter branch addresses
    wire [15:0] pc_branch_abs_addr;
    wire [7:0] pc_branch_rel_addr;

    // Wait until memory operation finished
    wire wait_for_memory;

    // Ready to proceed with program execution
    wire running;

    assign {instr_opcode, instr_bits_11_8, instr_bits_7_4, instr_bits_3_0} = instr_i;

    assign regs_flag_write_en =
        (ctrl_add |
        ctrl_sub |
        ctrl_addc |
        ctrl_subc |
        ctrl_and |
        ctrl_or |
        ctrl_xor |
        ctrl_lsh |
        ctrl_ash |
        ctrl_addi |
        ctrl_ld);

    assign regs_dest =
        ctrl_li ? alu_immediate :
        ctrl_ld ? data_i :
        alu_dest;

    assign regs_dest_write_en = (regs_flag_write_en | ctrl_li);

    assign regs_flag_C = ctrl_ld ? 1'b0       : alu_flag_C;
    assign regs_flag_Z = ctrl_ld ? ~(|data_i) : alu_flag_Z;
    assign regs_flag_P = ctrl_ld ? data_i[0]  : alu_flag_P;
    assign regs_flag_S = ctrl_ld ? data_i[7]  : alu_flag_S;
    assign regs_flag_V = ctrl_ld ? 1'b0       : alu_flag_V;

    assign data_addr_o = regs_pointer + {{8{alu_immediate[7]}}, alu_immediate};
    assign data_o = data_store_en_o ? regs_src_a : 8'b0;

    assign data_store_en_o = ctrl_st & cpu_en_i;
    assign data_load_en_o = ctrl_ld & cpu_en_i;

    assign alu_immediate =
        ctrl_addi ? {{4{instr_bits_3_0[3]}}, instr_bits_3_0} :
        ctrl_lsh | ctrl_ash ? instr_bits_3_0 :
        ctrl_li | ctrl_ld | ctrl_br     ? {instr_bits_7_4, instr_bits_3_0} :
        ctrl_st                         ? {instr_bits_11_8, instr_bits_3_0} :
        0;

    assign alu_src_a = ctrl_li | ctrl_ld | ctrl_st | ctrl_br | ctrl_b ? 0 : regs_src_a;
    assign alu_src_b = 
        ctrl_lsh | ctrl_ash | ctrl_addi ? alu_immediate :
        ctrl_ld | ctrl_st | ctrl_br     ? 0 :
        regs_src_b;

    assign regs_dest_addr  = instr_bits_11_8;
    assign regs_src_a_addr = instr_bits_7_4;
    assign regs_src_b_addr = instr_bits_3_0;

    assign alu_cin = ctrl_addc | ctrl_subc ? cond_flag_C : 
                     ctrl_sub ? 1'b1 :
                     0;

    assign alu_add_en = ctrl_add | ctrl_addc | ctrl_addi;
    assign alu_sub_en = ctrl_sub | ctrl_subc;
    assign alu_and_en = ctrl_and;
    assign alu_or_en  = ctrl_or;
    assign alu_xor_en = ctrl_xor;
    assign alu_ash_en = ctrl_ash;
    assign alu_lsh_en = ctrl_lsh;

    assign cond_code = instr_bits_11_8;
    assign cond_met =
        (cond_code == 4'b1111) ? 1 :
        (cond_code == 4'b1110) ? 0 :
        (cond_code == 4'b1001) ? cond_flag_V :
        (cond_code == 4'b1000) ? !cond_flag_V :
        (cond_code == 4'b0111) ? cond_flag_S :
        (cond_code == 4'b0110) ? !cond_flag_S :
        (cond_code == 4'b0101) ? cond_flag_P :
        (cond_code == 4'b0100) ? !cond_flag_P :
        (cond_code == 4'b0011) ? cond_flag_Z :
        (cond_code == 4'b0010) ? !cond_flag_Z :
        (cond_code == 4'b0001) ? cond_flag_C :
        (cond_code == 4'b0000) ? !cond_flag_C :
        0;

    assign pc_branch_en = (ctrl_b | ctrl_br) & cond_met;
    
    assign branch_o = pc_branch_en & running;

    assign pc_branch_mode = ctrl_br;

    assign pc_branch_abs_addr = {regs_src_a, regs_src_b};
    assign pc_branch_rel_addr = {instr_bits_7_4, instr_bits_3_0};
    
    assign wait_for_memory =
        (~instr_valid_i) |
        (ctrl_ld & (~data_valid_i)) |
        (ctrl_st & (~data_store_complete_i));

    assign running = cpu_en_i & (~wait_for_memory);

    // Instruction opcode decoder
    K_DECODER KAMP_instruction_decoder (
        .opcode_i(instr_opcode),
        .onehot_o({
            ctrl_ext,
            ctrl_add,
            ctrl_sub,
            ctrl_addc,
            ctrl_subc,
            ctrl_and,
            ctrl_or,
            ctrl_xor,
            ctrl_lsh,
            ctrl_ash,
            ctrl_li,
            ctrl_addi,
            ctrl_ld,
            ctrl_st,
            ctrl_br,
            ctrl_b
        })
    );

    // Program counter
    K_PC KAMP_program_counter (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .int_i(int_i),

        .update_en_i(running),

        .branch_en_i(pc_branch_en),
        .branch_mode_i(pc_branch_mode),

        .branch_abs_addr_i(pc_branch_abs_addr),
        .branch_rel_addr_i(pc_branch_rel_addr),

        .instr_addr_o(instr_addr_o)
    );

    // Registers
    K_REGS KAMP_registers (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .dest_addr_i(regs_dest_addr),
        .src_a_addr_i(regs_src_a_addr),
        .src_b_addr_i(regs_src_b_addr),

        .update_en_i(running),

        .dest_write_en_i(regs_dest_write_en),
        .flag_write_en_i(regs_flag_write_en),

        .flag_C_i(regs_flag_C),
        .flag_Z_i(regs_flag_Z),
        .flag_P_i(regs_flag_P),
        .flag_S_i(regs_flag_S),
        .flag_V_i(regs_flag_V),

        .src_a_o(regs_src_a),
        .src_b_o(regs_src_b),
        .dest_i(regs_dest),

        .flag_C_o(cond_flag_C),
        .flag_Z_o(cond_flag_Z),
        .flag_P_o(cond_flag_P),
        .flag_S_o(cond_flag_S),
        .flag_V_o(cond_flag_V),

        .pointer_o(regs_pointer)
    );

    // ALU
    K_ALU KAMP_ALU (
        .src_a_i(alu_src_a),
        .src_b_i(alu_src_b),

        .cin_i(alu_cin),

        .add_en_i(alu_add_en),
        .sub_en_i(alu_sub_en),
        .and_en_i(alu_and_en),
        .or_en_i(alu_or_en),
        .xor_en_i(alu_xor_en),
        .lsh_en_i(alu_lsh_en),
        .ash_en_i(alu_ash_en),

        .dest_o(alu_dest),

        .flag_C(alu_flag_C),
        .flag_Z(alu_flag_Z),
        .flag_P(alu_flag_P),
        .flag_S(alu_flag_S),
        .flag_V(alu_flag_V)
    );

endmodule
