# AI-ANC FPGA simulation and vector generation

IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3

RTL_DIR  := rtl
TB_DIR   := tb
BUILD    := build

RTL_SRCS := \
	$(RTL_DIR)/anc_pkg.v \
	$(RTL_DIR)/anc_math.v \
	$(RTL_DIR)/nlms_filter.v \
	$(RTL_DIR)/feature_extractor.v \
	$(RTL_DIR)/ai_mu_selector.v \
	$(RTL_DIR)/anc_top.v

.PHONY: all vectors quantize train-fpga sim cosim clean

all: train-fpga vectors quantize

train-fpga:
	$(PYTHON) scripts/train_fpga_mlp.py

vectors:
	$(PYTHON) scripts/fpga_model.py

quantize:
	$(PYTHON) scripts/quantize_weights.py

cosim:
	$(PYTHON) -c "from pathlib import Path; import sys; sys.path.insert(0,'scripts'); from fpga_model import FixedPointANC; from fpga_params import *; print('Fixed-point model OK')"

sim: vectors quantize
	@mkdir -p $(BUILD)
	$(IVERILOG) -g2005-sv -o $(BUILD)/anc_tb.vvp $(RTL_SRCS) $(TB_DIR)/anc_tb.v
	cd $(RTL_DIR) && $(VVP) ../$(BUILD)/anc_tb.vvp

clean:
	rm -rf $(BUILD)
