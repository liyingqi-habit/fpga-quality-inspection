# 传送带智能质检工作站

基于盘古 200K MINI，目标是完成设备内 AI 检查、独立托盘及停车式传送分流的完整工作站。

当前处于协作基础建设阶段，尚无团队验收的硬件版本。
后续内容通过任务分支和 PR（审核后合入主线的申请单）提交；两名非作者审核后，由项目所有者手动合并。

## 当前任务分支入口

- [CPU RC1固定候选统一回归](evidence/axil-candidate-rc1-20260927.md)：八套RTL、新综合网表与PDS已约束路径通过；[板级准入清单](docs/board/CPU_RC1_BOARD_AUDIT.md)仍有阻塞，不是可直接下载验收的版本。
- [赛题逐项对照表](docs/competition/REQUIREMENTS_MATRIX.md)：要求、已有证据、未完成项和验收方式。
- [队员上手指南](docs/team/GETTING_STARTED.md)：看代码、评审、修改和运行测试。
- [CPU 离线测试](validation/cpu/README.md)：需要合法外部输入，不是完整可上板工程。
- [独立写响应测试](validation/write_response/README.md)：可独立运行，但合成驱动不是CPU。
- [真实 LSU 写响应实验](validation/real_lsu/README.md)：固定源码生成实验CPU，真实退休/异常/复位检查；不是完整SoC或上板验收。
- [读写验证与最小 SoC 迁移](validation/lsu_soc/README.md)：正常读、SB/SH、分支冲刷、在途复位、混合指令及离线PDS结果；板级约束仍待确认，未上板验收。
- [迁移版综合网表回归](evidence/lsu-netlist-20260927.md)：同固件RTL对照、实际寄存器堆冲突计数、原始读值X注入；无SDF，不是完整硬件验收。
- [可扩展寄存器堆矩阵](evidence/regfile-matrix-20260927.md)：432组基础＋48组停顿/冲刷叠加，独立固件与对应综合网表对照；不是穷尽验证。
- [外部写总线背压与分支交叉](validation/bus_flush/README.md)：真实CPU＋实验写桥，432种时序配置；RTL验证，不是完整AXI/DDR或上板结果。
- [AXI4-Lite 与机器模式离线基线](validation/axil/README.md)：32 位单在途读写桥、真实 CPU/SoC、RV32IM 独立预期及异常/中断；范围和未测项目明确列出。
- [AXIL 同版本 PDS/网表验收](evidence/axil-pds-20260927.md)：实际综合、碰撞X注入与27MHz约束内时序；旧候选板级约束未获实物确认。
- [真实CPU＋新AXIL在途取消](evidence/axil-cancel-20260927.md)：84个读写/复位窗口，独立目标、36轨迹负向与6个RTL故障对照；专用RTL集成测试，不是上板结果。

本分支为 `task/T06-cpu-validation-contract`，对应 [PR #25](https://github.com/liyingqi-habit/fpga-quality-inspection/pull/25)。协作基础在另一个尚待合并的 [PR #24](https://github.com/liyingqi-habit/fpga-quality-inspection/pull/24)，两者不是已集成版本。

- [同时 pending 中断优先级](evidence/axil-irq-priority-20260927.md)：16种组合、4次启动、144次处理；包含屏蔽后释放、mret 和实际 RTL 优先级反转负向检查。
- [CSR三项修复与回归](evidence/axil-csr-fix-20260927.md)：195用例各两次启动通过，撤销三项修复的实际RTL负向检查均能发现错误；保留原始失败记录。
- [访存异常与中断竞争](evidence/axil-irq-exception-20260927.md)：144配置、288次启动，检查异常次序、精确PC、寄存器保留和返回后的IRQ；20项检查器负向及2个真实桥错误抑制变体被拒绝。
- [其他同步异常与中断竞争](evidence/axil-sync-competition-20260927.md)：ECALL等7类、126配置/252次启动；140项检查器负向和实际取指错误抑制负向通过。嵌套、在途复位及该固件网表测试未覆盖。
- [两层中断与处理期间局部复位](evidence/axil-nested-reset-20260927.md)：36个嵌套/延后配置和324个复位配置，含132个非零pending保留；25项检查器负向及2个实际故障对照通过。专用RTL夹具，不是板级复位验收。
