# BA-0.2 板级验收固件：有限 RTL 验证

日期：2026-09-29。基于提交 `d689416a33eb71dbd0d9058f2c6199857ea590c8`。
结论：**本页列出的 RTL 测试通过；综合网表/PDS/位流/上板 NOT_RUN，硬件 UNVERIFIED。**
未替换用户现有 PDS 工程的 ROM；未修改生产 CPU、桥、SoC、UART 或板级约束。

## 实际发现与修复

BA-0.1 二态测试通过不代表四态正确。在四态 RAM 故障测试中，首次陷阱前的
mcause/mepc/mtval 没有确定初始化值；失败打印读取这些 CSR，导致 TX 出现未知数据。
原记录 `board-rtl.jtNKjk5J/4state-ram.log` 明确报 `UART unknown data`。
检查生成 CPU 确认这些 CSR 由陷阱或 CSR 写更新，没有相应的复位赋值。

BA-0.2 启动增加三条 CSR 清零指令，不改变陷阱测试合同。大小由1956增加到1968字节，
data/bss仍为0。版本横幅更新，保留 UNVERIFIED（尚未硬件验收）。

另修正两个测试夹具问题：必须同时检查 PC 和有效退休，避免观察到冲刷的指令；
串口最后一个字节传完之前 CPU 可能已进入等待，因此记录入口次数，而不再错等一次性入口。
前者初次记录 `board-rtl.WktOT5iE`；后者 `board-rtl.I7cvQJqu` 触发夹具 watchdog。
这些失败不算通过，也不归因为生产 CPU 故障。
旧版四态正常长跑在发现 CSR 问题后主动停止，其不完整文本被检查器拒绝，不计为正常流程结果。

## 最终执行

固定输入输出目录：`board-rtl.m0fLKNrl`；编译目录：`board-acceptance.hp4LKtsu`。
入口：`bash firmware/board_acceptance/run_rtl.sh`，设置合法的 AXIL_CPU_BUILD、UART_FILE
及私有 TMPDIR；具体可复现用法和注入边界见[TESTING.md](../firmware/board_acceptance/TESTING.md)。
工具：Verilator 5.032、Icarus 12.0。整个最终脚本 exit 0，前后输入摘要逐字节一致。

|检查|实测结果|
|---|---|
|Verilator case 0 正常全流程|PASS，7269671 clocks，释放窗口不加速|
|case 1 RAM bit翻转|按预期 FAIL 10，诊断CSR全0，无假成功|
|case 2/9 软件/定时器IRQ丢失|按预期 FAIL 30/31|
|case 3/4/10 不按、按住不放、启动已按住|按预期 FAIL 41/42/40|
|case 5/6/8/13 UART帧、KEY1等待、同步异常处理、软件IRQ处理时复位|四例均重启并完成完整流程|
|case 7 UART一直busy|实际执行完整循环预算，32403101 clocks后静默失败，LED0=1，无UART成功文本|
|case 11 六次释放抖动后稳定|脉冲期间未提前进入按下阶段，随后完整通过|
|case 12 测试ROM将ECALL换成EBREAK|按预期 FAIL E0，mcause=3|
|七个文字预期变异|全部被拒绝，包括丢行、改版本、重复成功、改IRQ、删按键提示及错误复位计数|
|一次解码字节变异完整仿真|串口检查器拒绝，非只检查进程退出码|
|Icarus 正常流程，两个释放窗口加速|PASS，1874146 clocks；UART文本与二态正常结果逐字节相同|
|Icarus RAM故障|PASS（成功检测故障），507655 clocks，确定的 FAIL 10 / 三个诊断CSR全0|
|Icarus 撤销三个初始化指令的ROM反例|明确被 UART unknown data 拒绝，复现修复前的问题|

原版 mini_uart 有五处32位计数表达式赋给16位计数器的 WIDTHTRUNC 提示，日志保留。
本测试固定27MHz/115200，对应DIV=234，落在16位范围内；未修改第三方文件，
也不据此证明任意参数组合安全。Icarus编译记录无报错。

## 固定摘要

|文件/结果|SHA256|
|---|---|
|start.S|a8ae477433621438902285782b1273913a9e045215fa5068e09307351aafdc44|
|run_rtl.sh|d5d45832a53e95338f018e1e9c7babecd4f6d5a4e6bb6ff579534dfbb697fde7|
|acceptance_tb.sv|b9531d30698d3db76095d0a7b8cb5b618588d04b4b54bc804fb38c957a95d531|
|check_uart.py|2713933848097cde54cc07cdd5ab191e013f695a2649eb687f3ecc8a41b414a4|
|negative_rom.py|105a8447deff574089d7271396947c04eea6b4e4065c0d2fdc173dbac4e738af|
|生产CPU|d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25|
|寄存器堆初始bin|b8b891b81fd1c062082faf97533834198d8a4c4b6867899d6218712132a8ed38|
|mini_uart.v|12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e|
|firmware.hex|041e0b07c23a447238e1950d3708d7d59dc7512efee1bd6c3a2ad48cbc6d8fa1|
|二态正常和四态加速正常UART文本（含复位分隔标记）|2899dcdfebabf5468af3ad7127d1de7d3fd4c33911dcea31fcad595efe17f15d|
|四态RAM失败UART文本|4a1a44fdf509a39e4db01a354cf2d7acf575c225f66e10add8ef6ffa423e8c81|
|撤销初始化的测试ROM，禁止用于上板|20998b5981ece896c513fa820c751e8f4e4277a57ae97a9e5bd33c1f157e3db8|

## 不扩大的结论与下一步

- UART从顶层TX解码，非直接读取软件写数据；但没有实物串口电气验证。
- 30秒超时场景通过推进外设tick触发，不是实际等待30秒。
- 四态正常场景的两段100ms释放等待同样推进tick；原速释放时序由二态正常场景覆盖。
- 四态只测正常、RAM失败与初始化反例，不声称十四场景全部四态通过。
- 不覆盖全部复位相位、任意中断竞争、全部RAM故障、计时器回绕边界或所有抖动组合。
- 本轮不重跑旧八套CPU矩阵，也不把旧综合网表/PDS结果套用于BA-0.2。
- 下一步应以本固件SHA为候选重跑综合网表与PDS时序，完成板级前置核对和两名非作者评审，
  再由人工监管进行UART、KEY0/KEY1和冷启动验收。不得自动下载或接入执行器。
