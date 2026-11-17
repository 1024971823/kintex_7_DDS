#!/usr/bin/env bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_DIR="$PROJ_DIR/simulation"
VIVADO_BIN_DIR="${VIVADO_ROOT:-$HOME/Xilinx/Vivado/2024.2}/bin"

if [[ ! -e /usr/lib/libtinfo.so.5 && -e "$HOME/.local/lib/libtinfo.so.5" ]]; then
    export LD_LIBRARY_PATH="$HOME/.local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

mkdir -p "$SIM_DIR"
cd "$SIM_DIR"

echo "[1/5] Compiling Verilog RTL (user/src) with xvlog..."
"$VIVADO_BIN_DIR/xvlog" \
    "$PROJ_DIR/user/src/dds_sin_qtr_rom.v" \
    "$PROJ_DIR/user/src/dds_sin_lut.v" \
    "$PROJ_DIR/user/src/dds_mod_nco.v" \
    "$PROJ_DIR/user/src/awg_wave_ram.v" \
    "$PROJ_DIR/user/src/dds_channel.v" \
    "$PROJ_DIR/user/src/awg_stream_fifo.v" \
    "$PROJ_DIR/user/src/awg_dds_axi_lite.v" \
    "$PROJ_DIR/user/src/awg_dds_top.v"

echo "[2/5] Compiling SystemVerilog testbench (user/sim) with xvlog -sv..."
"$VIVADO_BIN_DIR/xvlog" -sv "$PROJ_DIR/user/sim/tb_awg_dds_top.sv"

echo "[3/5] Elaborating with xelab..."
"$VIVADO_BIN_DIR/xelab" -debug typical tb_awg_dds_top -s sim_awg_dds

echo "[4/5] Running XSIM simulation (outputs simulation/awg_dds_wave.vcd)..."
"$VIVADO_BIN_DIR/xsim" sim_awg_dds -runall

echo "[5/5] Verifying spectral SFDR and AWG waveform via Python..."
python3 "$PROJ_DIR/scripts/verify_sim_fft.py" "$SIM_DIR"
