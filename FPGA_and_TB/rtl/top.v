module top #(
    parameter integer FLASH_SPI_DIV = 48,
    parameter integer FLASH_RESET_WAIT_CYCLES = 4096
) (
    input clk_i,
    input nrst_i,

    input cpu_en_i,

    input int_i,

    input  flash_MISO_i,
    output reg flash_MOSI_o,
    output reg flash_SCK_o,
    output reg flash_NSS_o,

    inout [3:0] port_io
);

    wire [15:0] instr_addr;
    wire instr_valid;
    wire [15:0] instr;
    wire [15:0] data_addr;
    wire data_store_en;
    wire data_load_en;
    wire data_valid;
    wire data_store_complete;
    wire [7:0] data_cpu_to_memory;
    wire [7:0] data_memory_to_cpu;

    wire [7:0] data_controller_to_cache;
    wire [7:0] data_cache_to_controller;
    wire cache_read;
    wire cache_write;
    wire [7:0] cache_addr;

    wire flash_MOSI, flash_SCK, flash_NSS;

    reg [1:0] int_sync, cpu_en_sync;
    wire interrupt, cpu_en;

    assign interrupt = int_sync[1];
    assign cpu_en = cpu_en_sync[1];

    reg [3:0] port_in;
    wire [3:0] port_out;
    wire [3:0] port_dir;
    
    assign port_io[0] = port_dir[0] ? port_out[0] : 1'bz; 
    assign port_io[1] = port_dir[1] ? port_out[1] : 1'bz; 
    assign port_io[2] = port_dir[2] ? port_out[2] : 1'bz; 
    assign port_io[3] = port_dir[3] ? port_out[3] : 1'bz; 

    always @(negedge nrst_i, posedge clk_i) begin
        if (!nrst_i) begin
            {flash_MOSI_o, flash_SCK_o} <= 0;
            flash_NSS_o <= 1;
            port_in <= 0;
            int_sync <= 2'b0;
            cpu_en_sync <= 2'b0;
        end else begin
            {flash_MOSI_o, flash_SCK_o, flash_NSS_o} <= {flash_MOSI, flash_SCK, flash_NSS};
            port_in <= port_io;
            int_sync <= {int_sync[0], int_i};
            cpu_en_sync <= {cpu_en_sync[0], cpu_en_i};
        end
    end
 
    wire branch;

    KAMP_top kamp (
        .clk_i(clk_i),
        .rst_i(!nrst_i),
        .cpu_en_i(cpu_en),
        .instr_addr_o(instr_addr),
        .instr_valid_i(instr_valid),
        .instr_i(instr),
        .branch_o(branch),
        .data_addr_o(data_addr),
        .data_store_en_o(data_store_en),
        .data_load_en_o(data_load_en),
        .data_valid_i(data_valid),
        .data_store_complete_i(data_store_complete),
        .data_o(data_cpu_to_memory),
        .data_i(data_memory_to_cpu),
        .int_i(interrupt)
    );

    memory_controller #(
        .FLASH_SPI_DIV              (FLASH_SPI_DIV),
        .FLASH_RESET_WAIT_CYCLES    (FLASH_RESET_WAIT_CYCLES)
    ) memory_controller (
        .clk_i                (clk_i),
        .nrst_i               (nrst_i),
        .instr_addr_i         (instr_addr),
        .instr_valid_o        (instr_valid),
        .instr_o              (instr),
        .branch_i             (branch),
        .data_addr_i          (data_addr),
        .data_store_en_i      (data_store_en),
        .data_load_en_i       (data_load_en),
        .data_valid_o         (data_valid),
        .data_store_complete_o(data_store_complete),
        .data_o               (data_memory_to_cpu),
        .data_i               (data_cpu_to_memory),
        .flash_MISO_i         (flash_MISO_i),
        .flash_MOSI_o         (flash_MOSI),
        .flash_SCK_o          (flash_SCK),
        .flash_NSS_o          (flash_NSS),
        .port_o               (port_out),
        .port_i               (port_in),
        .port_dir_o           (port_dir),
        .cache_addr_o         (cache_addr),
        .cache_write_o        (cache_write),
        .cache_read_o         (cache_read),
        .cache_data_o         (data_controller_to_cache),
        .cache_data_i         (data_cache_to_controller)
    );

    memory #(
        .CAPACITY(256),
        .WIDTH   (8)
    ) cache (
        .clk_i       (clk_i),
        .data_i      (data_controller_to_cache),
        .data_o      (data_cache_to_controller),
        .read_i      (cache_read),
        .write_i     (cache_write),
        .write_addr_i(cache_addr),
        .read_addr_i (cache_addr)
    );

endmodule
