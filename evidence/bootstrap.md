# T00 实际检查与远端状态（阶段记录）

开始日期：2026-09-26；远端落地续至2026-09-27（Asia/Shanghai）。执行者：Codex 本地工具，按所有者授权；不是人工硬件验收。

## 本地实测

受测源码：8fb2e0eb7f924982fca63283172f4fe4b0a3703f，运行时工作区无未提交实现修改。Git 2.53.0.windows.3，Python 3.12.14，Windows PowerShell；机器绝对路径留本地，不公开。

- doctor：实际检测Git/Python版本成功，PDS/IP/仿真器仍未验证。
- `python -X utf8 tools/project.py check`：退出码0，仓库结构检查通过，不代表PDS/硬件通过。
- `python -X utf8 -m unittest discover -s tests -v`：15 tests，OK。覆盖缺字段、未知依赖、直接/间接循环、越界/缺失路径、缺工具、工程清单状态、假PASSED模板、真实输入哈希及拒绝覆盖。
- `git diff main --check`：退出码0；先前末尾空行已在独立提交清理。

预期是结构正确、无效输入被拒绝；实际符合上述15例。原始测试输出见[本地运行文本](local-checks.txt)，本记录是后续文档提交，不声称报告自身是受测SHA。CI与硬件证据另行核验。

未覆盖：原生PDS解析、真实工程/IP依赖构建、RTL仿真、CPU/AI性能、实物电气/机构、所有秘密和许可的自动发现。MISSING工程并非受测通过工程。

## 已核验的远端

- [公开仓库](https://github.com/liyingqi-habit/fpga-quality-inspection)，个人账号liyingqi-habit，用户ID316439266。
- main唯一种子c9f62bb71ea59190b27fe7216add8d2c30156ce8，远端tree只有README.md，与本地SHA一致。
- [父任务1—15及首批卡16—23](https://github.com/liyingqi-habit/fpga-quality-inspection/issues)。T02-01为#17，缺身份和合法匹配原工程，已标blocked；所有任务未关闭，未指派未知成员。
- [质量规则24044105](https://github.com/liyingqi-habit/fpga-quality-inspection/rules/24044105)：active；无bypass；PR两批准、dismiss stale、last-push approval、讨论解决、禁止删除和非快进。
- [唯一合并人规则24044107](https://github.com/liyingqi-habit/fpga-quality-inspection/rules/24044107)：active，仅针对main更新；仅用户316439266可在PR路径通过这层限制，不豁免独立质量规则。
- 有效规则API已核验main有上述规则，任务分支规则数0。唯一管理员目前是所有者。管理员仍可能修改规则，不能承诺管理权限永远无法变更政策。

## 远端后续核验

用户明确授权并亲自完成project/workflow追加认证后，初始化分支上传成功。[PR #24](https://github.com/liyingqi-habit/fpga-quality-inspection/pull/24)已创建，未合并。

首次真实CI：[运行36253561851](https://github.com/liyingqi-habit/fpga-quality-inspection/actions/runs/36253561851)，受测SHA 1b02b00cdb64d4e310fb6a6c1aec8b9f20a47ef8；check-run 108435994617 名称repo-baseline，completed/success，GitHub Actions app_id 15368。成功后才在质量规则24044105添加required_status_checks：context=repo-baseline、integration_id=15368、strict=true。保留两人审核等原规则，bypass仍为空。

[项目看板](https://github.com/users/liyingqi-habit/projects/1)已创建并关联本仓库，包含23个Issue和本PR，使用等条件/可领取/正在做/待验收/卡住/已完成。可领取仅指卡中允许的准备或设计范围，物理条件仍须确认。T02-01缺原工程保持卡住，PR待验收，未把硬件任务设为已完成。

上述是一次真实核验快照，后续提交需要新的CI。请在PR检查区确认最新head对应成功记录，而非只看本历史运行。

## 仍需人工完成

另外两位用户名未知，未邀请、未接受、无两份审核。提供用户名后仅邀请开发权限；两名非作者审核后由所有者手动合并。管理员能修改规则的管理边界依旧存在。没有合并、发布最终版或操作硬件。

下一项具体技术工作：[T01-01 #16](https://github.com/liyingqi-habit/fpga-quality-inspection/issues/16)，先盘点实物身份和工具版本，准确工程仍MISSING。
