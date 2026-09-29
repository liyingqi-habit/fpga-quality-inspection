# 板级验收固件 BA-0.2（上板 UNVERIFIED）

状态：**已进行有限 RTL 验证，仍非可直接下载的已验收版本。**
用户已恢复离线仿真；网表/PDS重建/位流/上板仍 NOT_RUN。
仅匹配RC1 CPU和 `validation/axil/soc.sv`，不是通用SDK、操作系统或完整ISA测试。

BA-0.1 的历史编译记录见[草案证据](../../evidence/board-acceptance-draft-20260929.md)。
BA-0.2 的验证方式见[测试入口与边界](TESTING.md)，实际结果见[RTL证据](../../evidence/board-acceptance-rtl-20260929.md)。
本版修复了首次陷阱前失败提示可能读取未初始化诊断 CSR 的问题，启动时显式清零 mepc/mcause/mtval。

## 不覆盖旧工程

源文件 `start.S`；`build.sh`每次建立独立输出目录，生成ELF、反汇编、map、binary、4096行firmware.hex与SHA256记录。不修改任何PDS工程/原firmware.hex，不自动仿真、下载、接线或启停电机。不要手动把新hex替换进已验收的RC1回归包后继续沿用旧报告。

Linux/WSL已有RISC-V GCC、binutils、Python 3时，在仓库根目录运行：

```bash
bash firmware/board_acceptance/build.sh
```

可设TMPDIR为本地私有输出目录。入口复用 `validation/cpu/sw/link.ld`、`validation/cpu/scripts/bin_to_hex.py`，需要保留仓库相对布局。生成结果仅代表编译，不能冒充运行证据。

## 软件约定

|项目|固定约定|
|---|---|
|CPU|RC1，SHA256 d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25；RV32IM+Zicsr，无压缩指令|
|复位/异常|复位0x80000000；0x80000080保留陷阱入口；启动将mtvec设置到对齐的直接模式入口|
|时钟/串口|27 MHz；mini_uart默认115200，8N1，无流控；本测试仅验证TX，不验证RX|
|ROM/RAM|ROM 0x80000000..0x80003FFF；RAM 0x80004000..0x80007FFF|
|UART|0x10000000 TX；0x10000004 bit0为tx_busy|
|GPIO/tick|0x10000010 bit0接LED0；0x10000020为32位时钟计数|
|IRQ寄存器|0x10000030软件pending；0x10000034 timer compare；KEY1低有效外部中断|

使用纯汇编、无栈、无.data/.bss状态。保留t3/t4专供陷阱处理，s7为捕获次数，s8预期cause，s9预期同步异常PC，s10恢复PC，s11预期mtval。处理器不嵌套；不调用C函数；未来修改必须保留这个寄存器合同。正常陷阱不得调用打印函数。UART函数额外使用a5，puts/hex32分别用s6/s5保存返回地址。

## 自检流程与覆盖边界

1. 禁止全局/各源中断，清诊断CSR及软件pending，将timer compare置最大，输出版本和UNVERIFIED标记。
2. **破坏性RAM自检**：全部4096字，四遍写入“字地址 XOR {0,FFFFFFFF,55555555,AAAAAAAA}”，每遍全部写完再逐字读取比较。无栈/全局RAM数据被覆盖。不是完整March测试，不覆盖每一类RAM故障或子字操作。
3. ECALL、非法零指令、EBREAK：逐项核对mcause、精确mepc、mtval=0、一次捕获、MIE入陷阱后为0；通过指定恢复PC返回。此固件不覆盖全部同步异常、嵌套或故障竞争。
4. 软件IRQ、定时器IRQ分别测试：仅开当前源，核对cause/mtval并屏蔽来源，清软件pending、禁用timer，再mret；主程序核对捕获一次与MIE恢复。timer设置为当前tick+270000（约10ms），跨计数回绕时明确失败，不擅自当成有效deadline。
5. KEY1人工IRQ：先提示释放，要求MEIP连续低100ms，再提示按下一次；IRQ捕获后屏蔽MEIE，再要求释放稳定100ms。每段等待有30秒tick超时和独立循环次数上限。外部中断为电平请求，一次捕获不证明硬件边沿检测或按下去抖；释放检测是软件轮询的稳定窗口，不保证捕获每个亚采样毛刺。
6. 完成输出SELFTEST PASS和人工复位提示；LED0心跳，软件不自动重启。按KEY0或冷启动后的重复验收由人记录。

超时依赖CPU和总线继续执行；若总线永久卡住，软件无法替代硬件看门狗。UART轮询也有次数上限，但挂死的MMIO本身无法被软件超时解救。timer关闭采用屏蔽mie，最大compare不能阻止tick到FFFFFFFF时外设pending短暂出现；测试结束全局中断仍关闭。

## 以后上板时的操作单（本轮不执行）

前置：[板级准入](../../docs/board/CPU_RC1_BOARD_AUDIT.md)未满足前不得下载。确认供电/版本/SCBV、KEY0与专用配置RESET区别、引脚；断开电机/执行器。审阅本固件 RTL 与负向测试记录，完成剩余验证、重跑同固件综合网表/PDS，再生成版本化上板包，不能直接使用旧结果。

1. 串口工具选择人工核实的端口，115200 / 8数据位 / 无校验 / 1停止位 / 无流控，关闭HEX显示，打开文本日志保存。不固定假设COM7。
2. 两名非作者审核并有人监管下载后，保持KEY1释放，查看BA-0.2启动横幅及自动项目结果。
3. 看到 `WAIT PRESS KEY1 ONCE` 后30秒内轻按并释放KEY1。按住不放会在释放阶段失败；不要按专用配置RESET替代KEY1。
4. 必须看到下方全部结果，记录版本、固件SHA256、实际串口日志和按键操作。LED不能单独判PASS。
5. 按KEY0进行CPU复位，重新完成整套；再按厂家供电流程断电/上电，重新完成。首次、KEY0复位、冷启动各保存一份日志。固件不保存断电计数，不能由一条横幅证明已做三轮。
6. 任何FAIL/无输出/乱码，先停止验收、保留日志，不反复盲目下载。无输出可能是供电、配置、时钟、复位、端口或UART问题，不仅是CPU错误。

下面是**预期文本，不是实跑记录**：

```text
CPU BOARD ACCEPTANCE BA-0.2 UNVERIFIED
CPU=RC1-d0e23f3c CLK=27000000 UART=115200-8N1
BOOT RAM-DESTRUCTIVE NO-ACTUATORS
PASS RAM 0x80004000..0x80007FFF 4 address-XOR passes
PASS EXCEPTIONS ECALL ILLEGAL EBREAK
PASS IRQ SOFTWARE
PASS IRQ TIMER
WAIT RELEASE KEY1 (30s timeout, 100ms stable)
WAIT PRESS KEY1 ONCE (30s timeout)
WAIT RELEASE KEY1 (30s timeout, 100ms stable)
PASS IRQ EXTERNAL PRESS/RELEASE
SELFTEST PASS (limited tests only)
MANUAL: KEY0 reset -> repeat entire test; then cold power cycle -> repeat.
```

## 失败码

|code|含义|
|---|---|
|10|RAM读回不一致|
|20/21/22|ECALL/非法指令/EBREAK未捕获一次|
|30/31|软件/定时器IRQ超时、计数或返回MIE不符|
|32|timer deadline跨tick回绕，未实施本次timer测试|
|40|开始前KEY1未稳定释放|
|41|KEY1 IRQ未在等待窗口内完成或返回状态错误|
|42|IRQ之后KEY1未稳定释放|
|E0|非预期陷阱、重复陷阱或cause/PC/mtval/MIE错误|

FAIL行附mcause/mepc/mtval；非陷阱失败时这些CSR可能是上一次陷阱的值，不代表当前失败地址。UART忙超限走静默失败，LED0常亮，不保证还能打印FAIL。任何常亮/不亮都不能独立判断故障原因。

已新增正常流程、独立UART解码、RAM故障、IRQ丢失/错误cause、KEY1等待/长按/有限抖动、四种复位位置、UART持续busy的RTL测试。覆盖范围及实际状态见RTL证据；不等于穷尽所有边界。
后续：同固件综合网表与时序、板级条件核对和人工实物验收，仍 **NOT_RUN/待确认**。
