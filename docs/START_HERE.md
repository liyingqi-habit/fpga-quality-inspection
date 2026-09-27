# 第一天怎么开始

我们要做的是一台检查真实接线组件的设备，而不是只让灯闪或在电脑上画检测框。完整流程见 [产品](PRODUCT.md)。

## 今天可以做什么

先看 [8 张首批卡](tasks/README.md)。最先做 T01-01 实物/工具盘点；T01-02 规则问题整理、T04-01 光学准备、T11-01 身份接口草案可以独立推进。
拿不到输入的部分写阻塞，不让“已写文档”变成“硬件已通过”。

## 打开哪里

本项目根目录就是含本 README 对应 docs/ 的 Git 文件夹。不要把 codex_handoff_v4 或 private_inputs 当工程。
[工程登记](setup/PROJECTS.md)目前是 MISSING；没有可公开重建的团队 PDS 基线。不要打开 example JSON 当作 PDS。

## 运行基础检查

安装/选用 Python 3.10+ 和 Git，Windows PowerShell 或其他终端进入仓库根：
```text
python tools/project.py doctor
python tools/project.py check
python -m unittest discover -s tests -v
```
若 python 不在 PATH，按 [环境说明](setup/ENVIRONMENT.md)用你机器上实际解释器路径替换 python。
doctor 报告工具缺口；没有 PDS 不妨碍仓库检查，但会阻塞硬件构建，不能写硬件通过。
本机真正运行的记录放 [证据索引](../evidence/README.md)。

## 几个词

- Issue：一张有负责人、状态和交接的任务单；技术定义在 docs/tasks，不在四处复制。
- PR：请求另外两人审核并把修改合入 main 的申请单。
- main：已经经过审核的阶段基线，不是试验工作台。
- CI：GitHub 自动运行的基础检查，本轮只验证文档/清单/工具，不测试电机或 FPGA。
- G0—G7：证据关卡，不是日期、分支或文件数量。
- golden：独立参考结果，要防止参考程序和硬件复制同一个错误。

初始化 PR 未合并时 main 只有短 README，完整内容请切到 chore/T00-bootstrap-v4 查看。
认领、提交和审核按 [贡献流程](../CONTRIBUTING.md)；不因只有一个账号就凑审批。
