module flash_loader_tb;

    localparam PAGE_SIZE = 128;
    localparam HEX_FILE = "flash_contents.hex";
    localparam HEX_FILE_SIZE = 65536;

    localparam START_PAGE = 396;
    localparam END_PAGE = 404;

    reg clk = 0;
    reg nrst = 1;

    wire MISO, MOSI_w, SCK_w, NSS_w;

    reg [16:0] page = 1;

    wire [6:0] data_addr;
    wire [7:0] data;
    wire write_en;

    reg start = 0;

    wire done;

    flash_loader flash_loader (
        .clk_i      (clk),
        .nrst_i     (nrst),
        .MISO_i     (MISO),
        .MOSI_o     (MOSI_w),
        .SCK_o      (SCK_w),
        .NSS_o      (NSS_w),
        .page_i     (page),
        .data_addr_o(data_addr),
        .data_o     (data),
        .write_en_o (write_en),
        .start_i    (start),
        .done_o     (done)
    );

    reg MOSI, SCK, NSS;

    always @(posedge clk) begin
        {MOSI, SCK, NSS} <= {MOSI_w, SCK_w, NSS_w};
    end

    spi_flash_model #(
        .HEX_FILE  ("flash_contents.hex"),
        .FLASH_SIZE(65536)
    ) spi_flash_model (
        .MISO_o(MISO),
        .MOSI_i(MOSI),
        .SCK_i (SCK),
        .NSS_i (NSS)
    );

    always #1 clk = ~clk;

    integer loaded_byte_idx = 0;

    integer i = 0, j = 0;

    reg [7:0] loaded_memory [0:PAGE_SIZE-1];
    reg [7:0] expected_memory [0:HEX_FILE_SIZE-1];

    reg failed = 0;

    initial begin
        $display("\n==== FLASH LOADER TB ====");

        $dumpfile("../vcd/flash_loader_tb.vcd");
        $dumpvars(0);

        $readmemh(HEX_FILE, expected_memory);

        for (j = START_PAGE; j < END_PAGE; j = j + 1) begin
            page = j[16:0];
            $display("Testing page %d", page);

            loaded_byte_idx = 0;

            #2 nrst = 0;
            #2 nrst = 1;

            #10 wait(clk == 0);
            
            start = 1;
            #2 start = 0;
            
            while (!done) begin
                @(posedge clk);
                if (write_en) begin
                    loaded_memory[data_addr] = data;
                    loaded_byte_idx += 1;
                end
            end
            if (loaded_byte_idx != PAGE_SIZE) begin
                $display("Expected to load %d bytes, loaded %d", PAGE_SIZE, loaded_byte_idx);
                failed = 1;
            end

            for (i = 0; i < PAGE_SIZE; i = i + 1) begin
                if (expected_memory[{page, 7'd0} + i[23:0]] != loaded_memory[i[6:0]]) begin
                    $display("Expected to read %02X, received %02X", expected_memory[{page, 7'd0} + i[23:0]], loaded_memory[i[6:0]]);
                    failed = 1;
                end
            end
            #10;
        end

        if (failed) begin
            $display("==== Test failed ====\n");
        end else begin
            $display("==== Test succesful ====\n");
        end

        #10 $finish();
    end

endmodule
