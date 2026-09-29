# 同时挂起中断优先级：实际 RTL 验证

日期：2026-09-27。任务 T06，基于提交 `898f0f3`，本次仅新增验证夹具和说明，未改生产 CPU、AXIL 桥、SoC 或约束。

## 预期与输入

[RISC-V Machine-Level ISA](https://docs.riscv.org/reference/isa/priv/machine.html) 定义本配置机器模式中断优先级 MEI > MSI > MTI；无 AIA 覆盖。本测试用独立 Python 规则生成预期，不从 DUT 仲裁信号生成答案。

CPU RTL SHA256：`6bc91de7f76e88d7edf056e8d30790c645876bf13e7177e7827c949ff12d141e`。UART SHA256：`12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e`。固定上游和生成方法见 AXIL README；合法第三方输入及生成 RTL 不随本次上传。

工具：WSL Ubuntu、Icarus 12、RISC-V GCC 14.2、Python 3。复现：设置 AXIL_CPU_BUILD、CPU_INPUT_ROOT 后运行 `bash validation/axil/run_irq.sh`。

## 实跑范围与结果

- 外部+软件、外部+定时器、软件+定时器、三源共四组；各组包括全使能与先屏蔽最高来源两种，再交叉两种 mie/mstatus.MIE 使能顺序：16种组合。
- 固件先在屏蔽状态通过真实 MMIO 和测试台 key 输入挂起请求，等待 mip 确认；再允许仲裁。这里验证“仲裁前同时 pending”，不是断言请求在同沿产生。
- 外部 key 断言/撤销附加延迟0或9周期，各跑两次全局复位启动，共64次场景执行、144次中断处理、1840条记录，全部 PASS。
- 记录实际 mcause、mip、mie、mstatus、mtval、mepc；处理程序按实际 cause 只清当前来源，检查其他 pending 保留、屏蔽来源延后处理、mret 恢复 MIE。最终有限40次循环内不得重复处理。
- 14次轨迹突变分别破坏 cause、剩余 pending、trap 状态、mtval、返回 MIE、重复计数和 mepc，均由指定原因拒绝。
- 在本地生成 RTL 副本真实反转三源优先级，重新编译运行相同固件；检查器必须以 `VALUE:mcause` 拒绝，已通过。不是仅修改期望文件。

最终本地运行标识 `axil-irq.m72ndFBH`，包含 run.log、audit.json、两个 delay 目录的 irq.csv、负向轨迹、反汇编、符号表及 inputs.sha256。实际初轮曾因测试固件把 x28 同时用作日志指针和 t3 导致异常；改为 s11 后重跑通过，没有改 CPU 来迎合测试。

既有 SoC 的199个独立结果、9类同步异常和三源基础中断另外重跑，运行标识 `axil-soc.cri5SgGd`；不将这部分计入新增144次处理。

## 限制与交接

mepc 只检查四字节对齐及编译符号定义的使能/等待/返回窗口，不证明全部停顿时精确中断 PC。非嵌套处理中断；未测嵌套、IRQ与同步异常竞争、短脉冲/再次挂起、其他特权级、全部CSR边界或长时间随机压力。

使用自定义软件/定时器寄存器和同步 key，不是 CLINT/PLIC 验证。未运行本固件的 PDS/综合网表/SDF，也未上板、产生下载文件或操作执行器。既有 PDS 时序结论不自动扩展为本固件验证。R07 保持 PARTIAL。

交付审阅重点：独立预期顺序、源清除逻辑、屏蔽期间不丢请求、负向拒绝原因。后续可补 CSR WARL/只读边界，再选择嵌套与异常竞争覆盖；两名非作者审核，所有者手动合并。
