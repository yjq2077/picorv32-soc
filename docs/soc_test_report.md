# PicoRV32 SoC 外设读写验证与时序分析测试报告

- **测试对象**：PicoRV32 SoC（`soc_top.v`，AXI-Lite 架构）
- **测试平台**：Verilator 5.050（`--timing`，仿真时钟 100 MHz，周期 10 ns）
- **测试日期**：2026-08-29（阶段一：裸机外设自测）/ 2026-08-30（阶段二、三：RT-Thread 移植与中断路径优化；阶段四：地址压缩）/ 2026-09-10（阶段五：APB 接口外置 + 地址线可重定位）
- **总体结论**：**PASS**
  - 阶段一：14/14 项外设检查全部通过，0 失败，无 CPU trap；
  - 阶段二/三：RT-Thread 8/8 任务全部通过（`ctrl1=0x0000beef`），中断路径经三轮优化总周期下降约 9.3%；
  - 阶段四：地址压缩至 2MB 内（每从口 64KB）后回归通过，性能与压缩前一致；
  - 阶段五：APB 外设移出 SoC（APB0/APB1 对外 master 接口，寄存器输出），boot_ctrl 新增 APB0_BASE/APB1_BASE 地址线叠加验证通过，8/8 任务回归 PASS。

> 本文第 1-6 节为阶段一裸机外设验证与总线/中断时序分析；第 7 节起为阶段二、三（RT-Thread 移植 + 中断优化）的测试数据与性能对比；第 10 节为阶段四地址压缩；第 11 节为阶段五 APB 接口外置与地址线重定位。

---

## 1. 系统架构与地址映射

本 SoC 采用双主（PicoRV32 CPU + 外部主机下载口）AXI-Lite 互连（`axil_interconnect`，来自 Verilog-AXI 基础设施库），挂接 11 个从口。**阶段四起全部从口压缩在 2MB 地址空间内，每个从口仅占 64KB（`0x10000`）窗口**，便于作为协处理器嵌入其他大型逻辑芯片：

| 从口 | 基地址 | 外设 | 说明 |
|---|---|---|---|
| 0 | `0x00000000` | `axil_ram` | 64 KB 指令/数据 RAM |
| 1 | `0x00010000` | `boot_ctrl` | CPU 复位控制（下载用）+ APB0_BASE/APB1_BASE 地址线重定位寄存器 |
| 2 | `0x00020000` | `irq_ctrl` | 中断控制器（16 源聚合） |
| 3-6 | `0x00030000`~`0x00060000` | `i2c_master_axil` ×4 | I2C 主控制器（alexforencich） |
| 7-8 | `0x00070000`~`0x00080000` | `uart_axil` ×2 | UART 串口（alexforencich） |
| 9 | `0x00090000` | APB0 master | 经 `axil2apb` 桥引出 SoC 外（32 位地址线，寄存器输出），GPIO/TIMER0 由外部挂接；**地址线可重定位** |
| 10 | `0x000A0000` | APB1 master | 经 `axil2apb` 桥引出 SoC 外（32 位地址线，寄存器输出），CTRL/TIMER1 由外部挂接；**地址线可重定位** |

阶段五起，APB0/APB1 不再在 SoC 内部挂接 APB 外设，而是作为**对外 APB master 接口**直接引出（全部输出为寄存器输出），GPIO / TIMER0 / CTRL / TIMER1 等 APB 设备移到 SoC 外由外部芯片挂接，其中断（`gpio_intr` / `timer0_irq` / `timer1_irq`）仍送回 SoC 的 `irq_ctrl` 聚合。`boot_ctrl` 的 `APB0_BASE`（0x08）/ `APB1_BASE`（0x0C）寄存器（默认 **0**）用于**APB 地址线重定位**：axil2apb 桥把 AXI 侧 64KB 窗口内偏移与 base 相加，输出到 32 位 APB 地址线 `apb_paddr = base + offset`；互联译码保持固定不变（详见第 11 节）。

中断映射：`[0]` UART0_RX、`[1]` UART0_TX、`[2]` UART1_RX、`[3]` UART1_TX、`[4]` TIMER0、`[5]` TIMER1、`[6]` GPIO，聚合后送入 PicoRV32 `irq[5]`。

---

## 2. 总体流程时间线

由外部主机口完成固件下载 → 通过 `boot_ctrl` 释放 CPU 复位 → CPU 运行自测 → 写 `ctrl1=0xBEEF` 报告 PASS。

| 阶段事件 | 时间 (ns) | 说明 |
|---|---|---|
| 系统复位释放 (`rst_n` 拉高) | ≈ 250 | 复位 25 拍后释放 |
| 下载开始（首个主机写） | 385 | 写入 RAM |
| 下载结束（第 1662 字） | 166,785 | 1662 字共耗时 166.4 µs |
| `boot_ctrl.CTRL` 写 `1` | 166,805 | 请求释放 CPU 复位 |
| `cpu_resetn` 拉高 | 166,825 | 写后 20 ns（2 拍）生效 |
| **CPU 首次取指** | 166,885 | 复位释放后 60 ns（6 拍） |
| 自测完成（`ctrl1=0xBEEF`） | 3,605,275 | 自测耗时 3,438,450 ns（≈3.44 ms） |
| 仿真结束 | ≈ 3,606,000 | `$finish` |

- **下载吞吐率**：6648 字节 / 166.4 µs ≈ **39.9 MB/s**，每字平均 100 ns（10 拍/字，含互连握手）。
- 复位释放写 → `cpu_resetn` 生效仅 2 拍（`boot_ctrl` 直接 `assign cpu_resetn = ctrl[0]`）。
- 复位释放 → 首次取指 6 拍（CPU 复位撤除后的启动周期 + RAM 读延迟）。

---

## 3. 外设读写验证数据

### 3.1 boot_ctrl（复位控制 + APB 基地址，0x00010000）

| 操作 | 地址 | 数据 | 结果 |
|---|---|---|---|
| 主机写 CTRL | 0x00 | 0x1 | `cpu_resetn` 拉高，CPU 启动 |
| CPU 读 STATUS | 0x04 | bit0=1（running）、bit1=0（trap 清除） | PASS |
| 主机读 APB0_BASE | 0x08 | 0x00000000（复位默认） | PASS |
| 主机读 APB1_BASE | 0x0C | 0x00000000（复位默认） | PASS |
| 主机写 APB0_BASE | 0x08 | 0x000C0000 → 读回 0x000C0000 | PASS（RW） |
| 主机写 APB1_BASE | 0x0C | 0x000D0000 → 读回 0x000D0000 | PASS（RW） |
| 主机恢复默认 | 0x08 / 0x0C | 0x00000000 | 恢复固定映射 |

固件检查 `BOOT_STATUS & 0x1 == 1`（复位已释放）、`BOOT_STATUS & 0x2 == 0`（无 trap）均通过。APB 基地址寄存器为 32 位读写（复位默认 0），测试台完成下载后先验证默认值与读写回读，并在释放复位前采样 `apb0/1_paddr` 验证地址线叠加（详见第 11 节），再恢复为 0 以保持固定地址映射，随后释放 CPU 复位。

### 3.2 irq_ctrl（中断控制器，0x00020000）

捕获到的 AXI-Lite 读写序列（AW/W 与 R 均为 3 拍事务）：

| 时间 (ns) | 操作 | 地址 | 数据 | 含义 |
|---|---|---|---|---|
| 176,665 | R | IPR(0x04) | 0x00000000 | 无挂起（定时器测试前轮询） |
| 2,291,435 | W | IER(0x00) | 0x00000000 | 关全部中断源 |
| 2,292,285 | W | MER(0x08) | 0x00000000 | 关主中断 |
| 2,295,075 | W | IER(0x00) | 0x00000010 | 使能 TIMER0（bit4） |
| 2,295,925 | W | MER(0x08) | 0x00000001 | 开主中断 |
| 2,311,075 | R | IPR | 0x00000010 | 读到 TIMER0 挂起 → ISR 响应 |
| … | R | IPR | 0x00000010 ×15 | 定时器中断风暴 |
| 2,622,495 | W | MER | 0 | 关闭主中断 |
| 2,623,245 | W | IER | 0 | 关闭全部源 |
| 2,761,455 | W | IER | 0x00000040 | 使能 GPIO（bit6） |
| 2,762,305 | W | MER | 1 | 开主中断 |
| 2,770,985 | R | IPR | 0x00000040 | 读到 GPIO 挂起 → ISR 响应 |
| 2,801,195 | W | IER / MER | 0 / 0 | 收尾关闭 |

**验证结论**：IER 使能位、MER 主开关、IPR 挂起读回全部正确；TIMER0 与 GPIO 中断源均被正确识别。

### 3.3 GPIO（APB0，0x00090000）

| 操作 | 地址 | 写数据 | 读回数据 | 结果 |
|---|---|---|---|---|
| 读 IN | 0x04 | - | 0x00AA | PASS（TB 驱动 0x00AA） |
| 写 DIR | 0x08 | 0xFFFF | - | 全输出 |
| 写 OUT | 0x00 | 0x5A5A | 0x5A5A | PASS |
| 写 OUT | 0x00 | 0xA5A5 | 0xA5A5 | PASS |
| 写 DIR | 0x08 | 0x0000 | - | 恢复全输入 |

GPIO 输入采样、输出回读、方向控制均正确。GPIO 上升沿中断（bit0）由 TB 在 "GPIOIRQ" 标记后翻转 `gpio_in[0]` 触发，ISR 通过 IPR 识别并清除，中断触发验证通过。

### 3.4 CTRL 控制寄存器（APB1，0x000A0000）

| 操作 | 地址 | 写数据 | 读回数据 | 结果 |
|---|---|---|---|---|
| 读 VERSION | 0x0C | - | 0x00000001 | 版本号正确 |
| 写/读 REG0 | 0x00 | 0x11112222 | 0x11112222 | PASS |
| 写/读 REG1 | 0x04 | 0x33334444 | 0x33334444 | PASS |
| 写/读 REG2 | 0x08 | 0x55556666 | 0x55556666 | PASS |
| 写 REG1 | 0x04 | 0x0000BEEF | - | 结果标记（PASS） |

### 3.5 UART0 / UART1（0x00070000 / 0x00080000）

配置：`UART_PRESCALE=2`，位时间 = 2×8 = 16 拍 = 160 ns → **波特率 6.25 Mbps**。

**UART0 发送**（TB 解码还原）：
```
UART0 TX: Hello from PicoRV32 SoC! 0123456789 abcdef
```
**UART1 发送**：
```
UART1 TX: secondary serial port alive.
```
两路 TX 串行位流解码与发送内容完全一致（起始位/8 数据位/停止位，每字符 16 拍）。

**UART0 接收**：固件打印 "RXREADY" 标记 → TB 监测到后发送字符 `'A'`（0x41）→ 固件 `uart_getc` 收到：

```
uart0 rx byte = 0x41 'A'     [PASS] uart0 rx
```

RX 数据正确无毛刺、无误码，验证了此前修复的 RX 位采样时序（8×prescale 位周期对齐）。

### 3.6 I2C0（0x00030000，alexforencich i2c_master_axil）

对挂接在总线 0 上的 7 位地址 `0x50` 的 EEPROM 从模型执行读写：

| 测试 | 内容 | 返回 | 结果 |
|---|---|---|---|
| 写 | 字节 `{0x00, 0xAA, 0xBB, 0xCC}`（首个为内部指针） | rc=0 (I2C_OK) | PASS |
| 写后读 | 设置指针 0x00 后连续读 4 字节 | rc=0，数据 `AA BB CC 00` | PASS |

读回数据与写入数据逐字节一致，验证 START/STOP、地址+ACK、多字节连续传输协议。全测试期间总线 0 共产生 **111 次 SCL 下降沿**（含地址、数据、ACK 位），总线活动正常。

### 3.7 TIMER0（APB0，0x00091000）

**单次模式（one-shot）**：`RELOAD=0x3E8`（1000），使能后轮询 COUNT 寄存器，捕获到的完整计数序列：

| 轮询时间 (ns) | COUNT (hex) | COUNT (dec) | 相邻递减 |
|---|---|---|---|
| 2,132,215 | 0x394 | 916 | - |
| 2,133,365 | 0x321 | 801 | 115 |
| 2,134,515 | 0x2AE | 686 | 115 |
| 2,135,665 | 0x23B | 571 | 115 |
| 2,136,815 | 0x1C8 | 456 | 115 |
| 2,137,965 | 0x155 | 341 | 115 |
| 2,139,115 | 0x0E2 | 226 | 115 |
| 2,140,265 | 0x06F | 111 | 115 |
| 2,141,415 | **0x000** | **0** | 到期（保持 0） |

- 每两次轮询间隔 1150 ns，计数精确递减 115 → **1 计数 = 1 时钟 = 10 ns，计数精度 100%**。
- 到期后计数保持 0 不再重装，固件轮询 `COUNT==0` 判定超时，单次模式验证通过。

**自动重载 + 中断模式**：`RELOAD=0x1F4`（500）→ 理论周期 5 µs。捕获到 16 次连续中断事件（详见时序分析 4.3），ISR 每次读取 IPR、写 IACK 清标志，最终主循环检测到 `irq_timer0_fired` 并关闭定时器，`[PASS] timer0 irq`。

---

## 4. 时序分析

### 4.1 总线事务延迟（AXI-Lite → APB 桥路径）

以监视器捕获的时间戳（10 ns 分辨率）统计：

| 路径 | 事务 | 请求时间 (ns) | 响应时间 (ns) | 延迟 |
|---|---|---|---|---|
| APB0 读（GPIO IN） | AR→RVALID | 1,147,365 | 1,147,395 | **30 ns / 3 拍** |
| APB0 写（GPIO DIR） | AW→BVALID | 1,146,705 | 1,146,735 | **30 ns / 3 拍** |
| APB1 读（CTRL VER） | AR→RVALID | 451,785 | 451,815 | **30 ns / 3 拍** |
| APB1 写（CTRL REG0） | AW→BVALID | 594,455 | 594,485 | **30 ns / 3 拍** |
| IRQ 控制寄存器 | AR→RVALID | 1,766,655 | 1,766,665 | **10 ns / 1 拍** |
| RAM 读（取指） | AR→RVALID | — | — | 2 拍（RTL 状态机 IDLE→READ→RESP） |

> APB 路径 3 拍 = 互连仲裁/路由 1 拍 + `axil2apb` 桥（SETUP 1 拍 + ACCESS 1 拍，APB 从设备 `pready=1` 单周期应答）。全部事务 `resp=OKAY`，无超时、无重试。

### 4.2 CPU 启动与指令流

| 指标 | 数值 |
|---|---|
| 复位释放写 → `cpu_resetn` 生效 | 20 ns（2 拍） |
| `cpu_resetn` → 首次取指 | 60 ns（6 拍） |
| 全测试 RAM 读（AR）事务数 | 30,184 |
| 全测试 RAM 写（AW）事务数 | 4,798 |
| RAM 事务合计 | 34,982 |
| 互连状态机跳变次数 | 151,305 |

RAM 读事务绝大部分为取指，写事务为固件数据写入；双主仲裁（CPU 取指 + 主机下载）无冲突，验证了互连扩展从口的正确性。

### 4.3 中断响应时序

**TIMER0 中断**（自动重载，5 µs 周期）：
- 定时器使能（`CTRL=0x7` 写完成）于 2,297,305 ns。
- 首次 `IRQ_OUT` 上升沿：**2,302,325 ns**（使能后 ≈5.02 µs，与 500 拍理论值吻合）。
- 中断响应：ISR 读取 IPR（0x10）于 2,311,075 ns → **IRQ 断言到 ISR 识别源延迟 = 8,750 ns**。

**GPIO 中断**：
- TB 翻转 `gpio_in[0]` 后 `IRQ_OUT` 上升沿：2,762,325 ns。
- ISR 读取 IPR（0x40）：2,770,995 ns → **响应延迟 = 8,670 ns**。

> 该延迟包含：PicoRV32 中断进入（`PROGADDR_IRQ=0x10` 跳转、寄存器现场保存）+ ISR 序言 + IPR AXI 读事务（3 拍）。两次测量接近一致，中断路径确定且稳定。

**中断风暴说明**：TIMER0 自动重载周期 5 µs 短于 ISR 服务时间（≈10 µs，因 IPR 读 + IACK 写均走慢速 APB/AXI 路径），故出现连续 16 次 `IRQ_OUT` 脉冲（高 10 µs / 低 1 µs 交替），主循环直至检测到 `irq_timer0_fired` 标志后关闭定时器与中断。行为符合 PicoRV32 单核 + 慢速外设总线的预期特性，不影响功能正确性。

### 4.4 定时器精度

- 单次模式：10 µs（RELOAD=1000）精确到计数周期，轮询观测逐 10 ns 递减，**误差 = 0**。
- 自动重载模式：5 µs（RELOAD=500），首次中断与理论值偏差 < 1%。

### 4.5 I2C 总线活动

- 总线 0 全测试 **111 次 SCL 下降沿**，对应：写（1 地址 + 4 数据 + ACK）+ 写读（1 地址 + 1 指针 + 4 读数据 + ACK/NACK）≈ 10 字节 × 9 SCL/字节 + 起始/停止。
- 所有 ACK 正常，无 NACK 导致的失败，读回数据逐字节一致。

---

## 5. 性能汇总

| 指标 | 数值 |
|---|---|
| 系统时钟 | 100 MHz |
| 固件体积 | 6648 字节（1662 字） |
| 固件下载吞吐 | ≈ 39.9 MB/s |
| 下载阶段耗时 | 166.4 µs |
| 全自测耗时（复位释放→结果） | 3.438 ms |
| APB 读写事务延迟 | 30 ns（3 拍） |
| 中断响应延迟（TIMER0 / GPIO） | 8.75 µs / 8.67 µs |
| UART 波特率 | 6.25 Mbps（prescale=2） |
| I2C SCL 下降沿 | 111 |
| CPU trap | 0（全程无） |

---

## 6. 结论

1. **功能正确性**：14/14 项外设检查全部 PASS（boot/复位控制、中断控制器、GPIO、CTRL 寄存器、UART0/1 收发、I2C0 读写、TIMER0 单次与中断），无 CPU trap，结果标记 `ctrl1=0xBEEF` 正确写入并回读。
2. **总线协议**：双主 AXI-Lite 互连在「主机下载 + CPU 运行」场景下仲裁正确；AXI-Lite→APB 桥 3 拍完成事务，全部 `OKAY` 响应。
3. **下载链路**：外部主机口可经互连访问 RAM 与复位控制寄存器，下载 1662 字后成功释放内核，验证了扩展从口的预期能力。
4. **时序指标**：中断响应 ≈8.7 µs、定时器计数 100% 精确、下载吞吐 ≈40 MB/s，均在合理范围。

**遗留说明**：本报告数据来自 `soc_tb.v`（`+define+ENABLE_DBG` 调试监视版）的 Verilator 仿真日志（`sim/sim_dbg3.log`），监视点包括 CPU 复位/取指、RAM 事务计数、互连状态跳变、IRQ 控制器事务、APB0/APB1 全部读写、中断边沿与 I2C SCL 活动。I2C1-3、UART1 RX、TIMER1 未在固件自测中覆盖，如需可扩展固件用例复测。

---

## 7. 阶段二：RT-Thread 移植与 8 任务自测

在阶段一裸机自测全部通过后，移植 RT-Thread Nano 至 PicoRV32：

- **`fw/rtos`**：内核源码（`src/`）+ `libcpu` 移植（`cpuport.c` 线程帧 32 字布局 `[0]pc [1]ra [2]sp [3]gp [4..31]x4..x31`，`context_gcc.S` 上下文切换汇编）；
- **`start.S` `irq_vec`**：中断向量（`PROGADDR_IRQ=0x10`），使用 PicoRV32 自定义 `setq/maskirq/retirq` 指令保存现场、屏蔽嵌套中断、切中断栈；
- **8 个测试任务**（优先级 10-17，通过计数信号量汇合，最低优先级 `report` 汇总）：

| 任务 | 优先级 | 验证内容 |
|---|---|---|
| ctrl | 10 | 控制寄存器读写、trap 清除、复位状态 |
| gpio | 11 | GPIO 输入/输出/方向 |
| uarttx | 12 | 中断驱动 UART0 发送（974 字符） |
| uartrx | 13 | 中断驱动 UART0 接收 |
| timer | 14 | TIMER1 单次 + OS tick（mdelay 10ms） |
| gpioirq | 15 | GPIO 上升沿中断 |
| i2c | 16 | I2C0 EEPROM 读写 |
| report | 17 | 信号量汇合汇总 |

**结果**：8/8 任务全部 `[PASS]`，最终 `=== TEST RESULT: PASS (ctrl1=0x0000beef) ===`，全程无 CPU trap。

期间修复的关键问题：
- **启动即 trap**：反汇编固件 ELF 定位 `start.S` 启动代码问题；`soc_tb.v` 增强为 trap 时打印 16 条 PC 历史；
- **任务切换后中断被屏蔽**：新任务以 `mask=0xFFFFFFFF` 恢复导致 UART TX 中断无法服务——在 `rt_hw_context_switch_exit` 恢复线程帧后补 `maskirq zero, zero`；
- **I2C 无中断输出**：`i2c_master_axil.v` 无 interrupt 引脚，`task_i2c` 确认采用轮询。

## 8. 阶段三：中断路径性能优化

### 8.1 周期记账与瓶颈定位

在 `soc_tb.v` 增加按 PC 区域的周期记账（`[dbg] cyc irq_vec / irq_fn / rt_sched / ctx_asw / tick / sem`）与内存停等统计（`mem_valid && !mem_ready`）。定位结果：CPU 周期主要消耗在**中断向量区**（`irq_vec`，0x10..0x200），其中约 **72% 为内存停等周期**（指令取指 + 现场保存/恢复的数据访问均需经 AXI-Lite 互联访问 RAM）。

### 8.2 优化 1：UART 中断边沿触发（RTL）

- 原实现 `int_tx = s_axis_tready` 几乎恒高 → 电平触发中断风暴；
- `uart_axil.v` 增加 `tx_ready_d` 边沿检测与 `tx_irq_pend` 锁存，CPU 写 TXDATA 时清除；
- 固件新增 `uart_it_tx_kick()` 在 ISR 中为下一字节重新武装；
- **收益**：`int_tx` 高电平周期大幅下降（约 69%）。

### 8.3 优化 2（方向 1）：跳过无切换请求的中断调度尾巴

- `irq.c` 在 `rt_interrupt_leave()` 后判断：若 `rt_thread_switch_interrupt_flag==0`（常见无切换场景）直接返回，不再调用 `rt_hw_irq_handle_switch`；
- **收益**（基版 → 方向 1）：`ctx_asw` 区域周期 **504,504 → 366,155（-138k，-27%）**，并消除 UART TX 字符错乱。

### 8.4 优化 3（方向 2）：精简 irq_vec 寄存器保存/恢复

- 基于 ABI 约定（s2-s11 由合规 C ISR 调用链天然保存），`start.S` 保存侧仅存 22 个寄存器（跳过 x18-x27）；恢复侧按切换标志分支——无切换恢复 22 个、有切换恢复 32 个；
- `cpuport.c` 切换时用内联汇编从 CPU 活值捕获 s2-s11 写入被中断线程帧（已反汇编验证仅用 a/t 寄存器，安全）；
- **收益**（方向 1 → 方向 2，固件行为一致、974 字符不变，可严格对比）：

| 指标 | 方向 1 | 方向 2 | 变化 |
|---|---|---|---|
| **总周期** | 10,296,224 | 9,340,283 | **-956k（-9.3%）** |
| **irq_vec 周期** | 4,476,667 | 3,530,240 | **-946k（-21.1%）** |
| irq_vec 内存停等 | 3,263,806 | 2,564,226 | **-700k** |
| 停等占比 | 72% | 72% | 持平 |
| ctx_asw | 366,155 | 366,608 | ~不变 |
| UART TX 字符 | 974 | 974 | 一致 |

> 说明：优化效果集中在 `irq_vec`（固定 0x10..0x200 区域），`total` 与 `irq_vec`/`stall_irqvec` 为可靠对比指标；`irq_fn` 因编译后 `irq()` 地址上移、`uart_it_tx_kick` 部分落入硬编码 PC 区域，跨版本不可直接对比，未采用。

### 8.5 中断计数相关指标（方向 2 最终版）

```
[dbg] uart0 txd_write=974 rxd_read=1 tx_pend_hi=974 int_tx_hi=9181495 ier1_hi=4142351
[dbg] irq rise=1990 high=4008903 cyc cpu_irq_taken=5471129 timer0_irq_hi=170913
[dbg] cyc total=9340283 irq_vec=3530240 irq_fn=962668 rt_sched=7146 ctx_asw=366608 tick=27076 sem=7486
[dbg] stall total=6506143 irqvec=2564226 (irqvec stall 72%)
=== TEST RESULT: PASS (ctrl1=0x0000beef) ===
```

## 9. 阶段二/三 结论

1. RT-Thread Nano 在 PicoRV32（AXI-Lite）上稳定运行：8 任务并发、信号量同步、时钟节拍、中断驱动外设全部正确。
2. 中断路径经三轮优化（边沿触发 → 跳过调度尾巴 → 精简向量寄存器保存），总周期下降约 9.3%、`irq_vec` 区域下降 21%，且无功能回归。
3. 内存停等（经 AXI-Lite 互联访问 RAM）是中断向量的主要开销来源（72%），方向 2 通过减少现场保存/恢复的访存次数直接削减停等 700k 周期。

---

## 10. 阶段四：地址压缩（2MB 内，每从口 64KB）

原地址映射分布在 0x10000000~0x60000000 高位地址空间，编址范围过大，不适合移植到其他芯片作为协处理器。本阶段将全部 AXI-Lite 从口压缩到 **2MB 以内**，每个从口固定 **64KB（`0x10000`）窗口**，便于嵌入大型逻辑芯片（如智能网卡）内部总线，作为可编程协处理器运行拥塞控制、流量控制、链路探测、路由协议等需要经常更新的控制面应用。

### 10.1 改动内容

| 文件 | 改动 |
|---|---|
| `rtl/soc/soc_top.v` | `axil_interconnect` 的 `M_BASE_ADDR` / `M_ADDR_WIDTH` 改为紧凑映射，全部从口 `M_ADDR_WIDTH=16`（64KB） |
| `fw/lib/soc_addr.h` | 全部外设基地址宏同步更新为 2MB 内新地址 |
| `sim/soc_tb.v` | 主机口释放 CPU 复位的 `boot_ctrl` 地址 `0x10000000 → 0x00010000` |
| `fw/lib/gpio.c` | 注释中的 GPIO 基地址更新 |

新地址映射（详见第 1 节）：RAM `0x00000000`、BOOT `0x00010000`、IRQ `0x00020000`、I2C0-3 `0x00030000`~`0x00060000`、UART0/1 `0x00070000`/`0x00080000`、APB0 `0x00090000`（GPIO+TIMER0）、APB1 `0x000A0000`（CTRL+TIMER1），总计仅占 **0x000AFFFF（< 2MB）**。

### 10.2 回归结果

地址压缩后重新编译固件与仿真，**8/8 RT-Thread 任务全部 PASS，`ctrl1=0x0000beef`，无 CPU trap**：

```
[host] fw.hex loaded: 5341 words (21364 bytes)
[host] downloaded 5341 words to RAM
[host] ram[0]  = 0x4840006f
[host] cpu reset released (boot_ctrl=1)
=== TEST RESULT: PASS (ctrl1=0x0000beef) ===
[dbg] uart0 txd_write=974 rxd_read=1 tx_pend_hi=974 int_tx_hi=9181495 ier1_hi=4142351
[dbg] irq rise=1990 high=4008903 cyc cpu_irq_taken=5471129 timer0_irq_hi=170913
[dbg] cyc total=9340283 irq_vec=3530240 irq_fn=962668 rt_sched=7146 ctx_asw=366608 tick=27076 sem=7486
[dbg] stall total=6506143 irqvec=2564226 (irqvec stall 72%)
```

关键性能指标与地址压缩前（阶段三方向 2 最终版）**完全一致**：`total=9,340,283`、`irq_vec=3,530,240`、`ctx_asw=366,608`、UART TX 974 字符。地址译码宽度与基址对齐（全部基址为 `0x10000` 倍数）不影响互联仲裁与事务延迟。

### 10.3 回归过程中的关键问题

首次回归 **TIMEOUT**：CPU 卡在 `poll_status` 死循环（PC 0x1644/0x1654），且全程零外设写操作。定位后发现 `fw/fw.elf` 的 `.data` 中 `uart0_inst.base=0x40000000`（旧地址）——`fw/Makefile` 的 `%.o: %.c` 规则不含头文件依赖，修改 `soc_addr.h` 后 `board.o` 等对象未重编，链接使用了旧对象。**`make clean && make` 强制重建后恢复正常**。建议后续为 Makefile 增加 `-MMD` 头文件依赖生成，避免同类问题。

## 11. 阶段五：APB 接口外置与地址线重定位

### 11.1 需求与设计

为便于把本 SoC 作为协处理器嵌入大型逻辑芯片，APB0/APB1 两个 APB 域不再在 SoC 内部挂接外设，而是作为**对外 APB master 接口**直接引出到 `soc_top` 之外；GPIO / TIMER0 / CTRL / TIMER1 等 APB 设备移到芯片侧挂接，其中断信号送回 SoC 的 `irq_ctrl` 聚合。同时，`boot_ctrl` 的 `APB0_BASE` / `APB1_BASE` 寄存器允许外部主控在**运行时把 APB 地址线上携带的基地址整体平移**，便于避开芯片内其他主设备的地址冲突。实现方式：

- **`rtl/soc/boot_ctrl.v`**：新增两个 32 位读写寄存器 —— `APB0_BASE`（0x08）与 `APB1_BASE`（0x0C），复位默认 **0**，输出 `apb0_base` / `apb1_base`；
- **`rtl/soc/axil2apb.v`**：新增 `base_addr` 输入与 `APB_ADDR_WIDTH` 参数（设为 32）。AXI 侧地址本为 64KB 窗口内偏移（16 位），桥在 IDLE 捕获事务时将 `base_addr + 窗口内偏移` 写入地址寄存器，APB 地址线扩展到 32 位输出 `apb_paddr = base + offset`（去除 64KB 以上高位、保留偏移、再叠加基地址）。**全部 APB 输出（paddr / pwdata / pstrb / psel / penable / pwrite）改为寄存器输出**，对外无组合路径；
- **`rtl/soc/soc_top.v`**：删除内部 `apb_interconnect` 及 `apb_gpio` / `apb_timer` / `apb_ctrl` 例化，将两路 `axil2apb` 桥的 APB 主口引出为顶层 `apb0_*` / `apb1_*` 端口（32 位地址线），新增 `gpio_intr` / `timer0_irq` / `timer1_irq` 外部中断输入接入 `irq_ctrl`；两桥 `base_addr` 分别接 boot 寄存器输出；
- **`rtl/third_party/verilog-axi/rtl/axil_interconnect.v`**：保持**静态译码不变**（回退此前为动态译码所做的修改），APB 窗口在互联中的位置固定（从口 9/10 = `0x00090000` / `0x000A0000`），重定位只体现在 APB 地址线上；
- **`sim/soc_tb.v`**：原 SoC 内部 APB 外设移至测试台例化 —— `apb_interconnect` + `apb_gpio` + `apb_timer`（APB0 侧 GPIO/TIMER0）、`apb_ctrl` + `apb_timer`（APB1 侧 CTRL/TIMER1），外设译码使用 `apb0_paddr[15:0]` / `apb1_paddr[15:0]` 窗口内偏移，与基地址无关。

### 11.2 测试台验证

`sim/soc_tb.v` 在固件下载完成后、释放 CPU 复位前，对外部主机口依次验证寄存器读写与 APB 地址线输出（`soc_tb` 直接采样顶层 `apb0_paddr` / `apb1_paddr`）：

```
[host] boot APB0_BASE default = 0x00000000 (expect 0x00000000)      PASS
[host] boot APB1_BASE default = 0x00000000 (expect 0x00000000)      PASS
[host] APB0 paddr base=0        = 0x00001000 (offset only, expect 0x00001000)  PASS
[host] boot APB0_BASE      = 0x000c0000 (expect 0x000c0000)         PASS
[host] APB0 paddr base=C0000   = 0x000c1000 (expect 0x000c1000)     PASS
[host] boot APB1_BASE      = 0x000d0000 (expect 0x000d0000)         PASS
[host] APB1 paddr base=D0000   = 0x000d1000 (expect 0x000d1000)     PASS
[host] APB0 paddr restored     = 0x00001000 (offset only, expect 0x00001000)  PASS
[host] boot APB base registers restored to 0 (fixed map)
```

验证覆盖：复位默认值、32 位全字写入回读、**地址线输出三种情形**（基地址为 0 时仅输出窗口内偏移 `0x00001000`；写入非零后输出 `base + 偏移`，如 `0x000C0000 + 0x1000 = 0x000C1000`；恢复默认 0 后回到偏移输出）。随后将寄存器写回 0 再释放 CPU 复位。

### 11.3 回归结果

| 检查项 | 结果 |
|---|---|
| APB0_BASE / APB1_BASE 默认值（0x00000000） | PASS |
| APB0_BASE 写 0x000C0000 / APB1_BASE 写 0x000D0000 回读 | PASS |
| APB0 paddr：base=0 → `0x00001000`；base=0xC0000 → `0x000C1000`；恢复 → `0x00001000` | PASS |
| APB1 paddr：base=0xD0000 → `0x000D1000` | PASS |
| 外置外设（GPIO/TIMER0/CTRL/TIMER1）经 SoC 外 APB 口读写 + 中断 | PASS |
| 恢复默认后 RT-Thread 8/8 任务 | PASS |
| `=== TEST RESULT: PASS (ctrl1=0x0000beef) ===` | PASS |
| 全程 CPU trap | 0 |

回归性能与阶段四一致（`total=9,340,403` ≈ 9,340,283、`irq_vec=3,530,240`、UART TX 974 字符），外置 + 寄存器化不影响互联仲裁与事务延迟（APB 读写仍为 3 拍）。仿真日志：`sim/sim_apb_ext.log`。

## 附录 A：固件完整运行日志

```
=== PicoRV32 SoC peripheral test ===
ctrl.version   = 0x00000001
  [PASS] ctrl0 rw
  [PASS] ctrl1 rw
  [PASS] ctrl2 rw
  [PASS] cpu trap clear
  [PASS] cpu running (reset released)
  gpio_in       = 0x00aa
  [PASS] gpio input (tb)
  [PASS] gpio output 0x5A5A
  [PASS] gpio output 0xA5A5
UART0 TX: Hello from PicoRV32 SoC! 0123456789 abcdef
UART1 TX: secondary serial port alive.
RXREADY
  uart0 rx byte = 0x41 'A'
  [PASS] uart0 rx
  [PASS] timer0 one-shot expired
  [PASS] timer0 irq
GPIOIRQ  [PASS] gpio irq
  i2c write rc   = 0
  [PASS] i2c0 write
  i2c read rc    = 0  data = aa bb cc 00
  [PASS] i2c0 read back
RESULT: PASS
=== TEST RESULT: PASS (ctrl1=0x0000beef) ===
```

## 附录 B：主机下载阶段日志

```
[host] fw.hex loaded: 1662 words (6648 bytes)
[host] downloading word 0/1662 ... 1536/1662
[host] downloaded 1662 words to RAM
[host] ram[0]  = 0x0600600b
[host] ram[1661] = 0x00000000
[host] cpu reset released (boot_ctrl=1)
```
