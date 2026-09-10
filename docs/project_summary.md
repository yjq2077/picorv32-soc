# PicoRV32 SoC 项目工作总结

- **项目名称**：PicoRV32 SoC（RV32IM 轻量 SoC，AXI4-Lite 架构）
- **开发方式**：通过 **TRAE Work** 远程向家中 7×24 运行的小主机提交任务，由 **DeepSeek V4 Flash 正式版** 完成全部 RTL / 固件 / 仿真代码与调试
- **仿真平台**：Verilator 5.x（100 MHz，周期 10 ns）
- **完成日期**：2026-08-30（阶段一~四）/ 2026-09-10（阶段五：APB 接口外置 + 地址线可重定位）
- **最终状态**：8/8 RT-Thread 任务通过，`ctrl1=0x0000beef`（PASS），无 CPU trap；APB0/APB1 作为对外 APB master 接口引出（寄存器输出），基地址可经 boot 寄存器在地址线上叠加重定位

---

## 1. 项目背景与目标

在基于 [PicoRV32](https://github.com/YosysHQ/picorv32)（AXI4-Lite 版 `picorv32_axi`）与 [Alex Forencich](https://github.com/alexforencich) 的 verilog-axi / verilog-uart / verilog-i2c 基础设施之上，搭建一个轻量、可仿真验证的 RISC-V SoC，并移植 RT-Thread 实时操作系统运行多任务自测，最后对中断路径做系统性性能优化。

**硬性约束**（贯穿全程）：
- 必须使用 `picorv32_axi`（AXI-Lite 接口变体）；
- RAM 上限 64 KB，且需仲裁 PicoRV32 与独立 AXI-Lite 下载口双访问；
- CPU 复位必须由经 AXI-Lite 访问的寄存器模块控制；
- AXI-Lite 互联需额外增加一个从口，供外部主机访问 RAM 与复位控制寄存器；
- UART 中断必须采用边沿触发而非电平触发。

## 2. 系统架构

双主 AXI4-Lite 互连（`axil_interconnect`）+ 11 个从口。阶段四起全部从口压缩在 **2MB 以内**，每个从口占 **64KB（`0x10000`）窗口**，便于作为协处理器嵌入其他大型逻辑芯片：

| 从口 | 基地址 | 外设 |
|---|---|---|
| RAM | `0x00000000` | 64 KB 指令/数据 RAM（`axil_ram`，字节写使能） |
| BOOT | `0x00010000` | `boot_ctrl` CPU 复位控制 + APB0_BASE/APB1_BASE（0x08/0x0C） |
| IRQ | `0x00020000` | `irq_ctrl` 中断控制器（16 源聚合） |
| I2C0-3 | `0x00030000`~`0x00060000` | `i2c_master_axil` ×4 |
| UART0-1 | `0x00070000`~`0x00080000` | `uart_axil` ×2 |
| APB0 | `0x00090000` | 对外 APB0 master（GPIO/TIMER0 由外部挂接）；**地址线可重定位** |
| APB1 | `0x000A0000` | 对外 APB1 master（CTRL/TIMER1 由外部挂接）；**地址线可重定位** |

阶段五起，APB0/APB1 不再在 SoC 内部挂接 APB 外设，而是作为**对外 APB master 接口**引出（全部输出为寄存器输出），GPIO/TIMER0/CTRL/TIMER1 移到 SoC 外由外部挂接，中断信号送回 `irq_ctrl` 聚合。`boot_ctrl` 的 `APB0_BASE`（0x08）/ `APB1_BASE`（0x0C）寄存器（默认 0）用于**地址线重定位**：axil2apb 桥输出 `apb_paddr = base + 64KB 窗口内偏移`（32 位地址线），互联译码保持固定不变（详见阶段五）。

中断映射：`[0] UART0_RX [1] UART0_TX [2] UART1_RX [3] UART1_TX [4] TIMER0 [5] TIMER1 [6] GPIO`，聚合后送入 PicoRV32 `irq[5]`。

固件侧由三层构成：
- `fw/rtos`：RT-Thread Nano 移植（`libcpu` 的 `cpuport.c` / `context_gcc.S` + `src` 内核源码 + `board.c` / `rtconfig.h`）；
- `fw/lib`：外设函数库（寄存器级驱动，可独立发布）；
- `fw/app`：应用（`start.S` 启动与中断向量、`main.c` 8 个测试任务、`irq.c` 中断服务）。

## 3. 开发工具链

| 工具 | 用途 |
|---|---|
| **TRAE Work** | 远程任务提交与结果回收（提交到家中 7×24 小主机执行） |
| **DeepSeek V4 Flash 正式版** | 全部代码编写、RTL 修改、固件移植、仿真调试与文档生成 |
| WSL Ubuntu 24.04 | 开发环境 |
| Verilator 5.050 | RTL 仿真 |
| riscv-none-elf-gcc 15.2.0（`-march=rv32im`） | 固件交叉编译 |
| Git / GitHub | 版本管理与代码托管 |

## 4. 工作阶段

### 阶段一：SoC 基础搭建与验证（2026-08-29）

- 完成 `soc_top.v` 顶层：`axil_interconnect` 双主 11 从互联、地址译码；
- 完成 `axil_ram`（64 KB 字节写）、`boot_ctrl`、`irq_ctrl`、`uart_axil`、`axil2apb` + `apb_interconnect` + `apb_gpio / apb_timer / apb_ctrl`；
- 编写 `soc_tb.v` 测试台：外部主机 AXI-Lite 下载口 + UART RX/TX 行为模型 + GPIO 驱动 + I2C EEPROM 从模型 + 结果看门狗（`ctrl1==0xBEEF`）；
- 编写 `fw/lib` 外设函数库与 `fw/app` 裸机自测；
- **结果**：14/14 外设检查 PASS，无 CPU trap，下载吞吐 ≈40 MB/s，APB 事务 3 拍完成。详见 [soc_test_report.md](soc_test_report.md)。

**阶段一解决的关键问题**：
- 启动即 trap：通过检查固件 ELF 并反汇编启动代码定位；增强 `soc_tb.v` 在 trap 时打印 16 条 PC 历史以辅助排查；
- UART RX 位采样时序（8×prescale 位周期对齐）；
- `apb_timer` 单次模式到期后须保持计数为 0 而非立即重装；
- `soc_tb.v` 中 UART RX 任务须用局部变量，避免与看门狗循环计数器冲突。

### 阶段二：RT-Thread 移植与 8 任务自测（2026-08-30 上午）

- 移植 RT-Thread Nano：`libcpu/cpuport.c`（线程帧 32 字布局，`[0]pc [1]ra [2]sp [3]gp [4..31]x4..x31`）+ `context_gcc.S`（`rt_hw_context_switch` / `switch_to` / `switch_interrupt` / `switch_exit`）；
- `start.S` 增加 `irq_vec` 中断向量（`PROGADDR_IRQ=0x10`），使用 PicoRV32 自定义 `setq/maskirq/retirq` 指令；
- 设计 8 个测试任务，通过计数信号量汇合：
  | 任务 | 优先级 | 验证内容 |
  |---|---|---|
  | ctrl | 10 | 控制寄存器读写、trap 清除、复位状态 |
  | gpio | 11 | GPIO 输入/输出/方向 |
  | uarttx | 12 | 中断驱动 UART0 发送 |
  | uartrx | 13 | 中断驱动 UART0 接收 |
  | timer | 14 | TIMER1 单次 + OS tick |
  | gpioirq | 15 | GPIO 上升沿中断 |
  | i2c | 16 | I2C0 EEPROM 读写 |
  | report | 17 | 信号量汇合汇总（最低优先级） |
- **结果**：8/8 任务全部 PASS。

**阶段二解决的关键问题**：
- 启动即 trap：通过固件 ELF 反汇编定位 `start.S` 启动代码问题；
- 任务上下文切换后中断屏蔽未解除（新任务以 `mask=0xFFFFFFFF` 恢复执行，UART TX 中断无法被服务）——在 `rt_hw_context_switch_exit` 恢复线程帧后添加 `maskirq zero, zero`；
- I2C 因 `i2c_master_axil.v` 无中断输出，确认采用轮询方式（保留在 `task_i2c`）。

### 阶段三：中断路径性能优化（2026-08-30 中午）

通过 `soc_tb.v` 增加周期记账（`[dbg] cyc irq_vec / irq_fn / rt_sched / ctx_asw / tick / sem`），定位 CPU 周期开销主要集中在中断向量区（32 寄存器保存/恢复，占约 29% 总周期，其中 72% 为内存停等周期）。

#### 优化 1：UART 中断改为边沿触发（RTL）

- 原实现：`int_tx = s_axis_tready`，几乎恒高 → 中断风暴；
- 改为：`uart_axil.v` 中 `tx_ready_d` 边沿检测 + `tx_irq_pend` 锁存，CPU 写 TXDATA 时清除；
- 固件新增 `uart_it_tx_kick()` 在 ISR 中为下一字节"踢一脚"；
- **收益**：`int_tx` 高电平周期大幅下降（约 69%），中断频率显著降低。

#### 优化 2（方向 1）：跳过无切换请求的中断调度尾巴

- 中断处理结束无论是否请求任务切换，都会执行 `rt_hw_irq_handle_switch` 尾巴；
- 在 `irq.c` 中：`rt_interrupt_leave()` 后若 `rt_thread_switch_interrupt_flag==0` 直接返回 `regs`，跳过 `rt_hw_irq_handle_switch`；
- **收益**：`ctx_asw` 区域周期 504,504 → 366,155（**-138k，-27%**），并消除 UART TX 字符错乱。

#### 优化 3（方向 2）：精简 irq_vec 寄存器保存/恢复

- 基于 ABI 约定：s2-s11 由合规的 C ISR 调用链天然保存，无需在向量入口存储；
- `start.S` 保存侧仅存 22 个寄存器（跳过 x18-x27），恢复侧按切换标志分支：无切换恢复 22 个、有切换恢复 32 个；
- `cpuport.c` 在切换时用内联汇编从 CPU 活值捕获 s2-s11 写入被中断线程帧（已反汇编验证仅用 a/t 寄存器，无 s 寄存器操作，安全）；
- **收益**（d1 → d2，固件行为一致、可严格对比）：
  | 指标 | 方向 1 | 方向 2 | 变化 |
  |---|---|---|---|
  | 总周期 | 10,296,224 | 9,340,283 | **-956k（-9.3%）** |
  | irq_vec 周期 | 4,476,667 | 3,530,240 | **-946k（-21.1%）** |
  | irq_vec 内存停等 | 3,263,806 | 2,564,226 | **-700k** |

**阶段三解决的关键问题**：
- `irq.c` 优化初期出现仿真总周期与中断数激增、UART TX 卡死（字符堆积环形缓冲未发送）——定位为回退版 UART 发送流程缺陷，优化版修复后所有任务正常；
- 方向 2 中 `rt_hw_irq_handle_switch` 若使用 s 寄存器会导致捕获值错误——通过反汇编确认仅用 a/t 寄存器保证安全。

### 阶段四：地址压缩与协处理器应用场合（2026-08-30 下午）

原地址映射分布在 0x10000000~0x60000000 高位地址空间，编址范围过大，不适合移植到其他芯片作为协处理器。本阶段：

- 将全部 AXI-Lite 从口压缩到 **2MB 以内**，每个从口固定 **64KB（`0x10000`）窗口**（简单外设足够用）；
- 修改 `rtl/soc/soc_top.v`（`M_BASE_ADDR` / `M_ADDR_WIDTH`，全部从口 `M_ADDR_WIDTH=16`）、`fw/lib/soc_addr.h`（基地址宏）、`sim/soc_tb.v`（boot_ctrl 释放复位地址）、`fw/lib/gpio.c`（注释）；
- README 开头新增**应用场合**：本 SoC 可作为大型逻辑芯片（如智能网卡）内部的可编程协处理器，运行拥塞控制、流量控制、链路探测、路由协议等需要经常更新的控制面应用或算法，外部主控经 AXI-Lite 下载固件、控制复位并随时升级；
- **回归结果**：地址压缩后重新编译固件与仿真，8/8 任务 PASS，`ctrl1=0x0000beef`，无 CPU trap；关键性能指标与压缩前完全一致（`total=9,340,283`、`irq_vec=3,530,240`、`ctx_asw=366,608`、UART TX 974 字符）。

**阶段四解决的关键问题**：首次回归 TIMEOUT（CPU 卡在 `poll_status` 死循环、零外设写）——定位为 `fw/Makefile` 的 `%.o: %.c` 规则不含头文件依赖，修改 `soc_addr.h` 后 `board.o` 等对象未重编，链接到旧地址固件；`make clean && make` 强制重建后恢复。建议后续为 Makefile 增加 `-MMD` 头文件依赖。

### 阶段五：APB 接口外置与地址线重定位（2026-09-10）

为便于把 SoC 作为协处理器嵌入大型逻辑芯片，APB0/APB1 两个 APB 域外置：不再在 SoC 内部挂接 APB 外设，而是作为**对外 APB master 接口**直接引出；GPIO / TIMER0 / CTRL / TIMER1 等 APB 设备移到芯片侧挂接，其中断信号送回 SoC 的 `irq_ctrl` 聚合。同时，外部主控可在运行时通过 boot 寄存器把 APB 地址线上携带的基地址整体平移：

- **`rtl/soc/boot_ctrl.v`**：新增两个 32 位读写寄存器 `APB0_BASE`（0x08）/ `APB1_BASE`（0x0C），复位默认 **0**，输出 `apb0_base` / `apb1_base`；
- **`rtl/soc/axil2apb.v`**：新增 `base_addr` 输入与 `APB_ADDR_WIDTH` 参数（设为 32）。AXI 侧地址为 64KB 窗口内偏移（16 位），桥捕获事务时输出 `apb_paddr = base_addr + 窗口内偏移`（去除 64KB 以上高位、保留偏移、叠加基地址），地址线扩展到 32 位；**全部 APB 输出（paddr / pwdata / pstrb / psel / penable / pwrite）寄存器化**，对外无组合路径；
- **`rtl/soc/soc_top.v`**：删除内部 `apb_interconnect` 及 `apb_gpio` / `apb_timer` / `apb_ctrl` 例化，引出顶层 `apb0_*` / `apb1_*` 端口（32 位地址线），新增 `gpio_intr` / `timer0_irq` / `timer1_irq` 外部中断输入接入 `irq_ctrl`，两桥 `base_addr` 接 boot 寄存器输出；
- **`rtl/third_party/verilog-axi/rtl/axil_interconnect.v`**：保持**静态译码不变**——回退此前为实现动态译码所做的 `M_DYNAMIC_BASE` 修改（从历史提交恢复），APB 窗口在互联中的位置固定（从口 9/10），重定位只体现在 APB 地址线上；
- **`sim/soc_tb.v`**：原 SoC 内部 APB 外设移至测试台例化（`apb_interconnect` + `apb_gpio` / `apb_timer` / `apb_ctrl`），外设译码使用 `apb*_paddr[15:0]` 窗口内偏移，与基地址无关；
- **`fw/lib/soc_addr.h`**：新增 `BOOT_APB0_BASE` / `BOOT_APB1_BASE` 宏。

**验证结果**（`sim/sim_apb_ext.log`）：寄存器默认值（0）、全字写回读（0x000C0000 / 0x000D0000）、**APB 地址线输出三态验证**全部 PASS —— 基地址为 0 时仅输出窗口内偏移（`0x00001000`）；写入非零后输出 `base + 偏移`（`0x000C1000` / `0x000D1000`）；恢复默认后回到偏移输出。随后释放 CPU 复位，**8/8 RT-Thread 任务 PASS、`ctrl1=0x0000beef`、无 CPU trap**，回归性能与阶段四一致（`total=9,340,403` ≈ 9,340,283、`irq_vec=3,530,240`、UART TX 974 字符），外置 + 寄存器化不影响互联仲裁与事务延迟（APB 读写仍为 3 拍）。

## 5. 最终成果

- **功能**：双主 AXI-Lite SoC，11 从口外设全部可访问，地址压缩至 2MB 内（每从口 64KB）便于移植作协处理器；APB0/APB1 基地址可经 boot 寄存器在运行时动态重定位；RT-Thread 8 任务并发自测全部 PASS；
- **性能**：
  - 固件下载吞吐 ≈ 39.9 MB/s；
  - APB 路径事务 3 拍（30 ns）；
  - 中断响应延迟（TIMER0/GPIO）≈ 8.7 µs；
  - 定时器单次模式计数精度 100%；
  - 中断路径经三轮优化，总周期较优化前下降约 9.3%（d1→d2 口径），`irq_vec` 区域下降 21%；
  - 地址压缩后性能与压缩前一致，无功能回归；
- **质量**：全程无 CPU trap，PASS 结果 `ctrl1=0x0000beef` 正确上报。

## 6. 经验教训

1. **周期记账是性能优化的前提**：先把"周期花在哪"量化，再决定优化方向；`irq_vec` 72% 的停等占比直接指向访存次数优化。
2. **ABI 约束可利用**：中断向量的寄存器保存可以依赖"调用者保存/被调用者保存"规范做减法，但必须反汇编验证编译器行为（如 s 寄存器捕获）。
3. **边沿触发优于电平触发**：对"请求型"外设中断（如 UART TX 就绪），电平触发会产生中断风暴，边沿 + 锁存 + 软件踢一脚是更优方案。
4. **仿真测试台是 Debug 利器**：trap 时打印 PC 历史、中断边沿计数、内存停等统计，能让问题从"玄学"变成可定位的工程问题。
5. **隔离变量**：对比优化效果时，保证固件行为一致（如 UART 字符数），否则总周期对比会被污染（本项目中 d1 与 d2 的 974 字符一致，对比才有效）。
6. **Makefile 必须有头文件依赖**：仅靠 `%.o: %.c` 编译，修改 `soc_addr.h` 这类被大量文件包含的头文件后，旧对象会带着旧值被链接，造成"改了地址但行为没变"的隐蔽故障。应使用 `-MMD -MP` 生成 `.d` 依赖（阶段四曾因此踩坑）。
7. **改动第三方 IP 要三思**：曾尝试给 `axil_interconnect` 增加 `M_DYNAMIC_BASE` 动态译码，经需求澄清后改为"互联保持静态译码、仅 APB 地址线叠加基地址"，最终从历史提交回退了互联模块的全部修改。对第三方基础设施的侵入式改动应尽量规避——能在外围模块（如桥）实现的特性就不要动互联；先确认需求再动手，避免返工。

## 7. 附：git 提交历史

```
1e8b3aa Move APB peripherals out of SoC; relocate base on APB address lines
5a91d7a Add boot_ctrl APB0/APB1 base registers with dynamic interconnect base addressing
0bc280f Compact AXI-Lite address map to 2MB (64KB per slave port) for coprocessor use
22bb1b8 Add project docs: RT-Thread/interrupt-optimization test data and work summary
0116381 Optimize UART/RT-Thread interrupt path: edge-trigger + latency reduction
640ab94 Add RT-Thread port, interrupt-driven UART and peripheral test tasks
cba4d55 Initial import: PicoRV32 SoC (AXI-Lite) with dual-master interconnect, peripherals, firmware library and Verilator testbench
```
