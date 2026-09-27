# 赛题逐项对照表

核对日期：2026-09-27。用途：评审与规划，不是主办方合规证明或完成证书。

## 依据与状态口径

依据用户提供的《全国大学生嵌入式芯片与系统设计竞赛2026 FPGA赛道选题指南-紫光同创》，实际PDF第10—11页、印刷第8—9页，选题一CPU相关条目。原PDF仅本地保存，不公开复制。

原文件SHA256：`d4d7d389e22f88ac0d362072fc0c73711959816d374168692e102d25453d2ce6`。未取得更新的正式通知，不宣称这是最新最终规则。2026-10-30是团队目标日期，不是已核实官方截止。

- PARTIAL：已有局部实跑证据，不代表整项完成。
- NOT_RUN：对应完整验收尚未执行。
- BLOCKED：缺少输入、硬件确认或正式答复。
- INFRA_PASS：验证设施自身通过，不能改记CPU或整机PASS。
- DRAFT：技术决策待评审；与测试状态分开记录。

以下证据索引： [E1 CPU先导实跑摘要](../../evidence/cpu-validation-20260927.md)、[E2 写响应设施实跑](../../evidence/write-response-20260927.md)、[E3 真实LSU实验](../../evidence/real-lsu-20260927.md)、[A1 写完成源码审计](../interfaces/CPU_WR_01_AUDIT.md)、[D1 访存合同草案](../interfaces/CPU_BUS_CONTRACT_DRAFT.md)。E1是已有本地日志的公开摘要，非本轮全部重跑。

补充证据：[E4 真实LSU最小SoC迁移与读写回归](../../evidence/lsu-soc-20260927.md)。E4为R01/R02/R03/R07增加局部证据：正常读、所有字节/半字通道、三处错误路径冲刷、六类访存异常，以及迁移后的UART/GPIO/计时与复位回归。上述项目仍为PARTIAL；不代表完整ISA、中断、DDR或完整工作站完成，也不覆盖迁移版PDS及实物验收。

## 要求、代码与缺口

CPU-WR-05补充：[E5 在途复位/混合指令](../../evidence/lsu-extended-20260927.md)、[E6 迁移版PDS](../../evidence/lsu-pds-20260927.md)。E5增加24个本地全局复位窗口、独立参考模型混合指令两轮×三档延迟；E6完成综合/PnR，旧候选约束下27MHz时序通过。R01/R02/R03/R07/R11仍PARTIAL：不把局部RTL验证、异步路径例外、工具估算Fmax当作完整ISA、中断、板级时序或CoreMark验收。

|编号 / 原文层级|要求概括|目前代码或证据 / 状态|下一步验收与任务|
|---|---|---|---|
|R01 基础|支持RV32I的通用处理单元|[定向程序](../../validation/cpu/sw/cpu_directed.S)、E1：PARTIAL；27项不是完整RV32I覆盖，真实CPU RTL尚属外部输入|T06：建立指令覆盖清单与独立预期，覆盖分支、访存、边界和非法情况；保留失败反例|
|R02 基础|不少于3级流水，正确处理数据冲突与分支|[冒险程序](../../validation/cpu/sw/hazard_test.S)、E1：PARTIAL；候选为VexRiscv派生方案，不以名称代替结构证据|T06：固定生成配置/RTL，核对级数并测旁路、停顿、冲刷、错误路径副作用|
|R03 基础|UART、GPIO等基础外设用于控制和输出|[UART测试台](../../validation/cpu/tb/mini_uart_tb.sv)、[最小SoC测试台](../../validation/cpu/tb/mini_soc_tb.sv)、E1：PARTIAL|T02/T06：核实板级引脚电平，人工监管上板验证串口和GPIO，不把仿真按键等同实物通过|
|R04 实现方式/平台|Verilog/SystemVerilog；推荐开发板或紫光同创FPGA平台|SV测试代码、PDS综合摘要E1：PARTIAL；盘古200K MINI完整硬件身份及匹配工程仍待确认|T01/T02：确认板卡/核心板版本、合法工程及约束；生成RTL参赛方式另行正式澄清|
|R05 高阶|两路组相联指令Cache和数据Cache，优化突发访问|当前公开测试包无对应完整实现证据：NOT_RUN|T06：分别验证I/D Cache结构、命中/缺失/替换、写策略、突发及错误复位；不得把无Cache先导当完成|
|R06 高阶|动态分支预测（如BTB）|无专门预测效果、恢复与结构验收：NOT_RUN|T06：固定配置，测预测命中/失误恢复和副作用；BTB是原文举例，不将例子擅自升级为唯一实现|
|R07 高阶|完整RISC-V异常/中断机制|[异常程序](../../validation/cpu/sw/cpu_traps.S)、E1：PARTIAL；原工程写异常缺口见A1，E3补充独立无Cache配置的写错误/复位验证；中断完整验收NOT_RUN|T06：将实验接入完整系统后回归CSR/返回、异常优先级及中断；E2仅INFRA_PASS，E3不使整项完成|
|R08 高阶应用|基于所设计CPU构建边缘AI加速，移植YOLO或轻量模型，结合传感/显示完成应用|传送带质检是团队方案，完整设备内AI未验收：NOT_RUN|T03/T07—T10/T13：真实图像、模型、整数参考与硬件加速一致，CPU调度及整图运行证据；PC代算不得冒充设备执行|
|R09 测评环境|列明riscv32-unknown-elf-gcc、CoreMark v1.0|先导实跑使用riscv64-unknown-elf-gcc 14.2.0；尚无正式CoreMark结果：PARTIAL/NOT_RUN|T15：核实RV32目标编译参数和产物；与原文工具链名称差异须记录并澄清，不凭工具前缀断言一致|
|R10 性能测量|CoreMark运行不少于10秒，评估CoreMark/MHz|无合规计时、迭代与校验报告：NOT_RUN|T15：固定CoreMark版本、参数、CPU频率和计时方法，原始日志证明时长至少10秒及结果正确|
|R11 性能测量|满足时钟约束的最高频率、CoreMark/LUT资源效率|E1仅先导综合资源；无最终频率/性能比：PARTIAL|T15：同受测构建的布局布线时序、约束、资源及CoreMark计算；综合网表无SDF仿真不证明时序闭合|
|R12 应用评价|整体资源、时序、主频、AI延迟与识别效果|整机未运行：NOT_RUN|T10/T14：冻结输入数据和构建，保留测量分母、延迟定义、识别统计及原始记录|
|R13 技术文档|模块化、合理约束、完整注释；用ILA波形分析CoreMark关键算法流水效率|当前测试源码与证据文档为PARTIAL；CoreMark ILA证据NOT_RUN|T15：固定代码/配置/约束和报告版本，实际采集并分析，不使用示意波形冒充ILA实测|

## 自选方案不是赛题硬指标

五级、RV32IM中的M扩展、VexRiscv、YOLOv5n具体版本/输入尺寸/量化方式、传送带和托盘机构是团队技术选择。原文基础门槛是RV32I和至少三级；高阶条目保持高阶层级。写响应设施是保证系统正确性的工程措施，不是单独竞赛评分项。不移用其他选题的95%或1080p要求。

## 必须正式确认的问题

1. 完整CPU复用、派生改造、生成RTL及自主工作量是否被认可？未获答复前，VexRiscv路线保持候选，先导测试可以保留，但不能宣称参赛合规已批准。
2. 当前工具链替代方式、最终提交格式、规则版本和截止时间。
3. 应用与CoreMark是否要求同一bitstream：本地任务资料提出待核实问题，不能写成上述两页已明确规定。
4. 第三方CPU/IP/模型/资料的再分发许可逐项检查；公开仓库不自动获得授权。

由所有者通过正式渠道询问，答复记录来源、日期、适用版本、原问题和影响任务。本文件不代发询问。

## 更新方法

每次状态升级必须提供受测commit、输入版本/哈希、命令、实际输出、未覆盖项；没有证据仍NOT_RUN。T06相关任务见 [#6](https://github.com/liyingqi-habit/fpga-quality-inspection/issues/6) 与 [#20](https://github.com/liyingqi-habit/fpga-quality-inspection/issues/20)。完整T01—T15/G0—G7地图在待合并的 [PR #24](https://github.com/liyingqi-habit/fpga-quality-inspection/pull/24)，不能假设本分支已有全部基础工具。
