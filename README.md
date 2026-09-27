# 传送带智能质检工作站

基于盘古 200K MINI，目标是完成设备内 AI 检查、独立托盘及停车式传送分流的完整工作站。

当前处于协作基础建设阶段，尚无团队验收的硬件版本。
后续内容通过任务分支和 PR（审核后合入主线的申请单）提交；两名非作者审核后，由项目所有者手动合并。

## 当前任务分支入口

- [赛题逐项对照表](docs/competition/REQUIREMENTS_MATRIX.md)：要求、已有证据、未完成项和验收方式。
- [队员上手指南](docs/team/GETTING_STARTED.md)：看代码、评审、修改和运行测试。
- [CPU 离线测试](validation/cpu/README.md)：需要合法外部输入，不是完整可上板工程。
- [独立写响应测试](validation/write_response/README.md)：可独立运行，但合成驱动不是CPU。

本分支为 `task/T06-cpu-validation-contract`，对应 [PR #25](https://github.com/liyingqi-habit/fpga-quality-inspection/pull/25)。协作基础在另一个尚待合并的 [PR #24](https://github.com/liyingqi-habit/fpga-quality-inspection/pull/24)，两者不是已集成版本。
