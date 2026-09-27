# CSR 三项修复与新 CPU 回归

日期2026-09-27，T06，基于 `af5912e`。用户授权修复[此前三个FAIL](axil-csr-boundary-20260927.md)。旧失败保留，不改为PASS；本页是新版本实跑结果，未上板。

## 实际修复

`patch_csr.py` 只作用于固定上游提交 `7445c66bb4bb508f096c1d4814b4fae1ea8643c0` 的隔离副本，每个上下文必须恰好匹配一次才写文件。

1. 只读映射只有在“读且不写”时允许访问；对架构只读地址再按原始CSR写译码拒绝写入，禁用该指令CSR读写副作用并产生非法指令异常。x0/立即数0的合法只读形式保留。
2. mepc 显式写入和读回按静态指令对齐配置掩码。本配置无C，低两位为0。
3. mret 的MPP复位值选择已实现的最低特权模式；本配置仅M，返回后MPP=3，保留原MIE/MPIE恢复逻辑。

补丁保留原mtval修复。没有修改ISA预期、总线协议、SoC、引脚或UART。依据仍为旧失败页引用的RISC-V Zicsr与Machine-Level规范。代码支持的其他配置分支不等于已测，本轮只验证固定RV32IM机器模式。

新CPU SHA256：`d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25`。
新综合网表SHA256：`4cf1fb1932d73a55b954a5929049d9adeda5f6bda85402c11273f23d68eae46d`。
固件仍为199结果基线，SHA256：`773e5cbb012284d43806645e83d90c6e879e85d6ea70ee806b855775839791b1`（仅指PDS基线固件，不是CSR固件）。脚本锁定新哈希，更新后的优先级注入定位也经过实际RTL审计，不能静默接受未知生成物。

## 实跑回归

|检查|结果|本地运行标识|
|---|---|---|
|CSR固定预期|195用例各2启动，390次全部PASS，3120记录、零不匹配；17检查器负向自测PASS|axil-csr.mIAuQAss|
|实际RTL撤销只读保护|512个预期字段不匹配，被指定cause/PC/rd/次数原因拒绝|上述negative/readonly|
|实际RTL撤销mepc掩码|12个读回错误被拒绝|上述negative/align|
|实际RTL撤销MPP修复|168个返回MPP错误被拒绝|上述negative/mpp|
|SoC基线|199结果×2启动、9类同步异常、三类基础中断与预期突变PASS|axil-soc.kZXzSrMm|
|中断优先级|144次处理PASS；14轨迹突变、实际优先级反转被拒绝|axil-irq.AgLBXJ3T|
|真实CPU在途取消|84场景、36轨迹负向、6个RTL故障对照PASS|axil-cancel.SCf12A7p|
|新综合网表|RTL/gate/碰撞原始读值X注入三者199结果逐条相同，各2启动；错误预期被拒绝|axil-netlist.JR7UfaWA|

门级及X注入版本每次启动观察到寄存器堆两端口同地址读写碰撞200/45次。审计了新网表bvalid提交探针、地址/数据与寄存器堆原语连接后才更新哈希。不是仅通过编译，也没有修改网表规避X。

**范围区分**：CSR195用例、优先级、取消是实际CPU RTL测试；本轮PDS/综合网表运行的是199结果基线固件，不能冒充195用例也跑了门级。未做SDF或板卡测试。

## PDS 实跑

PDS2025.2，PG2L200H-6/FBB676，原候选FDC，完整compile/synthesize/dev_map/pnr/report_timing成功。新临时工程标识 `pds_axil_c8ed83f3438f46e7af67f5433ce958f5`，原生项目和原始报告仅本地保存。

37.037ns（27MHz）约束：slow setup slack=27.178ns，slow hold=0.063ns；fast setup=30.676ns，fast hold=0.043ns。两角setup/hold/recovery/removal/mpw均零失败端点、总负裕量0；报告检查器四项负向自测通过。

资源：5013 LUT、1506寄存器、0锁存器、5 DRM36K等效、4 APM。仍有 no_input_delay=3、io_min_max_delay_consistency=4，候选引脚未获实物确认、异步输入例外和零输出延迟限制不变。结论为 `CONSTRAINED_PATHS_PASS_WITH_PROFILE_LIMITATIONS`；工具推导频率不是实物Fmax，板级状态仍NOT_VALIDATED。

## 过程失败与复现

首个本地候选 `axil-cpu-v4` 用被强制关闭的writeInstruction作为关闭条件，引入组合反馈，Spinal生成检查拒绝。改用原始CSR_WRITE_OPCODE后，在新目录 `axil-cpu-v5` 从上游重新生成并通过；失败目录保留，未用于后续回归或PDS。最终生成工具Java17、sbt1.10.7、Spinal1.13.0；仿真Icarus12、RISC-V GCC14.2。

按AXIL README在新目录执行generate.sh，随后运行run_csr.sh、run_soc.sh、run_irq.sh、run_cancel.sh；PDS使用新SoC输出，之后运行check_pds.py --self-test及run_netlist.sh。所有第三方源码、生成RTL、网表、固件及私有输入留本地，不上传公开仓库。

未覆盖完整特权/CSR架构、S/U/C配置、嵌套、计数器溢出、全部WARL值或硬件。R07仍PARTIAL。下一项可补IRQ/异常竞争或嵌套测试；板级验证须先人工确认板型/引脚/供电。两名非作者审核后由所有者手动合并，未代审/自动合并。
