### COMMON ###

# Directories
SRC_DIR  = rtl
SIM_DIR  = sim
TB_DIR   = tb
IMPL_DIR = impl

# Top module name
TOP_MOD = top

# Physical constraints file
PCF_FILE  = pcf/io.pcf

# Source files
SRCS = $(wildcard $(SRC_DIR)/*.v)


### SIMULATION ###


# Top TB

TB_MOD = top_tb
TB_FILE = $(TB_DIR)/$(TB_MOD).v
ICARUS_BIN    = $(TB_MOD).vvp

$(SIM_DIR)/$(ICARUS_BIN): $(TB_FILE) $(SRCS)
	@echo "Compiling with iverilog"
	iverilog -g2012 -o $@ $(TB_FILE) $(SRCS)

sim_icarus: $(SIM_DIR)/$(ICARUS_BIN)
	(cd $(SIM_DIR) && vvp $(ICARUS_BIN))

sim_verilator: $(VERILATOR_DIR)/$(VERILATOR_BIN)
	(cd $(VERILATOR_DIR) && ./$(VERILATOR_BIN))


# Generate flash contents for tests
$(TB_DIR)/flash_contents.hex:
	python $(TB_DIR)/generate_flash_contents.py


# Flash model TB

SPI_FLASH_MODEL_TB_SRCS = $(TB_DIR)/spi_flash_model_tb.v $(TB_DIR)/spi_flash_model.v

$(SIM_DIR)/spi_flash_model_tb.vvp: $(SPI_FLASH_MODEL_TB_SRCS) $(TB_DIR)/flash_contents.hex
	iverilog -g2012 -o $@ $(SPI_FLASH_MODEL_TB_SRCS)

test_spi_flash_model: $(SIM_DIR)/spi_flash_model_tb.vvp
	(cd $(TB_DIR) && vvp ../$<)


# Flash loader TB

FLASH_LOADER_TB_SRCS = $(TB_DIR)/flash_loader_tb.v $(TB_DIR)/spi_flash_model.v $(SRCS)

$(SIM_DIR)/flash_loader_tb.vvp: $(FLASH_LOADER_TB_SRCS) $(TB_DIR)/flash_contents.hex
	iverilog -g2012 -o $@ $(FLASH_LOADER_TB_SRCS)

test_flash_loader: $(SIM_DIR)/flash_loader_tb.vvp
	(cd $(TB_DIR) && vvp ../$<)


# Top TB

# Program used for the top testbench
$(TB_DIR)/top_tb_prog.hex: $(TB_DIR)/top_tb_prog.s
	./.venv/bin/python tools/assembler.py -o $@ $^

assemble_top_tb: $(TB_DIR)/top_tb_prog.hex

TOP_TB_SRCS = $(TB_DIR)/top_tb.v $(TB_DIR)/spi_flash_model.v $(SRCS)

$(SIM_DIR)/top_tb.vvp: $(TOP_TB_SRCS) $(TB_DIR)/top_tb_prog.hex
	iverilog -g2012 -o $@ $(TOP_TB_SRCS)

test_top: $(SIM_DIR)/top_tb.vvp
	(cd $(TB_DIR) && vvp ../$<)


# Top TB with bidir port

# Program used for the top with bidir port testbench
$(TB_DIR)/bidir_tb_prog.hex: $(TB_DIR)/bidir_tb_prog.s
	python tools/assembler.py -o $@ $^

assemble_bidir_tb: $(TB_DIR)/bidir_tb_prog.hex

BIDIR_TB_SRCS = $(TB_DIR)/bidir_tb.v $(TB_DIR)/spi_flash_model.v $(SRCS)

$(SIM_DIR)/bidir_tb.vvp: $(BIDIR_TB_SRCS) $(TB_DIR)/bidir_tb_prog.hex
	iverilog -g2012 -o $@ $(BIDIR_TB_SRCS)

test_bidir: $(SIM_DIR)/bidir_tb.vvp
	(cd $(TB_DIR) && vvp ../$<)


### IMPLEMENTATION ###

# Synthesis
SYN_TGT = $(IMPL_DIR)/$(TOP_MOD).json

$(SYN_TGT): $(SRCS)
	yosys -p "synth_ice40 -top top -json $@" $^

synth: $(SYN_TGT)

# Place-and-route 
PNR_TGT = $(IMPL_DIR)/$(TOP_MOD).asc

$(PNR_TGT): $(SYN_TGT) $(PCF_FILE)
	nextpnr-ice40 --up5k --package sg48 --json $(SYN_TGT) --pcf $(PCF_FILE) --asc $@ --report $(IMPL_DIR)/timing.json

pnr: $(PNR_TGT)


# Bitstream
BIT_TGT = $(IMPL_DIR)/$(TOP_MOD).bin

$(BIT_TGT): $(PNR_TGT)
	icepack $(PNR_TGT) $@

bitstream: $(BIT_TGT)


# Programming the FPGA
prog_cram: $(BIT_TGT)
	iceprog -S $<

prog_flash: $(BIT_TGT)
	iceprog $<


### FLASH SOFTWARE PROGRAMMING ###

flash_top_tb: assemble_top_tb
	python tools/flasher.py --port COM3 --baud 115200 tb/top_tb_prog.hex

flash_bidir_tb: assemble_bidir_tb
	python tools/flasher.py --port COM3 --baud 115200 tb/bidir_tb_prog.hex

# Phony rules
.PHONY: sim_icarus sim_verilator synth pnr bitstream prog_cram prog_flash sim_clean impl_clean clean
