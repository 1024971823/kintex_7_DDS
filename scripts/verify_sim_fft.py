#!/usr/bin/env python3
"""Analyze XSIM simulation CSV outputs: compute windowed FFT SFDR and verify AWG output."""

import cmath
import csv
import math
import sys
from pathlib import Path

FS_HZ = 200_000_000.0


def fft_radix2(x):
    n = len(x)
    if n <= 1:
        return x
    even = fft_radix2(x[0::2])
    odd = fft_radix2(x[1::2])
    t = [cmath.exp(-2j * math.pi * k / n) * odd[k] for k in range(n // 2)]
    return [even[k] + t[k] for k in range(n // 2)] + [even[k] - t[k] for k in range(n // 2)]


def blackman_harris_window(n):
    a0, a1, a2, a3 = 0.35875, 0.48829, 0.14128, 0.01168
    return [
        a0
        - a1 * math.cos(2.0 * math.pi * i / (n - 1))
        + a2 * math.cos(4.0 * math.pi * i / (n - 1))
        - a3 * math.cos(6.0 * math.pi * i / (n - 1))
        for i in range(n)
    ]


def analyze_sine_csv(csv_path: Path) -> bool:
    ch0, ch1, ch2, ch3 = [], [], [], []
    with csv_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ch0.append(int(row["ch0"]))
            ch1.append(int(row["ch1"]))
            ch2.append(int(row["ch2"]))
            ch3.append(int(row["ch3"]))

    n = len(ch0)
    win = blackman_harris_window(n)
    x_win = [complex(ch0[i] * win[i], 0.0) for i in range(n)]
    spec = fft_radix2(x_win)
    mags = [abs(spec[k]) for k in range(n // 2)]

    # Exclude DC (bins 0..4) and mainlobe (+/- 5 bins around peak)
    fund_bin = max(range(5, len(mags)), key=lambda k: mags[k])
    fund_freq_mhz = (fund_bin * FS_HZ / n) / 1e6
    fund_mag = mags[fund_bin]

    spur_bins = [
        mags[k]
        for k in range(5, len(mags))
        if abs(k - fund_bin) > 5
    ]
    max_spur = max(spur_bins) if spur_bins else 1e-12
    sfdr_dbc = 20.0 * math.log10(fund_mag / max(max_spur, 1e-12))

    # Check peak amplitude across channels
    peak0 = max(abs(v) for v in ch0)
    peak1 = max(abs(v) for v in ch1)

    print(f"[FFT] N={n}, Ch0 peak={peak0}, Ch1 peak={peak1}")
    print(f"[FFT] Fundamental bin={fund_bin} (~{fund_freq_mhz:.3f} MHz, target 7.123 MHz)")
    print(f"[FFT] Measured SFDR (Blackman-Harris window) = {sfdr_dbc:.2f} dBc")

    ok = (sfdr_dbc >= 90.0) and (abs(fund_freq_mhz - 7.123456) < 0.06) and (peak0 >= 32700)
    if not ok:
        print("FAIL: Sine SFDR or frequency/amplitude check failed!", file=sys.stderr)
    return ok


def analyze_awg_csv(csv_path: Path) -> bool:
    vals = []
    with csv_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            vals.append(int(row["awg_interp"]))

    peak = max(abs(v) for v in vals)
    edge_amp = max(abs(vals[10]), abs(vals[790]))
    print(f"[AWG] Samples={len(vals)}, center peak={peak}, edge amp={edge_amp}")
    # Gaussian pulse should peak near 30000 in the center and decay near edges
    ok = (peak > 28000) and (edge_amp < 1500)
    if not ok:
        print("FAIL: AWG Gaussian envelope check failed!", file=sys.stderr)
    return ok


if __name__ == "__main__":
    sim_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    ok_sine = analyze_sine_csv(sim_dir / "sim_sine_ch0.csv")
    ok_awg = analyze_awg_csv(sim_dir / "sim_awg_ch0.csv")
    if ok_sine and ok_awg:
        print("=== PYTHON SPECTRAL & AWG VERIFICATION PASSED ===")
        sys.exit(0)
    sys.exit(1)
