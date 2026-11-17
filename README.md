# Kintex-7 (XC7K325T-2FFG900) 4 通道高精度 DDS / 任意波形发生器 (AWG)

针对 Memblaze Kintex-7 (`xc7k325tffg900-2`) 板卡设计的 **4 通道 16-bit 高精度 DDS + 任意波形发生器 (AWG)** RTL 工程，包含完整 AXI4-Lite 控制、片上 BRAM 任意波表、DDR3/XDMA 深存储 AXI-Stream 流式播放通道、Vivado XSIM 仿真与频谱 SFDR 验证脚本。

---

## 1. 核心特性

- **4 个独立同步通道（16-bit 有符号输出，支持切换偏置二进制 Offset Binary 对接外部 DAC）**
- **48-bit 频率控制字 (FTW) 与 48-bit 相位偏置 (POFF)**
  - 在 200 MHz 采样时钟下，频率分辨率为 $200\times 10^6 / 2^{48} \approx 0.71\,\mu\text{Hz}$
  - 支持软件与外部硬件触发的 **多通道相干相位同步 (`phase_sync`)**
- **高无杂散动态范围 (SFDR) 正弦合成**
  - 1/4 周期 2048 点（偶/奇双 Bank BRAM）+ 11-bit 线性插值，4 周期固定流水线延迟
  - XSIM 实测 4096 点 Blackman-Harris 加窗 FFT：**SFDR = 101.80 dBc**
- **6 种波形模式 (`wave_mode`)**：
  - `0`: 高精度正弦波 (Sine)
  - `1`: 可调占空比方波 / PWM (`duty_cycle`)
  - `2`: 三角波 (Triangle)
  - `3`: 锯齿波 (Sawtooth)
  - `4`: **AWG 任意波形表**（每通道 4096 × 16-bit 偶/奇双 Bank BRAM，支持相位累加插值回放与直接逐点步进回放两种模式）
  - `5`: PRBS32 伪随机白噪声
- **内置线性扫频 (Chirp) 与模拟/数字调制**：
  - 线性扫频：支持锯齿扫频与三角往返扫频，可配步进、上下限与驻留周期
  - **AM / FM / PM 调制**：支持内置 32-bit 调制 NCO 或相邻通道交叉调制（Ch0↔Ch1，Ch2↔Ch3）
  - 可编程增益（Q1.15）与有符号直流偏置（带饱和防溢出限幅）
- **高速流式与回采接口**：
  - `S_AXIS_AWG` (64-bit)：内置 512×64-bit 同步 FIFO，直接对接 DDR3/XDMA H2C 做超深任意波形回放
  - `M_AXIS_CAP` (64-bit)：可配置帧长 `TLAST` 输出 `{ch3, ch2, ch1, ch0}`，用于 XDMA C2H 上位机回采或 ILA 观测

---

## 2. Digital IDE 标准目录结构

```text
kintex_7_DDS/
├── .vscode/
│   ├── property.json          # Digital IDE v0.5.0 工程配置 (xilinx / xc7k325tffg900-2)
│   ├── settings.json          # 工作区 Vivado 包装路径、SV2017、LSP 与仿真目录配置
│   └── tasks.json             # Ctrl+Shift+B 一键运行 XSIM + FFT 验证并生成 VCD
├── user/
│   ├── src/                   # RTL 设计源码
│   │   ├── dds_sin_qtr_rom.v  # 1/4 周期偶/奇双 Bank 正弦 ROM（脚本生成）
│   │   ├── dds_sin_lut.v      # 4 级流水线线性插值正弦查找表
│   │   ├── dds_mod_nco.v      # 轻量级 32-bit 内置调制 NCO（0 BRAM）
│   │   ├── awg_wave_ram.v     # 4096×16 双 Bank AWG 波形 BRAM（单周期双样本写）
│   │   ├── dds_channel.v      # 单通道 DDS + Chirp + AM/FM/PM + AWG + 增益/偏置
│   │   ├── awg_stream_fifo.v  # 512×64-bit AXI4-Stream 深波表流式 FIFO
│   │   ├── awg_dds_axi_lite.v # AXI4-Lite 从机寄存器与 BRAM 写入控制器
│   │   └── awg_dds_top.v      # 顶层模块（兼容 Vivado IP Integrator）
│   ├── sim/                   # 仿真 Testbench
│   │   └── tb_awg_dds_top.sv  # 全功能自检 Testbench（输出 VCD + CSV）
│   ├── data/                  # 约束与板级参考文件
│   │   ├── memblaze_k7_base.xdc   # 板卡基础时钟、LED、复位、SPIx4 约束
│   │   └── memblaze_j1_j4_ref.xdc # J1 / J4 接插件用户 IO 参考引脚（含电平警告）
│   ├── ip/                    # Vivado IP 核目录（预留）
│   └── bd/                    # Block Design 源码目录（预留）
├── prj/xilinx/                # Vivado 工程生成与综合产物目录
├── simulation/                # XSIM 仿真工作目录与 awg_dds_wave.vcd 波形文件
├── scripts/
│   ├── gen_sin_lut.py         # 生成 user/src/dds_sin_qtr_rom.v
│   ├── verify_sim_fft.py      # 读取仿真 CSV 计算 FFT SFDR 并验证 AWG 包络
│   ├── run_xsim.sh            # Vivado XSIM 一键编译、仿真、生成 VCD 与频谱验证
│   ├── synth_check.tcl        # Vivado 综合与 200 MHz 时序检查脚本
│   └── integrate_xdma.tcl     # 自动接入 PCIE_XDMA Block Design 的 Tcl 脚本
└── README.md
```

---

## 3. 寄存器与地址空间映射（64 KB，`0x0000`–`0xFFFF`）

### 全局寄存器 (`0x0000`–`0x0010`)

| 偏移地址 | 名称 | 属性 | 说明 |
|---|---|---|---|
| `0x0000` | `VERSION` | RO | `0x4444_5301` (`"DDS\x01"`) |
| `0x0004` | `GLOBAL_CTRL` | RW | `[0]` global_enable；`[1]` soft_phase_sync（自清零脉冲）；`[2]` stream_ddr_awg_en；`[3]` cap_axis_en；`[7:4]` ch_enable_mask；`[8]` dac_offset_bin（1=偏置二进制）；`[9]` clr_fifo_underflow |
| `0x0008` | `GLOBAL_STATUS` | RO | `[3:0]` ch_valid；`[4]` fifo_underflow；`[15:6]` fifo_fill_level；`[31:16]` heartbeat |
| `0x000C` | `SAMPLE_RATE` | RW | 软件参考采样率（默认 `200_000_000`） |
| `0x0010` | `CAP_PKT_LEN` | RW | `M_AXIS_CAP` 的 `TLAST` 周期减 1（默认 `1023`） |

### 单通道寄存器（`base = 0x0100 * (ch + 1)`，`ch = 0..3`）

| 偏移 (`+base`) | 名称 | 说明 |
|---|---|---|
| `+0x00` | `CH_CTRL` | `[2:0]` wave_mode；`[4:3]` mod_mode (0无/1AM/2FM/3PM)；`[5]` mod_src_sel (0内置/1交叉通道)；`[6]` awg_interp_en；`[7]` awg_step_mode；`[8]` sweep_en；`[9]` sweep_mode (0锯齿/1三角)；`[10]` ch_rst |
| `+0x04` / `+0x08` | `FTW_LO` / `FTW_HI` | 48-bit 频率控制字 |
| `+0x0C` / `+0x10` | `POFF_LO` / `POFF_HI` | 48-bit 相位偏置 |
| `+0x14` | `GAIN_OFFSET` | `[15:0]` gain (Q1.15，默认 `0x8000`=1.0x)；`[31:16]` dc_offset (signed 16-bit) |
| `+0x18` | `DUTY_CYCLE` | `[15:0]` 方波占空比（`0x8000`=50%） |
| `+0x1C` | `MOD_FTW` | 内置 32-bit 调制 NCO 频率控制字 |
| `+0x20` | `MOD_DEPTH_FM` | `[15:0]` am_depth；`[31:16]` fm_dev |
| `+0x24` | `MOD_PM_DEV` | `[15:0]` pm_dev（`0xFFFF` 对应 ±180°） |
| `+0x28`–`+0x40` | `SWEEP_*` | Chirp 扫频步进、上下限与驻留周期 (`STEP_LO/HI`, `MIN_LO/HI`, `MAX_LO/HI`, `DWELL`) |
| `+0x44` / `+0x48` | `AWG_STEP_CFG` / `DWELL` | 直接步进 AWG 末索引 `[11:0]` 与驻留周期 |

### AWG 波形 BRAM 窗口 (`0x8000`–`0xFFFF`)

每个 32-bit 写入字包含 2 个 16-bit 样本（`[15:0]` 为偶样本，`[31:16]` 为奇样本）：
- Ch0: `0x8000`–`0x9FFF`（4096 样本）
- Ch1: `0xA000`–`0xBFFF`（4096 样本）
- Ch2: `0xC000`–`0xDFFF`（4096 样本）
- Ch3: `0xE000`–`0xFFFF`（4096 样本）

---

## 4. 在 Digital IDE 中开发、仿真与板级整合

1. **用 VS Code 打开工程并验证环境**：
   - 执行 `code /home/Srakoul/Downloads/kintex_7_DDS` 打开工作区。
   - 左侧栏打开 **Digital IDE** 视图即可查看 `user/src`（`awg_dds_top`）与 `user/sim`（`tb_awg_dds_top`）模块树；也可按 `Ctrl+Shift+P` 运行 `Digital-IDE: Validate Toolchains`。
2. **运行 Vivado XSIM 仿真、FFT SFDR 验证与查看波形**：
   - 在 VS Code 中按 `Ctrl+Shift+B`（或在终端执行 `bash scripts/run_xsim.sh`）。
   - 仿真通过后，直接在 VS Code 中点击打开 `simulation/awg_dds_wave.vcd`（Digital IDE 内置波形查看器），可将 `dac_ch0_data`–`dac_ch3_data` 设为 **Signed / Analog** 模式直观查看正弦、Chirp 扫频、AM/FM/PM 与高斯脉冲 AWG 波形。
3. **整合到 Memblaze `PCIE_XDMA` 工程（推荐先复制一份原工程）**：
   ```bash
   vivado -mode batch -source scripts/integrate_xdma.tcl -tclargs /path/to/DIY_MEMBLAZE_PCIE_learn_ALINX.xpr
   ```
   > **提示**：执行综合/实现前，请确认本机 Vivado 2024.2 已安装 Kintex-7 (`xc7k325tffg900-2`) 器件支持库；如需通过 `J1`/`J4` 连接外部高速 DAC，请务必对照 [memblaze_j1_j4_ref.xdc](file:///home/Srakoul/Downloads/kintex_7_DDS/user/data/memblaze_j1_j4_ref.xdc) 在 Vivado Package Pins 视图确认所选引脚的 Bank `VCCO` 电压。
