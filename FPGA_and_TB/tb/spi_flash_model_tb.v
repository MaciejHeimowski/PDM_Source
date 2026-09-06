`timescale 1ns/1ps

module tb_spi_flash;

    wire MISO;
    reg MOSI;
    reg SCK;
    reg NSS;

    localparam HEX_FILE = "flash_contents.hex";
    localparam FLASH_SIZE = 65536;

    localparam START_ADDRESS = 24'd128;

    spi_flash_model #(
        .HEX_FILE  (HEX_FILE),
        .FLASH_SIZE(FLASH_SIZE)
     ) spi_flash_model (
        .MISO_o(MISO),
        .MOSI_i(MOSI),
        .SCK_i (SCK),
        .NSS_i (NSS)
    );

    initial begin
        SCK = 0;
    end

    integer i;

    task spi_write_byte (
        input [7:0] data
    );  
        begin
            for (i = 0; i < 8; i = i + 1) begin
                MOSI = data[7 - i];
                #1 SCK = 1;
                #1 SCK = 0;
            end
        end
    endtask

    task spi_read_byte(
        output [7:0] data
    );
        begin
            data = 0;
            for (i = 0; i < 8; i = i + 1) begin
                MOSI = 0;
                #1 SCK = 1;
                data[7 - i] = MISO;
                #1 SCK = 0;
            end
        end
    endtask

    reg [7:0] value;

    integer j;

    reg failed = 0;

    reg [7:0] expected_memory [0:FLASH_SIZE-1];

    initial begin
        $display("\n==== SPI FLASH MODEL TB ====");

        $dumpfile("../vcd/spi_flash_model_tb.vcd");
        $dumpvars(0);

        $readmemh(HEX_FILE, expected_memory);

        NSS = 1;
        MOSI = 0;

        #10 NSS = 0;

        spi_write_byte(8'h03);
        spi_write_byte(START_ADDRESS[23:16]);
        spi_write_byte(START_ADDRESS[15:8]);
        spi_write_byte(START_ADDRESS[7:0]);

        for (j = START_ADDRESS; j < FLASH_SIZE; j = j + 1) begin
            spi_read_byte(value);
            if (expected_memory[j] != value) begin
                $display("Expected to read %02X, received %02X", expected_memory[j], value);
                failed = 1;
            end
        end

        NSS = 1;

        if (failed) begin
            $display("==== Test failed ====\n");
        end else begin
            $display("==== Test succesful ====\n");
        end

        #20 $finish;
    end

endmodule
