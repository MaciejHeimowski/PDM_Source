module top_tb;

    reg clk = 0;
    reg nrst = 1;
    reg cpu_en = 1;
    reg interrupt = 0;
    
    wire flash_MISO, flash_MOSI, flash_SCK, flash_NSS;

    wire [3:0] out_port;

    top top (
        .clk_i       (clk),
        .nrst_i      (nrst),
        .cpu_en_i    (cpu_en),
        .int_i       (interrupt),
        .flash_MISO_i(flash_MISO),
        .flash_MOSI_o(flash_MOSI),
        .flash_SCK_o (flash_SCK),
        .flash_NSS_o (flash_NSS),
        .port_io  (out_port)
    );

    spi_flash_model #(
        .HEX_FILE  ("top_tb_prog.hex"),
        .FLASH_SIZE(65536)
     ) spi_flash_model (
        .MISO_o(flash_MISO),
        .MOSI_i(flash_MOSI),
        .SCK_i (flash_SCK),
        .NSS_i (flash_NSS)
    );

    always #1 clk = ~clk;

    wire [7:0] reg4;

    assign reg4 = top.kamp.KAMP_registers.regs[4];

    initial begin
        $display("\n==== TOP TB ====");

        $dumpfile("../vcd/top_tb.vcd");
        $dumpvars(0);

        #2 nrst = 0;
        #2 nrst = 1;

        #200000

        wait(top.instr == 16'h0000);

        #10 $finish;
    end

endmodule
