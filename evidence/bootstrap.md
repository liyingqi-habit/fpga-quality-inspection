# T00 实际检查与远端状态（阶段记录）

日期：2026-09-26。执行者：Codex 本地工具，按所有者授权；不是人工硬件验收。

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

## 尚未完成（不得当成已生效）

初始化分支第一次上传因缺workflow OAuth权限被拒绝，尚无PR及远端CI结果；repo-baseline尚未设required。Project等待project授权完成。另两位用户名未知，未邀请、未接受、无两份审核。没有合并、发布最终版或操作硬件。

下一步：补足明确授权，推任务分支、建PR并运行CI，成功后增加required检查；创建并关联Project、记录最终核验。技术工作从#16的T01-01开始。
