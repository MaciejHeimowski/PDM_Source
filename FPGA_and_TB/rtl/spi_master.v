module spi_master #(
    // Maximum possible clock divider
    parameter MAX_DIV = 16,
    // Delay in system clocks from SCK edge to MISO change
    parameter MISO_DELAY_FROM_SCK = 0,
    // Number of bits required for clock divider
    parameter DIV_BITS = $clog2(MAX_DIV) + 1
) (
    // Clock and reset
    input clk_i,
    input nrst_i,

    // SPI ports
    input MISO_i,
    output reg MOSI_o,
    output reg SCK_o,
    output reg NSS_o,

    // Operating parameters
    input [DIV_BITS-1:0] clk_div_i,
    input [1:0] mode_i,
    input MSB_first_i,

    // TX data
    input [7:0] tx_data_i,
    // TX data valid
    input tx_data_valid_i,
    // New TX byte mark
    output reg tx_ready_o,

    // RX data
    output reg [7:0] rx_data_o,
    // RX data valid mark
    output rx_data_valid_o,
    
    // Transfer done
    output reg done_o
);

    // CPOL and CPHA from mode
    wire CPOL, CPHA;
    assign CPOL = mode_i[1];
    assign CPHA = mode_i[0];

    // Clock divider
    reg [DIV_BITS-1:0] div_counter, div_counter_comb;
    reg div_clk, div_clk_comb;
    reg div_new_cycle_comb;

    // State machine
    localparam IDLE   = 4'd0;
    localparam BIT0   = 4'd1;
    localparam BIT1   = 4'd2;
    localparam BIT2   = 4'd3;
    localparam BIT3   = 4'd4;
    localparam BIT4   = 4'd5;
    localparam BIT5   = 4'd6;
    localparam BIT6   = 4'd7;
    localparam BIT7   = 4'd8;
    localparam NSS_DN = 4'd9;
    localparam NSS_UP = 4'd10;
    reg [3:0] state, state_comb;

    // TX / RX registers
    reg [7:0] rx_buf, rx_buf_comb;

    // MOSI sample and RX data valid mark
    reg miso_sample_mark_comb;
    wire miso_sample_mark_delayed_comb;
    reg rx_data_valid_comb;

    delay #(
        .WIDTH (1),
        .CYCLES(MISO_DELAY_FROM_SCK)
    ) miso_delay (
        .clk_i (clk_i),
        .nrst_i(nrst_i),
        .in_i  (miso_sample_mark_comb),
        .out_o (miso_sample_mark_delayed_comb)
    );

    delay #(
        .WIDTH (1),
        .CYCLES(MISO_DELAY_FROM_SCK)
    ) rx_dv_delay (
        .clk_i (clk_i),
        .nrst_i(nrst_i),
        .in_i  (rx_data_valid_comb),
        .out_o (rx_data_valid_o)
    );

    always @* begin
        // Output assignments
        MOSI_o = 0;
        SCK_o = CPOL;
        NSS_o = 0;
        rx_data_o = rx_buf;
        tx_ready_o = 0;
        rx_data_valid_comb = 0;
        done_o = 0;

        // Default comb assignments
        div_counter_comb = div_counter;
        div_clk_comb = div_clk;
        div_new_cycle_comb = 0;
        state_comb = state;
        rx_buf_comb = rx_buf;
        miso_sample_mark_comb = 0;

        if (div_counter < clk_div_i - 1) begin
            div_counter_comb = div_counter + 1;
        end else begin
            div_counter_comb = 0;
        end

        if (div_counter_comb < (clk_div_i / 2)) begin
            div_clk_comb = 0;
        end else begin
            div_clk_comb = 1;
        end

        if (div_counter_comb == 0) begin
            div_new_cycle_comb = 1;
        end else begin
            div_new_cycle_comb = 0;
        end

        case (state)
            IDLE: begin
                NSS_o = 1;
                tx_ready_o = 1;
                done_o = 1;
                if (tx_data_valid_i) begin
                    state_comb = NSS_DN;
                    div_counter_comb = 0;
                end
            end
            NSS_DN: begin
                if (div_new_cycle_comb) begin
                    state_comb = BIT0;
                end
            end
            BIT7, BIT6, BIT5, BIT4, BIT3, BIT2, BIT1, BIT0: begin
                if (MSB_first_i) begin
                    MOSI_o = tx_data_i[7 - (state - BIT0)];
                end else begin
                    MOSI_o = tx_data_i[state - BIT0];
                end
                if ({div_clk, div_clk_comb} == 2'b01) begin
                    miso_sample_mark_comb = 1;
                end
                SCK_o = div_clk ^ CPOL ^ CPHA;
                if (div_new_cycle_comb) begin
                    if (state < BIT7) begin
                        state_comb = state + 1;
                    end else begin
                        tx_ready_o = 1;
                        rx_data_valid_comb = 1;
                        if (tx_data_valid_i) begin
                            state_comb = BIT0;
                        end else begin
                            state_comb = NSS_UP;
                        end
                    end
                end
            end
            NSS_UP: begin
                if (div_new_cycle_comb) begin
                    state_comb = IDLE;
                end
            end
            default: begin
                NSS_o = 1;
                tx_ready_o = 1;
                done_o = 1;
            end
        endcase

        if (miso_sample_mark_delayed_comb) begin
            if(MSB_first_i) begin
                rx_buf_comb = {rx_buf[6:0], MISO_i};
            end else begin
                rx_buf_comb = {MISO_i, rx_buf[7:1]};
            end
        end
    end

    always @(negedge nrst_i, posedge clk_i) begin
        if (!nrst_i) begin
            div_counter <= 0;
            div_clk <= 0;
            state   <= IDLE;
            rx_buf  <= 0;
        end else begin
            div_counter <= div_counter_comb;
            div_clk <= div_clk_comb;
            state   <= state_comb;
            rx_buf  <= rx_buf_comb;
        end
    end

endmodule
