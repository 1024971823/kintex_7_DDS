# ==============================================================================
# Memblaze Kintex-7 (XC7K325T-2FFG900) Base Board Constraints
# Verified against board reference project io.xdc & MEMBLAZE扩展引脚定义.xls
# ==============================================================================

# 50 MHz Single-Ended System Clock (1.8V Bank)
set_property PACKAGE_PIN D27 [get_ports clk_in1_50M]
set_property IOSTANDARD LVCMOS18 [get_ports clk_in1_50M]
create_clock -period 20.000 -name clk_50m [get_ports clk_in1_50M]

# Active-Low Reset (PCIe PERST#)
set_property PACKAGE_PIN V22 [get_ports sys_rst_n_0]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n_0]
set_property PULLUP true [get_ports sys_rst_n_0]

# Status LEDs (3.3V Bank)
set_property PACKAGE_PIN R24 [get_ports {status_led[0]}]
set_property PACKAGE_PIN T21 [get_ports {status_led[1]}]
set_property PACKAGE_PIN T20 [get_ports {status_led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_led[*]}]

# PCIe 100 MHz Differential Reference Clock & GTX x8 Lanes (for XDMA integration)
# set_property PACKAGE_PIN U8 [get_ports {CLK_IN_D_0_clk_p[0]}]
# set_property PACKAGE_PIN L4 [get_ports {pcie_mgt_0_txp[0]}]
# set_property PACKAGE_PIN M2 [get_ports {pcie_mgt_0_txp[1]}]
# set_property PACKAGE_PIN N4 [get_ports {pcie_mgt_0_txp[2]}]
# set_property PACKAGE_PIN P2 [get_ports {pcie_mgt_0_txp[3]}]
# set_property PACKAGE_PIN T2 [get_ports {pcie_mgt_0_txp[4]}]
# set_property PACKAGE_PIN U4 [get_ports {pcie_mgt_0_txp[5]}]
# set_property PACKAGE_PIN V2 [get_ports {pcie_mgt_0_txp[6]}]
# set_property PACKAGE_PIN Y2 [get_ports {pcie_mgt_0_txp[7]}]

# SPI Flash Configuration (MT25QL256 SPIx4)
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
