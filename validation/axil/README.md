# 单在途 AXI4-Lite / RV32IM 机器模式离线基线

这是经所有者批准的 CPU 离线集成范围，不是完整比赛 CPU、DDR/DMA 系统或可直接下载的板级工程。源生成配置、桥、SoC、测试和独立预期公开；厂家库、原资料及生成 CPU/网表留本地合法输入目录。接口见 [CPU_AXIL_BASELINE](../../docs/interfaces/CPU_AXIL_BASELINE.md)，结果见 [实跑证据](../../evidence/axil-baseline-20260927.md)。

## 可直接运行的桥测试

Linux/WSL，Bash、Icarus Verilog 12、sha256sum：

```bash
bash validation/axil/run_bridge.sh
```

576 个组合：读/写 × 4 种 RESP × 3 档延迟 × 6 个正常/取消窗口 × 4 种 WSTRB；另有两种永不响应隔离，以及错误丢失、旧响应泄漏、读背压丢失三种实际 RTL 故障注入，必须因预期原因失败。驱动是测试替身，不是真 CPU。验证独立 AW/W、AR/R、响应背压、载荷保持、复位沿取消优先及排空后复用。无响应观察 40 周期，不声称无限时间形式证明。

## 生成实际 CPU 并跑 SoC

所需合法输入：VexRiscv 上游提交 `7445c66bb4bb508f096c1d4814b4fae1ea8643c0`，Java 17、sbt launcher 与本地仓库配置，以及此前核验的 mini_uart.v。RISC-V GCC 14.2 / objcopy / objdump、Python 3、Icarus。下列变量须指向本人实际目录，不复制他人的机器路径：

```bash
export VEX_SOURCE=/your/legal/VexRiscv
export SBT_LAUNCH=/your/tools/sbt-launch.jar
export SBT_REPOSITORIES=/your/tools/sbt-repositories
export REAL_LSU_BUILD=/your/unused/axil-cpu-build
bash validation/axil/generate.sh
export AXIL_CPU_BUILD="$REAL_LSU_BUILD"
export CPU_INPUT_ROOT=/your/legal/mini-inputs
bash validation/axil/run_soc.sh
```

生成器复制固定 git 快照，只修改副本；沿用已审计 LSU 写响应补丁，另加有上下文计数保护的 CSR mtval 修补。禁止改原上游目录。记录生成日志/哈希；不能对换了版本的输入盲目删哈希检查。

配置：五级候选、无 Cache/无预测、RV32IM+Zicsr、机器模式；SYNC 寄存器堆、乘除法、非法指令/访存/跳转异常、三种中断。`misa` I/M 位明确为 0x1100。不实现 S/U 模式、CLINT、PLIC 或权限隔离。

## 离线地址图（不是最终 ABI）

|范围/地址|行为|
|---|---|
|0x80000000—0x80003fff|16 KiB ROM，取指和数据读；越界取指报错|
|0x80004000—0x80007fff|16 KiB RAM，按 WSTRB 写；未初始化内容不可依赖|
|0x10000000 / 04|UART 数据 / 状态；写数据等待 TX 空闲|
|0x10000010|低 8 位 GPIO；离线固件用作事件标记|
|0x10000020|只读周期 tick|
|0x10000030|软件中断 pending bit0|
|0x10000034|timer compare；ticks >= compare 产生中断|
|key 低有效|同步后作为外部中断；不是去抖按键测试|
|其他数据地址|DECERR；实验 CPU 转为精确访问异常|

综合 SoC 局部 CPU 取消输入仍固定 0；全局复位同时清桥/目标。新增专用真实CPU+新AXIL桥的局部取消集成测试，见下节；它不改变物理复位方案，也不把旧 write_bridge 的证据混入新接口。

## 真实 CPU 的在途取消

设置上面的 AXIL_CPU_BUILD 后执行 `bash validation/axil/run_cancel.sh`。不需要UART输入或PDS。84个读写/响应码/延迟/取消窗口，独立目标不会随CPU局部复位清空；Python从握手、真实退休和程序输出核对排空与重启。36个轨迹负向和6个实际RTL故障变体必须被指定原因拒绝。原始轨迹、固件反汇编、audit.json及输入哈希保存在脚本打印目录。

详细范围及实际失败修复见 [CPU-AXIL-03证据](../../evidence/axil-cancel-20260927.md)。测试ROM在复位时切换到不同地址/数据的重启夹具；这不是板卡自动切换软件的功能。仅LW/SW，未覆盖子字取消、重复复位或所有周期；综合SoC仍未启用局部cancel。

## 指令与机器模式覆盖清单

`program.py` 的 Python 整数模型独立产生 199 个结果，RTL 不能自己给自己生成预期；固件写结果由 testbench 顺序检查。每次生成 coverage.json 和反汇编；同一固件启动两遍，期望突变必须在第 4 项失败。

|组|已执行的定向范围|
|---|---|
|整数寄存器|ADD SUB SLL SLT SLTU XOR SRL SRA OR AND，各 6 对零/符号/极值等操作数|
|立即数|ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI，各 6 项；移位 31|
|地址/跳转|LUI AUIPC JAL JALR；BEQ BNE BLT BGE BLTU BGEU 各 3 对，含 taken/not-taken|
|存储|LW LB LBU LH LHU；SW SB SH 合并；FENCE 后读、x0 写忽略|
|M 扩展|MUL MULH MULHSU MULHU DIV DIVU REM REMU；含除零及 signed overflow|
|CSR|CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI、mscratch、mcycle 增长|
|同步异常|cause 0/1/2/3/4/5/6/7/11，核对 mcause/mepc/mtval，设置恢复 PC 后 mret|
|中断|software/timer/external 分别设置 pending；mie 和全局 MIE 屏蔽，再启用；检查 cause、mtval=0、trap 时 MIE/MPIE 和返回 MIE|

不是 riscv-arch-test 认证或完整 ISA/特权符合性证明。NOT_RUN：所有寄存器/立即数穷举、嵌套中断、全部 CSR WARL/只读错误、计数器溢出、WFI/FENCE.I、真实外设协议、随机长跑、SDF、上板。FENCE 定向顺序测试不证明多主机内存模型；该单槽 SoC 也没有多主机。

## 同时 pending 的中断优先级

设置上述 AXIL_CPU_BUILD、CPU_INPUT_ROOT，执行 `bash validation/axil/run_irq.sh`。真实 CPU 和未修改的 SoC 运行生成固件；四种双/三源组合 × 是否先屏蔽最高来源 × 两种使能顺序，共16种。两档外部输入延迟各启动两次，总计144次中断处理、1840条记录。独立预期检查 MEI > MSI > MTI、只清当前来源、被屏蔽请求保留及 mret 恢复 MIE；14次轨迹突变和一次实际 RTL 优先级反转必须被指定原因拒绝。

原始轨迹、固件/反汇编、audit.json 和哈希留在脚本打印的本地目录。详见 [证据与限制](../../evidence/axil-irq-priority-20260927.md)。这是仲裁前同时处于 pending，不是同一时钟沿产生三种请求；不覆盖嵌套或全部中断竞争。

## PDS 和综合网表

`run_pds.ps1` 接收 PdsShell、AxilCpuBuild、CpuInputRoot、SocRun、ReferenceProject；复制隔离 ASCII 临时目录，保留输入哈希、原生 .pds 和报告。仅综合/dev_map/pnr/report_timing；不产 bitstream、不下载。ReferenceProject 仅提供 hash 固定的旧候选 FDC。

```powershell
./validation/axil/run_pds.ps1 -PdsShell <pds_shell.exe> -AxilCpuBuild <生成目录> -CpuInputRoot <合法输入> -SocRun <run_soc输出> -ReferenceProject <旧候选工程>
```

检查报告用 `python3 -B validation/lsu_soc/check_pds.py <PDS输出> --self-test`。网表功能回归设置 PDS_STAGE、PDS_SIM_LIB 后执行 `bash validation/axil/run_netlist.sh`。综合网表探针依赖已核验的特定网表，哈希变化先审计，不自动接受。当前 PDS/网表实际结果见 [同版本离线验收](../../evidence/axil-pds-20260927.md)，不是由脚本存在推定 PASS。
