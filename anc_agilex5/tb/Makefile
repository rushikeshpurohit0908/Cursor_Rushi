# Simulation makefile (Icarus Verilog or Verilator)
IVERILOG ?= iverilog
VVP      ?= vvp
RTL      := ../rtl
INC      := -I$(RTL)

.PHONY: all fxlms i2s i2c clean

all: fxlms i2s

fxlms:
	$(IVERILOG) $(INC) -o sim_fxlms \
		$(RTL)/secondary_path_fir.v $(RTL)/fxlms_engine.v tb_fxlms_engine.v
	$(VVP) sim_fxlms

i2s:
	$(IVERILOG) $(INC) -o sim_i2s \
		$(RTL)/i2s_rx.v $(RTL)/i2s_tx.v tb_i2s_loopback.v
	$(VVP) sim_i2s

i2c:
	$(IVERILOG) $(INC) -o sim_i2c \
		$(RTL)/i2c_master.v $(RTL)/codec_init.v tb_i2c_codec.v
	$(VVP) sim_i2c

clean:
	rm -f sim_fxlms sim_i2s sim_i2c *.vcd
