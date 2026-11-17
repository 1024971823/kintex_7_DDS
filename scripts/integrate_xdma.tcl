# ==============================================================================
# Vivado 2024.2 Integration Script:
#   Adds the 4-ch DDS/AWG RTL modules into the Memblaze PCIE_XDMA project
#   and instantiates awg_dds_top into the PCIE_XDMA Block Design.
#
# Usage (example):
#   1. Copy the seller's xdma_ddr project to a working folder first!
#   2. vivado -mode batch -source scripts/integrate_xdma.tcl -tclargs /path/to/DIY_MEMBLAZE_PCIE_learn_ALINX.xpr
# ==============================================================================

if {$argc < 1} {
    puts "ERROR: Please pass path to DIY_MEMBLAZE_PCIE_learn_ALINX.xpr"
    exit 1
}

set xpr_path [file normalize [lindex $argv 0]]
set dds_dir  [file normalize [file dirname [info script]]/..]

open_project $xpr_path

add_files -norecurse [list \
    "$dds_dir/user/src/dds_sin_qtr_rom.v" \
    "$dds_dir/user/src/dds_sin_lut.v" \
    "$dds_dir/user/src/dds_mod_nco.v" \
    "$dds_dir/user/src/awg_wave_ram.v" \
    "$dds_dir/user/src/dds_channel.v" \
    "$dds_dir/user/src/awg_stream_fifo.v" \
    "$dds_dir/user/src/awg_dds_axi_lite.v" \
    "$dds_dir/user/src/awg_dds_top.v" \
]
update_compile_order -fileset sources_1

open_bd_design [get_files PCIE_XDMA.bd]

# Add awg_dds_top as RTL module reference in Block Design
if {[llength [get_bd_cells -quiet awg_dds_top_0]] == 0} {
    create_bd_cell -type module -reference awg_dds_top awg_dds_top_0
}

# Connect 200 MHz clock & reset from clk_wiz_0 / rst_mig_7series_0_200M
connect_bd_net [get_bd_pins clk_wiz_0/clk_200M] [get_bd_pins awg_dds_top_0/clk]
connect_bd_net [get_bd_pins rst_mig_7series_0_200M/peripheral_aresetn] [get_bd_pins awg_dds_top_0/rst_n]

# Make DAC ports external so you can map them to J1/J4 pins when ready
foreach p {dac_valid dac_ch0_data dac_ch1_data dac_ch2_data dac_ch3_data ext_sync_trig} {
    if {[llength [get_bd_ports -quiet $p]] == 0} {
        make_bd_pins_external [get_bd_pins awg_dds_top_0/$p]
    }
}

# Connect AXI-Lite slave to xdma_0/M_AXI_LITE via AXI Interconnect / Connection Automation
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master {/xdma_0/axi_aclk (250 MHz)} \
    Clk_slave {/clk_wiz_0/clk_200M (200 MHz)} \
    Clk_xbar {/xdma_0/axi_aclk (250 MHz)} \
    Master {/xdma_0/M_AXI_LITE} \
    Slave {/awg_dds_top_0/S_AXIL} \
    ddr_seg {Auto} \
    intc_ip {Auto} \
    master_apm {0} \
} [get_bd_intf_pins awg_dds_top_0/S_AXIL]

assign_bd_address
validate_bd_design
save_bd_design

puts "=== Integrated awg_dds_top_0 into PCIE_XDMA.bd successfully ==="
