# -----------------------------------------------------------------------------
# LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
#
# ltpi.sdc - example SDC timing constraints.
# Adjust REF_CLK's period to match your board's actual reference oscillator.
# -----------------------------------------------------------------------------

create_clock -name REF_CLK -period 20.000 [get_ports REF_CLK]  ;# 50 MHz

derive_pll_clocks -create_base_clocks
derive_clock_uncertainty

# GPIO inputs are re-synchronized inside ltpi_top.sv with a 2-flop
# synchronizer; treat them as asynchronous to the link clock domain.
set_false_path -from [get_ports {GPIO_LL_IN[*] GPIO_NL_IN[*]}] -to [get_registers *]

# Reset is asynchronous by design (cv_pll/ltpi_phy_cyclonev/ltpi_top all use
# asynchronous resets); the PLL lock detector re-synchronizes it internally.
set_false_path -from [get_ports RESET_N]
