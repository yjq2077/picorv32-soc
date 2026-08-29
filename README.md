# PicoRV32 SoC

基于 [PicoRV32](https://github.com/YosysHQ/picorv32)（AXI4-Lite 版本）和 [Alex Forencich](https://github.com/alexforencich) 的 AXI-Lite 基础设施搭建的轻量 RISC-V SoC。包含双主 AXI4-Lite 互联、64KB 程序 RAM、UART / I2C / GPIO / Timer 外设和中断控制器，可在 Verilator 下完整仿真验证。

## 特性

- **PicoRV32 AXI4-Lite**：`picorv32_axi` 作为 CPU 主口（RV32IM，兼容 CoreMark）。
- **双主 AXI-Lite 互联**：`axil_interconnect`（Alex Forencich）两个主口 ——
  - 主口 0：PicoRV32 CPU；
  - 主口 1：外部主机口，可用于固件下载、内核复位控制，以及直接访问全部外设（调试）。
- **64KB 程序 RAM**：AXI-Lite 接口，`axil_ram`，字节写使能支持。
- **复位控制**：`boot_ctrl` 寄存器模块，外部主机可拉低/释放 CPU 复位以便下载固件。
- **外设**：4× I2C、2× UART、2× AXI-Lite→APB 桥（挂 GPIO、Timer、CTRL 寄存器）、1× 中断控制器（irq_ctrl）。
- **固件结构**：外设函数库（`fw/lib`，可独立发布）+ 应用（`fw/app`），全部外设读写自检。
- **仿真**：Verilator 5.x 仿真环境，外部主机口完成 RAM 下载并释放复位，全部外设测试通过、无 CPU trap。

## 系统框图

```
                    +--------------------------------------------------+
                    |                    soc_top                       |
                    |                                                  |
 External host      |   +------------------+                           |
 AXI4-Lite master   |   |  picorv32_axi    |                           |
 (fw download /     |   |  (CPU master)    |                           |
  reset ctrl /      |   +--------+---------+                           |
  peripheral debug) |            | CPU AXI4-Lite                       |
        |           |   +--------v---------------------------------+   |
        |           |   |         axil_interconnect                |   |
        +-----------+-->|  (2 masters / 11 slaves, axil_inter-     |   |
                    |   |   connect from verilog-axi)              |   |
                    |   +--+--+--+--+--+--+--+--+--+---------------+   |
                    |      |  |  |  |  |  |  |  |  |                   |
                    |   +--+  |  |  |  |  |  |  |  +--------+          |
                    |   |     |  |  |  |  |  |  +--+        |          |
                    |   |  +--+  |  |  |  +--+  |           |          |
                    |   |  |     |  |  |     |  |           |          |
                    |  RAM BOOT IRQ I2C UART  APB0       APB1          |
                    |  64K  ctrl ctl 0-3  0-1  GPIO      CTRL         |
                    |                        +TIMER0    +TIMER1        |
                    +--------------------------------------------------+
```

## 目录结构

```
picorv32-soc/
├── LICENSE.md              # 项目许可证（第三方组件保留各自许可证）
├── README.md
├── docs/
│   └── soc_test_report.md  # 外设读写验证与时序分析测试报告
├── rtl/                    # 全部 RTL（相对路径，整目录可整体搬移）
│   ├── pico32/             # PicoRV32 官方核（picorv32.v, ISC）
│   ├── third_party/        # Alex Forencich 基础设施（MIT）
│   │   ├── verilog-axi/    #   axil_interconnect / arbiter / priority_encoder
│   │   ├── verilog-uart/   #   uart / uart_rx / uart_tx
│   │   └── verilog-i2c/    #   i2c_master_axil / i2c_master / i2c_init / axis_fifo
│   └── soc/                # 本 SoC 专用 RTL
│       ├── soc_top.v       # 顶层：互联实例化、地址译码
│       ├── axil_ram.v      # 64KB AXI4-Lite RAM（字节写）
│       ├── boot_ctrl.v     # CPU 复位控制寄存器
│       ├── irq_ctrl.v      # 中断控制器（16 源，使能/挂起/主使能）
│       ├── uart_axil.v     # UART AXI4-Lite 封装
│       ├── axil2apb.v      # AXI4-Lite → APB 桥
│       ├── apb_interconnect.v
│       ├── apb_gpio.v      # GPIO（含中断）
│       ├── apb_timer.v     # 定时器（含中断）
│       └── apb_ctrl.v      # 控制/状态寄存器
├── sim/                    # Verilator 仿真
│   ├── soc_tb.v            # 顶层测试台（主机下载口 + 外设行为模型）
│   ├── files_rtl.f         # RTL 源清单（相对路径）
│   ├── build_sim.sh        # 编译
│   ├── run_sim.sh          # 运行（自动取 fw/fw.hex 下载）
│   └── analyze_log.py      # 仿真日志解析（供测试报告使用）
└── fw/                     # 固件：外设函数库 + 应用
    ├── Makefile            # CROSS 前缀可覆盖
    ├── app/                # 应用：start.S / main.c / irq.c / soc.ld
    └── lib/                # 外设函数库（可独立发布）
        ├── soc_addr.h      # 内存映射与寄存器定义
        ├── uart.c/h  i2c.c/h  gpio.c/h  timer.c/h
        ├── irq_ctrl.c/h    ctrl.c/h    print.c/h
```

## 地址映射

| 区域     | 基地址     | 说明                                              |
|----------|-----------|---------------------------------------------------|
| RAM      | 0x00000000 | 64KB 程序/数据 RAM（AXI4-Lite）                   |
| BOOT     | 0x10000000 | boot_ctrl：bit0=cpu_resetn（写），状态只读         |
| IRQ      | 0x20000000 | irq_ctrl：IER / IPR / MER                          |
| I2C0     | 0x30000000 | i2c_master_axil                                    |
| I2C1     | 0x30010000 | i2c_master_axil                                    |
| I2C2     | 0x30020000 | i2c_master_axil                                    |
| I2C3     | 0x30030000 | i2c_master_axil                                    |
| UART0    | 0x40000000 | uart_axil（TX/RX/状态/预分频）                     |
| UART1    | 0x40010000 | uart_axil                                          |
| APB0     | 0x50000000 | GPIO @+0x0000，TIMER0 @+0x1000                     |
| APB1     | 0x60000000 | CTRL @+0x0000，TIMER1 @+0x1000                     |

中断源映射（irq_ctrl 输入）：`[0] uart0_rx [1] uart0_tx [2] uart1_rx [3] uart1_tx [4] timer0 [5] timer1 [6] gpio`，汇总后接 PicoRV32 的 `irq[5]`。

## 环境要求

- Linux（开发环境为 WSL Ubuntu 24.04）
- [Verilator](https://www.veripool.org/verilator/) ≥ 5.x
- RISC-V 交叉工具链（`riscv-none-elf-*` 或 `riscv64-unknown-elf-*`，`-march=rv32im`）

## 快速开始

```bash
# 1. 编译固件（生成 fw/fw.hex，供仿真下载）
cd fw && make && cd ..
#    若工具链不在默认路径，覆盖 CROSS 前缀：
#    make CROSS=/opt/riscv32/bin/riscv-none-elf- fw.hex

# 2. 编译 Verilator 仿真（首次较慢）
cd sim && ./build_sim.sh && cd ..

# 3. 运行仿真（自动将 fw/fw.hex 经外部主机口下载到 RAM，然后释放 CPU 复位）
cd sim && ./run_sim.sh
```

仿真结束会打印各外设 `[PASS]/[FAIL]` 结果，最终以 `ctrl1 == 0xBEEF`（PASS）/ `0xDEAD`（FAIL）上报看门狗。全部外设（CTRL、GPIO、UART0/1、TIMER0/1、I2C0..3、中断）通过且无 CPU trap 即为成功。

详细的读写验证数据与总线/中断时序分析见 [docs/soc_test_report.md](docs/soc_test_report.md)。

## 固件库与应用的分离

`fw/lib` 是一套与具体应用解耦的外设函数库：

- 头文件 `<lib>/xxx.h` 提供寄存器级驱动 API；
- `soc_addr.h` 集中定义内存映射，与 `rtl/soc/soc_top.v` 一一对应；
- 应用只包含 `start.S`、`main.c`、`irq.c` 和链接脚本 `soc.ld`。

如需将库单独发布，仅需携带 `fw/lib` 目录并保持 `soc_addr.h` 中基地址与目标 SoC 一致。

## 许可证与致谢

- 本 SoC 专用 RTL 与固件：MIT，见 [LICENSE.md](LICENSE.md)。
- [PicoRV32](https://github.com/YosysHQ/picorv32)：ISC，`rtl/pico32/COPYING`（v1.0-72-ga473fc8, 2026-07-31）。
- [verilog-axi](https://github.com/alexforencich/verilog-axi) / [verilog-uart](https://github.com/alexforencich/verilog-uart) / [verilog-i2c](https://github.com/alexforencich/verilog-i2c)：MIT，`rtl/third_party/*/COPYING`（2025-02-27）。
