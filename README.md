# 传送带智能质检工作站

基于盘古 200K MINI，目标是完成设备内 AI 检查、独立托盘及停车式传送分流的完整工作站。

当前处于协作基础建设阶段，尚无团队验收的硬件版本。
后续内容通过任务分支和 PR（审核后合入主线的申请单）提交；两名非作者审核后，由项目所有者手动合并。

## 当前任务分支入口

- [赛题逐项对照表](docs/competition/REQUIREMENTS_MATRIX.md)：要求、已有证据、未完成项和验收方式。
- [队员上手指南](docs/team/GETTING_STARTED.md)：看代码、评审、修改和运行测试。
- [CPU 离线测试](validation/cpu/README.md)：需要合法外部输入，不是完整可上板工程。
- [独立写响应测试](validation/write_response/README.md)：可独立运行，但合成驱动不是CPU。
- [真实 LSU 写响应实验](validation/real_lsu/README.md)：固定源码生成实验CPU，真实退休/异常/复位检查；不是完整SoC或上板验收。
- [读写验证与最小 SoC 迁移](validation/lsu_soc/README.md)：正常读、SB/SH、分支冲刷、在途复位、混合指令及离线PDS结果；板级约束仍待确认，未上板验收。
- [迁移版综合网表回归](evidence/lsu-netlist-20260927.md)：同固件RTL对照、实际寄存器堆冲突计数、原始读值X注入；无SDF，不是完整硬件验收。
- [可扩展寄存器堆矩阵](evidence/regfile-matrix-20260927.md)：432组基础＋48组停顿/冲刷叠加，独立固件与对应综合网表对照；不是穷尽验证。

本分支为 `task/T06-cpu-validation-contract`，对应 [PR #25](https://github.com/liyingqi-habit/fpga-quality-inspection/pull/25)。协作基础在另一个尚待合并的 [PR #24](https://github.com/liyingqi-habit/fpga-quality-inspection/pull/24)，两者不是已集成版本。
