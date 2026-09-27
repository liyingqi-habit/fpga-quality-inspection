# 传送带智能质检工作站

基于盘古 200K MINI，目标是完成设备内 AI 检查、独立托盘及停车式传送分流的完整工作站。

当前处于协作基础建设阶段，尚无团队验收的硬件版本。目标日期为 2026-10-30，不是已核实官方截止时间，也不是按期保证。

目前能做：阅读任务、领取明确范围的准备工作、运行仓库结构及工具自检。不能宣称：CPU、整图 AI、PDS 构建或机构已通过。

最后硬件验收版本：**无**。工程入口：**MISSING**，详见[工程登记](docs/setup/PROJECTS.md)。主要阻塞是匹配 MINI 的合法基础工程、板级身份和工具核验；两位成员用户名仍待提供。

## 每天从这里开始

[任务 Issues](https://github.com/liyingqi-habit/fpga-quality-inspection/issues) · [任务看板](https://github.com/users/liyingqi-habit/projects/1) · [待审 PR](https://github.com/liyingqi-habit/fpga-quality-inspection/pulls) · [证据](evidence/README.md)

- [可领取任务和八张操作卡](docs/tasks/README.md)：动态负责人和交接以远端 Issue 为准。
- [怎么运行、第一次上手](docs/START_HERE.md)：三个轻量命令，不等于硬件验证。
- [怎么提交和审核](CONTRIBUTING.md)：任务分支 → PR（审核申请）→ 两名非作者审核 → 所有者手动合并。
- [最终功能验收](docs/acceptance/FINAL_ACCEPTANCE.md)：没有证据就保持未验证。

[完整产品](docs/PRODUCT.md) · [T01—T15 地图](docs/ROADMAP.md) · [G0—G7 关卡](docs/acceptance/GATES.md) · [排期](docs/SCHEDULE.md) · [实际检查记录](evidence/README.md)

三人可认领任何模块；先从 T01-01 身份盘点、T01-02 规则澄清和 T11-01 身份合同中选择。光学准备、CPU/整数合同和纸面机构方案可按各卡输入并行。不能跳过安全、以 PC 推理替代最终设备内 AI，或以托盘替代完整传送分流。

初始化 PR 未合并时，main 仍只有最小 README；完整待审内容位于 chore/T00-bootstrap-v4。原资料包、厂商受限资产和 private_inputs 不公开上传；本轮不选择根许可证。
