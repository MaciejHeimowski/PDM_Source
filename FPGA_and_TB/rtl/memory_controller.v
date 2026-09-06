module memory_controller #(
    parameter integer FLASH_SPI_DIV = 48,
    parameter integer FLASH_RESET_WAIT_CYCLES = 4096
) (
    // --- Clock and reset ---
    input  wire clk_i,                 // System clock
    input  wire nrst_i,                // Active-low async reset

    // --- Processor instruction memory interface ---
    input  wire [15:0] instr_addr_i,   // Requested instruction address
    output reg  instr_valid_o,         // Instruction from requested address is available
    output reg  [15:0] instr_o,        // Instruction contents output

    // --- Processor data memory interface ---
    input  wire [15:0] data_addr_i,    // Requested data address
    input  wire data_store_en_i,       // Data store request
    input  wire data_load_en_i,        // Data load request
    output reg  data_valid_o,          // Requested data to load is available
    output reg  data_store_complete_o, // Store operation completed
    output reg  [7:0] data_o,          // Data output to processor
    input  wire [7:0] data_i,          // Data input from processor

    // --- Branch input ---
    input branch_i,

    // --- Flash SPI interface ---
    input  wire flash_MISO_i,          // Flash MISO - data from flash to controller
	output wire flash_MOSI_o,          // Flash MOSI - data from controller to flash
	output wire flash_SCK_o,           // Flash SCK  - serial clock
	output wire flash_NSS_o,           // Flash NSS  - flash active-low chip select ,

    // --- GPIO port ---
    output reg  [3:0] port_o,
    input       [3:0] port_i,
    output reg  [3:0] port_dir_o,

    // --- Cache interface ---
    // Cache memory is assumed to have a one-cycle read and write - data is outputted on the positive clock edge
    // when cache_read_o is high and stored on the positive clock edge when cache_write_o is high
    output reg  [7:0] cache_addr_o,    // Cache memory address
    output reg  cache_write_o,         // Cache write enable
    output reg  cache_read_o,          // Cache read enable
    output reg  [7:0] cache_data_o,    // Cache data output
    input  wire [7:0] cache_data_i     // Cache data input
);

    // Code segment for 24-bit instruction addressing
    reg [7:0] code_segment, code_segment_comb;

    wire branch_delayed;

    // Cache page
    reg [16:0] loaded_page, loaded_page_comb;
    wire [16:0] requested_page;
    // A code-segment write prepares the segment for the next branch.
    wire [7:0] requested_code_segment;
    assign requested_code_segment = branch_delayed ? code_segment : loaded_page[16:9];
    assign requested_page = {requested_code_segment, instr_addr_i[15:7]};

    wire [6:0] loader_addr;
    wire [7:0] loader_data;
    wire loader_write_en;
    reg loader_start_comb;
    wire loader_done;

    localparam START     = 3'd0;
    localparam LOADING   = 3'd1;
    localparam INSTR_H   = 3'd2;
    localparam INSTR_L   = 3'd3;
    localparam DATA      = 3'd4;
    localparam DATA_REG  = 3'd5;
    localparam EXECUTE   = 3'd6;
    localparam HALT      = 3'd7;

    reg [2:0] state, state_comb;

    reg [7:0] instr_h_buf, instr_h_buf_comb;
    reg [7:0] instr_l_buf, instr_l_buf_comb;

    reg [3:0] port_out, port_out_comb;
    reg [3:0] port_dir, port_dir_comb;
    reg [3:0] port_in, port_in_comb;

    flash_loader #(
        .SPI_DIV          (FLASH_SPI_DIV),
        .RESET_WAIT_CYCLES(FLASH_RESET_WAIT_CYCLES)
    ) flash_loader (
        .clk_i      (clk_i),
        .nrst_i     (nrst_i),
        .MISO_i     (flash_MISO_i),
        .MOSI_o     (flash_MOSI_o),
        .SCK_o      (flash_SCK_o),
        .NSS_o      (flash_NSS_o),
        .page_i     (requested_page),
        .data_addr_o(loader_addr),
        .data_o     (loader_data),
        .write_en_o (loader_write_en),
        .start_i    (loader_start_comb),
        .done_o     (loader_done)
    );

    delay #(
        .WIDTH (1),
        .CYCLES(1)
     ) delay (
        .clk_i (clk_i),
        .nrst_i(nrst_i),
        .in_i  (branch_i),
        .out_o (branch_delayed)
    );

    always @* begin
        code_segment_comb = code_segment;
        loaded_page_comb = loaded_page;
        loader_start_comb = 0;

        state_comb = state;

        instr_h_buf_comb = instr_h_buf;
        instr_l_buf_comb = instr_l_buf;

        instr_valid_o = 0;
        instr_o = {instr_h_buf, instr_l_buf};

        data_valid_o = 0;
        data_store_complete_o = 0;
        data_o = 0;

        cache_addr_o = 0;
        cache_read_o = 0;
        cache_write_o = 0;
        cache_data_o = 0;

        port_out_comb = port_out;
        port_o = port_out;

        port_dir_comb = port_dir;
        port_dir_o = port_dir;

        port_in_comb = port_i;

        case (state)
            START: begin
                loader_start_comb = 1;
                state_comb = LOADING;
                cache_write_o = loader_write_en;
                cache_data_o = loader_data;
            end
            LOADING: begin
                cache_addr_o = {1'b0, loader_addr};
                cache_write_o = loader_write_en;
                cache_data_o = loader_data;
                if (loader_done) begin
                    state_comb = INSTR_H;
                end
            end
            INSTR_H: begin
                if (requested_page != loaded_page) begin
                    loaded_page_comb = requested_page;
                    state_comb = START;
                end else begin
                    cache_addr_o = {1'b0, instr_addr_i[6:1], 1'b0};
                    cache_read_o = 1;
                    state_comb = INSTR_L;
                end
            end
            INSTR_L: begin
                instr_h_buf_comb = cache_data_i;
                cache_addr_o = {1'b0, instr_addr_i[6:1], 1'b1};
                cache_read_o = 1;
                state_comb = EXECUTE;
            end
            DATA: begin
                instr_valid_o = 1;
                if (data_load_en_i | data_store_en_i) begin
                    if (data_addr_i == 16'hff00) begin
                        if (data_store_en_i) begin
                            port_dir_comb = data_i[3:0];
                        end
                    end else if (data_addr_i == 16'hff01) begin
                        if (data_store_en_i) begin
                            port_out_comb = data_i[3:0];
                        end
                    end else if (data_addr_i == 16'hff02) begin
                        //
                    end else if (data_addr_i == 16'hff10) begin
                        if (data_store_en_i) begin
                            code_segment_comb = data_i;
                        end
                    end else begin
                        cache_addr_o = {1'b1, data_addr_i[6:0]};
                        if (data_store_en_i) begin
                            cache_write_o = 1;
                            cache_data_o = data_i;
                        end else if (data_load_en_i) begin
                            cache_read_o = 1;
                        end
                    end
                    state_comb = DATA_REG;
                end
            end
            DATA_REG: begin
                instr_valid_o = 1;
                if (data_load_en_i) begin
                    data_valid_o = 1;
                    if (data_addr_i == 16'hff00) begin
                        data_o = {4'b0, port_dir};
                    end else if (data_addr_i == 16'hff01) begin
                        data_o = {4'b0, port_out};
                    end else if (data_addr_i == 16'hff02) begin
                        data_o = {4'b0, port_in};
                    end else if (data_addr_i == 16'hff10) begin
                        data_o = code_segment;
                    end else begin
                        data_o = cache_data_i;
                    end
                    state_comb = INSTR_H;
                end else if (data_store_en_i) begin
                    data_store_complete_o = 1;
                    state_comb = INSTR_H;
                end
            end
            EXECUTE: begin
                instr_l_buf_comb = cache_data_i;
                instr_o = {instr_h_buf, cache_data_i};
                instr_valid_o = 1;
                if (data_load_en_i | data_store_en_i) begin
                    state_comb = DATA;
                end else if (instr_o == 16'h0000) begin
                    state_comb = HALT;
                end else begin
                    state_comb = INSTR_H;
                end
            end
            HALT: begin
                state_comb = HALT;
            end
            default: begin
                
            end
        endcase
    end

    always @(negedge nrst_i, posedge clk_i) begin
        if (!nrst_i) begin
            code_segment <= 0;
            loaded_page <= 0;
            state <= START;
            instr_h_buf <= 0;
            instr_l_buf <= 0;
            port_out <= 0;
            port_dir <= 0;
            port_in  <= 0;
        end else begin
            code_segment <= code_segment_comb;
            loaded_page <= loaded_page_comb;
            state <= state_comb;
            instr_h_buf <= instr_h_buf_comb;
            instr_l_buf <= instr_l_buf_comb;
            port_out <= port_out_comb;
            port_dir <= port_dir_comb;
            port_in <= port_in_comb;
        end
    end

endmodule
