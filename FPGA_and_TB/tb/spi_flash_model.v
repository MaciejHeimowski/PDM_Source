module spi_flash_model #(
    parameter HEX_FILE = "flash_contents.hex",
    parameter FLASH_SIZE = 65536
) (
    output reg  MISO_o,
    input  wire MOSI_i,
    input  wire SCK_i,
    input  wire NSS_i
);

    reg [7:0] memory [0:FLASH_SIZE-1];

    integer i;

    initial begin
        for (i = 0; i < FLASH_SIZE; i = i + 1) begin
            memory[i] = 8'd0;
        end
        if (HEX_FILE != "") begin
            $readmemh(HEX_FILE, memory);
        end
    end

    localparam CMD  = 2'd0;
    localparam ADDR = 2'd1;
    localparam DATA = 2'd2;

    reg [2:0] state;

    reg [4:0] bit_idx_counter;

    reg [7:0] rx_byte;

    reg [23:0] address;

    reg [7:0] output_byte;

    localparam READ_COMMAND = 8'h03;

    always @(posedge NSS_i, SCK_i) begin
        if (NSS_i) begin
            // NSS goes high - reset everything
            state <= CMD;
            bit_idx_counter <= 0;
            rx_byte <= 0;
            address <= 0;
            MISO_o <= 0;
        end else if (SCK_i) begin
            // SCK posedge - shift input data
            case (state)
                CMD: begin
                    if (bit_idx_counter < 7) begin
                        rx_byte <= {rx_byte[6:0], MOSI_i};
                        bit_idx_counter <= bit_idx_counter + 1;
                    end else begin
                        bit_idx_counter <= 0;
                        if ({rx_byte[6:0], MOSI_i} == READ_COMMAND) begin
                            state <= ADDR;
                        end
                    end
                end
                ADDR: begin
                    address <= {address[22:0], MOSI_i};
                    if (bit_idx_counter < 23) begin
                        bit_idx_counter <= bit_idx_counter + 1;
                    end else begin
                        bit_idx_counter <= 0;
                        output_byte <= memory[{address[22:0], MOSI_i}];
                        state <= DATA;
                    end
                end
                DATA: begin
                    bit_idx_counter <= bit_idx_counter + 1;
                    if (bit_idx_counter == 7) begin
                        bit_idx_counter <= 0;
                        address <= address + 1;
                        output_byte <= memory[(address + 1)];
                    end
                end
                default: begin
                    
                end
            endcase
        end else begin
            // SCK negedge - shift output data
            if (state == DATA) begin
                MISO_o <= output_byte[7];
                output_byte <= {output_byte[6:0], 1'b0};
            end else begin
                MISO_o <= 0;
            end
        end
    end

endmodule
