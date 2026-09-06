module flash_loader #(
    parameter integer SPI_DIV = 48,
    parameter integer RESET_WAIT_CYCLES = 4096
) (
	input clk_i,
    input nrst_i,

	input  wire MISO_i,
	output wire MOSI_o,
	output wire SCK_o,
	output wire NSS_o,

    input  wire [16:0] page_i,

    output wire [6:0] data_addr_o,
    output reg [7:0] data_o,
    output reg write_en_o,

    input  wire start_i,
    output wire done_o
);

    localparam IDLE         = 4'd0;
    localparam EN_RST_INSTR = 4'd1;
    localparam WAIT_1       = 4'd2;
    localparam RST_INSTR    = 4'd3;
    localparam WAIT_2       = 4'd4;
    localparam READ_INSTR   = 4'd5;
    localparam ADDR_H       = 4'd6;
    localparam ADDR_M       = 4'd7;
    localparam ADDR_L       = 4'd8;
    localparam MEM_DATA     = 4'd9;
    localparam WAIT_RX_DONE = 4'd10;

    reg [3:0] state, state_comb;

    localparam integer SPI_DIV_BITS = $clog2(SPI_DIV) + 1;
    localparam [SPI_DIV_BITS-1:0] SPI_DIV_VALUE = SPI_DIV;
    localparam [1:0] SPI_MODE = 2'd0;
    localparam SPI_MSB_FIRST = 1'b1;

    reg [7:0] spi_tx_data, spi_tx_data_comb;
    reg spi_tx_data_valid_comb;
    wire spi_tx_data_ready;

    wire [7:0] rx_data;
    wire rx_data_valid;

    reg [11:0] byte_counter, byte_counter_comb;

    wire spi_done;

    spi_master #(
		.MAX_DIV            (SPI_DIV),
		.MISO_DELAY_FROM_SCK(1)
	) spi_master (
		.clk_i          (clk_i),
		.nrst_i         (nrst_i),
		.MISO_i         (MISO_i),
		.MOSI_o         (MOSI_o),
		.SCK_o          (SCK_o),
		.NSS_o          (NSS_o),
		.clk_div_i      (SPI_DIV_VALUE),
		.mode_i         (SPI_MODE),
		.MSB_first_i    (SPI_MSB_FIRST),
		.tx_data_i      (spi_tx_data),
		.tx_data_valid_i(spi_tx_data_valid_comb && spi_tx_data_ready),
		.tx_ready_o     (spi_tx_data_ready),
		.rx_data_o      (rx_data),
		.rx_data_valid_o(rx_data_valid),
		.done_o         (spi_done)
	);

    wire accepting_data;
    assign accepting_data = (state == MEM_DATA);
    wire accepting_data_delayed;

    delay #(
        .WIDTH (1),
        .CYCLES(1)
    ) accept_data_delay (
        .clk_i (clk_i),
        .nrst_i(nrst_i),
        .in_i  (accepting_data),
        .out_o (accepting_data_delayed)
    );

    delay #(
        .WIDTH (7),
        .CYCLES(1)
    ) addr_delay (
        .clk_i (clk_i),
        .nrst_i(nrst_i),
        .in_i  (byte_counter[6:0]),
        .out_o (data_addr_o)
    );

    assign done_o = (state == IDLE) && spi_done;

    always @* begin
        state_comb = state;
        spi_tx_data_comb = spi_tx_data;
        byte_counter_comb = byte_counter;
        spi_tx_data_valid_comb = 0;

        data_o = rx_data;
        write_en_o = rx_data_valid && accepting_data_delayed;

        case (state)
            IDLE: begin
                if (spi_tx_data_ready && start_i) begin
                    state_comb = EN_RST_INSTR;
                    spi_tx_data_comb = 8'h66;
                    spi_tx_data_valid_comb = 1;
                end
            end
            EN_RST_INSTR: begin
                if (spi_tx_data_ready) begin
                    state_comb = WAIT_1;
                    byte_counter_comb = 0;
                end
            end
            WAIT_1: begin
                if (byte_counter < RESET_WAIT_CYCLES - 1) begin
                    byte_counter_comb = byte_counter + 1;
                end else if (spi_tx_data_ready) begin
                    state_comb = RST_INSTR;
                    spi_tx_data_comb = 8'h99;
                    spi_tx_data_valid_comb = 1;
                end
            end
            RST_INSTR: begin
                if (spi_tx_data_ready) begin
                    state_comb = WAIT_2;
                    byte_counter_comb = 0;
                end
            end
            WAIT_2: begin
                if (byte_counter < RESET_WAIT_CYCLES - 1) begin
                    byte_counter_comb = byte_counter + 1;
                end else if (spi_tx_data_ready) begin
                    state_comb = READ_INSTR;
                    spi_tx_data_comb = 8'h03;
                    spi_tx_data_valid_comb = 1;
                end
            end
            READ_INSTR: begin
                if (spi_tx_data_ready) begin
                    state_comb = ADDR_H;
                    spi_tx_data_comb = page_i[16:9];
                    spi_tx_data_valid_comb = 1;
                end
            end
            ADDR_H: begin
                if (spi_tx_data_ready) begin
                    state_comb = ADDR_M;
                    spi_tx_data_comb = page_i[8:1];
                    spi_tx_data_valid_comb = 1;
                end
            end
            ADDR_M: begin
                if (spi_tx_data_ready) begin
                    state_comb = ADDR_L;
                    spi_tx_data_comb = {page_i[0], 7'b0};
                    spi_tx_data_valid_comb = 1;
                end
            end
            ADDR_L: begin
                if (spi_tx_data_ready) begin
                    state_comb = MEM_DATA;
                    spi_tx_data_comb = 8'b0;
                    byte_counter_comb = 0;
                    spi_tx_data_valid_comb = 1;
                end
            end
            MEM_DATA: begin
                if (spi_tx_data_ready) begin
                    if (byte_counter < 127) begin
                        byte_counter_comb = byte_counter + 1;
                        spi_tx_data_valid_comb = 1;
                    end else begin
                        byte_counter_comb = 0;
                        state_comb = WAIT_RX_DONE;
                    end
                end
            end
            WAIT_RX_DONE: begin
                if (rx_data_valid) begin
                    state_comb = IDLE;
                end
            end
            default: begin
                state_comb = IDLE;
            end
        endcase
    end

    always @(negedge nrst_i, posedge clk_i) begin
        if (!nrst_i) begin
            state <= IDLE;
            spi_tx_data <= 0;
            byte_counter <= 0;
        end else begin
            state <= state_comb;
            spi_tx_data <= spi_tx_data_comb;
            byte_counter <= byte_counter_comb;
        end
    end

endmodule
