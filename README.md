# PicoRV32 SoC

基于 [PicoRV32](https://github.com/YosysHQ/picorv32)（AXI4-Lite 版本）和 [Alex Forencich](https://github.com/alexforencich) 的 AXI-Lite 基础设施搭建的轻量 RISC-V SoC。包含双主 AXI4-Lite 互联、64KB 程序 RAM、UART / I2C 外设、两路对外 APB master 接口（供芯片内部 GPIO / Timer / CTRL 等 APB 设备挂接）和中断控制器，可在 Verilator 下完整仿真验证。

## 应用场合

本 SoC 采用 **2MB 以内的紧凑地址编址**（每个 AXI-Lite 从口仅占 64KB，便于集成进其他芯片内部总线），可作为大型逻辑芯片（如智能网卡）内部的**可编程协处理器**：外部主控通过 AXI-Lite 下载固件、控制复位并随时升级，运行需要经常更新的控制面应用或算法，例如：

- **拥塞控制**：ECN 标记处理、RED/WRED 队列水位判断、拥塞感知的流调度策略；
- **流量控制**：令牌桶/漏桶整形、流级速率统计与限速；
- **链路探测**：BFD、LLDP、链路质量检测与故障上报；
- **路由协议**：BGP/OSPF 邻居状态机、路由表学习与下发。

相比把逻辑固化在 RTL 中，这种"软"控制面可随时更新固件而无需重新综合整个芯片，且 PicoRV32 面积小、功耗低，非常适合嵌入大型逻辑芯片做可编程协处理器。

## 特性

- **PicoRV32 AXI4-Lite**：`picorv32_axi` 作为 CPU 主口（RV32IM，兼容 CoreMark）。
- **双主 AXI-Lite 互联**：`axil_interconnect`（Alex Forencich）两个主口 ——
  - 主口 0：PicoRV32 CPU；
  - 主口 1：外部主机口，可用于固件下载、内核复位控制，以及直接访问全部外设（调试）。
- **64KB 程序 RAM**：AXI-Lite 接口，`axil_ram`，字节写使能支持。
- **复位控制**：`boot_ctrl` 寄存器模块，外部主机可拉低/释放 CPU 复位以便下载固件。
- **APB 地址线可重定位**：`boot_ctrl` 的 `APB0_BASE`（0x08）/ `APB1_BASE`（0x0C）两个 32 位寄存器（默认 0），叠加到 axil2apb 桥输出的 APB 地址线上：`apb_paddr = base + 64KB 窗口内偏移`。互联译码不变，仅地址线上携带完整地址，便于芯片内部 APB 设备按绝对地址译码。
- **外设**：4× I2C、2× UART、2× AXI-Lite→APB 桥（对外 APB0/APB1 master 接口，寄存器输出；GPIO / Timer / CTRL 等 APB 设备由外部挂接）、1× 中断控制器（irq_ctrl，含外部外设中断输入）。
- **RT-Thread**：Nano 内核已移植（`fw/rtos`），8 个测试任务并发运行全部 PASS（信号量同步、时钟节拍、中断驱动外设）。
- **固件结构**：外设函数库（`fw/lib`，可独立发布）+ RT-Thread（`fw/rtos`）+ 应用（`fw/app`），全部外设读写自检。
- **中断优化**：UART 中断改为边沿触发；中断路径经"跳过无切换调度尾巴 + 精简 irq_vec 寄存器保存/恢复"两轮优化，仿真总周期下降约 9.3%、`irq_vec` 区域下降 21%。
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
                    |  64K  ctrl ctl 0-3  0-1  (master)   (master)     |
                    +--------------------------------------------------+
                              | APB0 (paddr=base0+offset, reg out)
                              +------------+       | APB1 (paddr=base1+offset, reg out)
                                           |       +-----------+
                             (external) GPIO/TIMER0      CTRL/TIMER1
```

## 目录结构

```
picorv32-soc/
├── LICENSE.md              # 项目许可证（第三方组件保留各自许可证）
├── README.md
├── docs/
│   ├── soc_test_report.md  # 外设读写验证与时序分析测试报告
│   └── project_summary.md  # 完整项目工作总结（开发工具：TRAE Work + DeepSeek V4 Flash 正式版）
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
│       ├── uart_axil.v     # UART AXI4-Lite 封装（TX 中断边沿触发）
│       ├── axil2apb.v      # AXI4-Lite → APB 桥（32 位地址线，base_addr 可叠加，寄存器输出）
│       ├── apb_interconnect.v
│       ├── apb_gpio.v      # GPIO（含中断）
│       ├── apb_timer.v     # 定时器（含中断）
│       └── apb_ctrl.v      # 控制/状态寄存器
│                           # （以上 apb_* 外设现由外部芯片挂接，测试台 sim/soc_tb.v 例化）
├── sim/                    # Verilator 仿真
│   ├── soc_tb.v            # 顶层测试台（主机下载口 + APB 外设模型 + 周期记账）
│   ├── files_rtl.f         # RTL 源清单（相对路径）
│   ├── build_sim.sh        # 编译
│   ├── run_sim.sh          # 运行（自动取 fw/fw.hex 下载）
│   └── analyze_log.py      # 仿真日志解析（供测试报告使用）
└── fw/                     # 固件：外设函数库 + RT-Thread + 应用
    ├── Makefile            # CROSS 前缀可覆盖
    ├── app/                # 应用：start.S（启动+irq_vec）/ main.c / irq.c / soc.ld
    ├── lib/                # 外设函数库（可独立发布）
    │   ├── soc_addr.h      # 内存映射与寄存器定义
    │   ├── uart.c/h  i2c.c/h  gpio.c/h  timer.c/h
    │   ├── irq_ctrl.c/h    ctrl.c/h    print.c/h
    └── rtos/               # RT-Thread Nano 移植
        ├── src/            # 内核源码（scheduler/ipc/timer/thread/...）
        ├── libcpu/         # cpuport.c / context_gcc.S（PicoRV32 移植）
        └── board.c/rtconfig.h
```

## 地址映射

全部 AXI-Lite 从口压缩在 **2MB** 以内，每个从口占 **64KB**（`0x10000`）窗口，便于移植到其他芯片作为协处理器。

| 区域     | 基地址     | 说明                                              |
|----------|-----------|---------------------------------------------------|
| RAM      | 0x00000000 | 64KB 程序/数据 RAM（AXI4-Lite）                   |
| BOOT     | 0x00010000 | boot_ctrl：bit0=cpu_resetn（写），状态只读；0x08=APB0_BASE，0x0C=APB1_BASE |
| IRQ      | 0x00020000 | irq_ctrl：IER / IPR / MER                          |
| I2C0     | 0x00030000 | i2c_master_axil                                    |
| I2C1     | 0x00040000 | i2c_master_axil                                    |
| I2C2     | 0x00050000 | i2c_master_axil                                    |
| I2C3     | 0x00060000 | i2c_master_axil                                    |
| UART0    | 0x00070000 | uart_axil（TX/RX/状态/预分频）                     |
| UART1    | 0x00080000 | uart_axil                                          |
| APB0     | 0x00090000 | 对外 APB0 master（GPIO/TIMER0 等外部设备挂接）       |
| APB1     | 0x000A0000 | 对外 APB1 master（CTRL/TIMER1 等外部设备挂接）       |

**APB 地址线可重定位**：`BOOT_APB0_BASE`（0x00010008）和 `BOOT_APB1_BASE`（0x0001000C）为 32 位读写寄存器，复位默认 **0**。axil2apb 桥把 AXI 侧 64KB 窗口内偏移与 base 相加后输出到 32 位 APB 地址线：`apb_paddr = base + offset`。默认 0 时地址线仅携带窗口内偏移；写入非零值（如 0x000C0000）后，访问同一 AXI 地址对应的 APB 地址线变为 `0x000C0000 + offset`。互联译码不变，芯片内部 APB 设备可据此按绝对地址译码。

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

仿真结束会打印各任务/外设 `[PASS]/[FAIL]` 结果，最终以 `ctrl1 == 0xBEEF`（PASS）/ `0xDEAD`（FAIL）上报看门狗。全部 8 个 RT-Thread 任务（ctrl / gpio / uarttx / uartrx / timer / gpioirq / i2c / report）通过且无 CPU trap 即为成功。

详细的读写验证数据、时序分析与中断优化前后对比见 [docs/soc_test_report.md](docs/soc_test_report.md)。

## RT-Thread 多任务

`fw/rtos` 为 RT-Thread Nano 在 PicoRV32 上的移植：

- 线程帧布局 32 字：`[0]pc [1]ra [2]sp [3]gp [4..31]x4..x31`；
- `context_gcc.S`：`rt_hw_context_switch(_to/_interrupt/_exit)` 上下文切换（切换出口显式 `maskirq zero, zero` 解除中断屏蔽）；
- `start.S` 的 `irq_vec`（`PROGADDR_IRQ=0x10`）使用 PicoRV32 自定义 `setq/maskirq/retirq` 指令保存现场并切换中断栈；
- 8 个测试任务通过计数信号量汇合，最低优先级 `report` 汇总上报 PASS。

## 中断路径优化（阶段三）

通过 `soc_tb.v` 周期记账发现 CPU 周期主要消耗在中断向量区（`irq_vec`），其中约 72% 为内存停等周期。三轮优化：

1. **UART 中断边沿触发**（RTL）：`uart_axil.v` 由电平触发（`int_tx = s_axis_tready`，几乎恒高）改为 `tx_ready_d` 边沿检测 + `tx_irq_pend` 锁存，CPU 写 TXDATA 清除；固件新增 `uart_it_tx_kick()`。
2. **跳过无切换请求的中断调度尾巴**（`irq.c`）：`rt_interrupt_leave()` 后若 `rt_thread_switch_interrupt_flag==0` 直接返回，`ctx_asw` 周期 **-138k（-27%）**。
3. **精简 irq_vec 寄存器保存/恢复**（`start.S` + `cpuport.c`）：利用 ABI 约定，s2-s11 由合规 C ISR 调用链天然保存，向量仅存/恢复 22 个寄存器，切换时由 `rt_hw_irq_handle_switch` 从 CPU 活值补全。**总周期 -956k（-9.3%），irq_vec -946k（-21.1%）**。

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
- [RT-Thread](https://github.com/RT-Thread/rt-thread)：Apache-2.0，见 `fw/rtos/LICENSE-APACHE-2.0.txt`。

## 开发工具

本项目通过 **TRAE Work** 远程向 7×24 运行的小主机提交任务，全部 RTL / 固件 / 仿真 / 调试由 **DeepSeek V4 Flash 正式版** 完成。完整工作过程见 [docs/project_summary.md](docs/project_summary.md)。
