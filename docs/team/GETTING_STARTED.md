# 队员上手指南：先看、再评审、最后改代码

状态快照：2026-09-27。仓库公开；Luckyfish416与chenyuanlei696-a11y均已核实具有Write开发权限，所有者为liyingqi-habit。权限和分支状态会变化，以GitHub实际页面为准。不需要互相传密码、令牌或验证码。

## 1. 发给队员的入口

- [仓库](https://github.com/liyingqi-habit/fpga-quality-inspection)
- [CPU任务分支](https://github.com/liyingqi-habit/fpga-quality-inspection/tree/task/T06-cpu-validation-contract)
- [PR #25的代码差异与评审](https://github.com/liyingqi-habit/fpga-quality-inspection/pull/25/files)
- [赛题对照表](../competition/REQUIREMENTS_MATRIX.md)
- [任务 #20](https://github.com/liyingqi-habit/fpga-quality-inspection/issues/20)

main目前仍是最小README基线；PR #24是协作基础，PR #25是CPU先导验证，两者在核对时均未合并。不要只打开main就以为没有代码。网页左上分支选择器可切到上述任务分支。只阅读无需下载ZIP或安装PDS。

已公开：测试台、汇编/C测试程序、脚本、写响应目标和Python检查器、草案与摘要。未随包公开：完整CPU RTL/生成工程、完整PDS工程、厂家库、原资料包、private_inputs和凭据。因此看得到测试代码，不等于全新电脑能运行所有CPU测试。

## 2. 如何评审

1. 先读本指南、赛题对照表、[CPU说明](../../validation/cpu/README.md)、[写响应说明](../../validation/write_response/README.md)及对应evidence。
2. 打开PR #25的Files changed，点相关行添加评论：写清文件/现象、为什么有问题、期望怎样验证。只问问题时用Comment；确认阻塞问题时用Request changes；确实检查后才Approve。
3. 至少核对：测试预期是否独立；错误是否归属原PC/地址；复位旧事务是否隔离；README命令与源码是否一致；有没有把合成测试说成真实CPU通过。
4. 报告实跑命令、工具版本、commit、结果和未跑部分；没有外部输入可完成静态评审，但明确写“CPU回归未运行”，不要照抄作者的PASS。
5. PR #25当前是Draft，先评论预审，由作者在准备好后转为可正式评审。每个PR需两名非作者审核，最后仅由所有者手动合并；不能代发Approve或自动合并。

如果评审者后来成为该PR的实质代码作者，应重新核对两名非作者要求；三人团队不足时先与所有者协调拆分PR或找独立审核者，不把自己的代码算作独立审核。

## 3. 下载并运行独立写响应测试

以下是给队员执行的命令，不表示已在队员电脑运行。安装Git；仿真建议用Linux或Windows的WSL终端。需Bash、iverilog/vvp、Python 3、sha256sum，已测Icarus 12.0/Python 3.14.4。缺软件按其官方安装方式准备；此指南不运行安装器。

在一个没有同名项目目录的父目录执行（已有目录不要覆盖）：

```bash
git clone --branch task/T06-cpu-validation-contract https://github.com/liyingqi-habit/fpga-quality-inspection.git
cd fpga-quality-inspection
git status --short
git rev-parse HEAD
bash validation/write_response/run.sh
```

期望：12个合成场景（11关闭、1保持隔离）；12个负向对照被指定原因拒绝；脚本退出0。`REJECTED`在此表示检查器成功抓住故意破坏，不是测试失败。结果保存在脚本打印的临时目录，含trace.csv、run.log、输入哈希。

这无需CPU输入、PDS或板卡。retire/trap/young由合成驱动产生；**不能以此宣称真实LSU、CPU或整机通过**。不要发送串口命令或操作执行器来“补测”。

## 4. 原CPU回归和PDS边界

当前最新入口是 [AXI4-Lite/机器模式基线](../../validation/axil/README.md)，含生成配置、可综合桥/SoC、独立预期及同版本PDS/网表流程。队员可先运行 `bash validation/axil/run_bridge.sh`（Python3/Icarus，无需CPU外部输入）。完整SoC回归另需合法上游源码、生成工具和UART输入。PDS/网表离线通过不代表上板验收。

此前[最小SoC迁移入口](../../validation/lsu_soc/README.md)保留为历史回归，其旧CPU、网表和证据不能混用到新基线。

新增[真实LSU实验入口](../../validation/real_lsu/README.md)：需要固定上游源码、Java/sbt生成环境；不使用原CPU_INPUT_ROOT四文件作为新配置。它是另一套受测配置，不把旧CPU回归结果自动继承过来。生成/运行/故障对照分别按该目录说明执行。

原CPU回归另需RISC-V裸机GCC/objcopy/objdump和合法外部输入。先向所有者确认取得匹配版本的方法；原资料包不得直接上传公开仓库或随意转发。

`CPU_INPUT_ROOT`目录必须包含以下四项，且通过[固定哈希](../../validation/cpu/inputs.sha256)：

```text
rtl/mini_soc.v
rtl/mini_uart.v
rtl/generated/VexRiscv.v
rtl/generated/VexRiscv.v_toplevel_RegFilePlugin_regFile.bin
```

在Bash中设置CPU_INPUT_ROOT为你自己的合法输入目录，执行`bash validation/cpu/run.sh`。缺输入记BLOCKED；哈希不同先报告版本差异，不改哈希来绕过校验。该脚本不调用PDS、不烧录板卡。

综合网表入口`bash validation/cpu/run_netlist.sh`还需设置CPU_NETLIST和PDS_SIM_LIB，分别指向匹配网表与已安装厂家仿真库；它不是PDS工程构建入口，无SDF也无上板验证。完整原生PDS工程尚未公开可复现，不承诺“打开仓库就能在PDS运行”。保留原生IP、编码和必要生成输入，按PR #24的文件规范评审，不将所有生成文件一概删除。

## 5. 修改代码：一人一任务分支

先在Issue留言认领范围、预期产出和验收；三人均可认领任何模块，但不要多人同时直接编辑当前共享任务分支。现有工作区不干净时先停下来处理自己的改动，不使用强制重置或自动stash。

下面以“修改尚未合并的CPU测试”为例，分支名是示例，若已存在请换一个唯一名称：

```bash
git status --short
git fetch origin
git switch -c task/T06-yourname-review-fix origin/task/T06-cpu-validation-contract
# 修改明确范围内的文件，并运行相关测试
git diff --check
git diff
# 只暂存本次审核过的具体文件，不盲目 git add .
git add validation/write_response/check_trace.py
git diff --cached
git commit -m "test(cpu): describe the specific change"
git push -u origin task/T06-yourname-review-fix
```

`git add`中的文件仅为示例：未改它就不要照抄，换成本次实际文件。推送后在GitHub创建PR：此例base选`task/T06-cpu-validation-contract`，compare选自己的分支，说明依赖PR #25；不要误以为PR已基于最新main。无关新任务应从更新后的origin/main起步；需要PR #24基础工具的任务须先协调依赖，不能把两条分支随意混合。

每一步完成后在自己的任务分支提交并推送，Issue记录commit。不要强推、不直接提交main、不修改他人的分支。若推送被拒绝先检查权限/远端变化，不覆盖远端。此类嵌套PR合入任务分支后，最终PR #25仍需完整审核。

## 6. PR和交接最小模板

```text
任务：Issue链接；base分支；起始commit
修改：具体文件和行为，影响的接口/消费者
实际检查：命令、工具版本、输入哈希、退出码/结果、证据位置
未测与风险：哪些是合成/RTL/网表/板级，外部依赖和已知失败
下一步：谁需要接入什么；两名非作者评审后由所有者手动合并
```

公开日志先检查用户名、本机绝对路径、凭据、第三方内容和再分发许可；原始日志本地留存，公开脱敏摘要，不能改失败为通过。本分支当前没有PR #24的tools/project.py及完整基础CI，不能照抄其检查命令或宣称CI已通过。脚本失败时附实际输出，不只截取最后一行。

建议首个上手任务：只运行独立写响应测试，给PR #25评论复现commit、两项统计和一个检查器观察点；无需先碰板卡。

寄存器堆测试专项评审可阅读[CPU-WR-07证据](../../evidence/regfile-matrix-20260927.md)与[参数化入口](../../validation/lsu_soc/README.md#cpu-wr-07可扩展寄存器堆定向矩阵)：核对432＋48组的参数、Python预期、错路径副作用检查、实际冲突计数及未覆盖范围。改固件参数后必须生成新网表，不复用旧ROM网表声称通过；厂家库与CPU输入仍需本地合法准备。
