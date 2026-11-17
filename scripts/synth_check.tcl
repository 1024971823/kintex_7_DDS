# Out-of-context Vivado 2024.2 synthesis & timing check for awg_dds_top
set proj_dir [file normalize [file dirname [info script]]/..]
set out_dir  "$proj_dir/prj/xilinx/synth_check"
file mkdir $out_dir

create_project -in_memory -part xc7k325tffg900-2

read_verilog [list \
    "$proj_dir/user/src/dds_sin_qtr_rom.v" \
    "$proj_dir/user/src/dds_sin_lut.v" \
    "$proj_dir/user/src/dds_mod_nco.v" \
    "$proj_dir/user/src/awg_wave_ram.v" \
    "$proj_dir/user/src/dds_channel.v" \
    "$proj_dir/user/src/awg_stream_fifo.v" \
    "$proj_dir/user/src/awg_dds_axi_lite.v" \
    "$proj_dir/user/src/awg_dds_top.v" \
]

synth_design -top awg_dds_top -part xc7k325tffg900-2 -mode out_of_context

# Constrain main clock to 200 MHz (5.0 ns) matching board clk_wiz_0/clk_200M
create_clock -period 5.000 -name clk [get_ports clk]

report_utilization -file "$out_dir/utilization_synth.rpt"
report_timing_summary -delay_type max -max_paths 5 -file "$out_dir/timing_synth.rpt"

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
puts "=== SYNTH CHECK COMPLETE: WNS = $wns ns (target 200 MHz) ==="
