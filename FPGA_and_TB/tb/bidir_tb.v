module top_tb;

    reg clk = 0;
    reg nrst = 1;
    reg cpu_en = 1;
    reg interrupt = 0;
    
    wire flash_MISO, flash_MOSI, flash_SCK, flash_NSS;

    wire [3:0] gpio_port;
    reg [1:0] gpio_inputs = 2'b00;
    assign gpio_port[1:0] = gpio_inputs;
    wire [1:0] gpio_outputs;
    assign gpio_outputs = gpio_port[3:2];

    top top (
        .clk_i       (clk),
        .nrst_i      (nrst),
        .cpu_en_i    (cpu_en),
        .int_i       (interrupt),
        .flash_MISO_i(flash_MISO),
        .flash_MOSI_o(flash_MOSI),
        .flash_SCK_o (flash_SCK),
        .flash_NSS_o (flash_NSS),
        .port_io     (gpio_port)
    );

    spi_flash_model #(
        .HEX_FILE  ("bidir_tb_prog.hex"),
        .FLASH_SIZE(65536)
     ) spi_flash_model (
        .MISO_o(flash_MISO),
        .MOSI_i(flash_MOSI),
        .SCK_i (flash_SCK),
        .NSS_i (flash_NSS)
    );

    always #1 clk = ~clk;

    wire [7:0] r4, r5;
    assign r4 = top.kamp.KAMP_registers.regs[4];
    assign r5 = top.kamp.KAMP_registers.regs[5];

    initial begin
        $display("\n==== TOP TB ====");

        $dumpfile("../vcd/bidir_tb.vcd");
        $dumpvars(0);

        #2 nrst = 0;
        #2 nrst = 1;

        #100

        while (gpio_inputs != 2'b11) begin
            wait(gpio_outputs == gpio_inputs)
            gpio_inputs += 1;
        end

        #100 $finish;
    end

endmodule
