# GitHub 实际设置与验收

目标：个人账号 liyingqi-habit/fpga-quality-inspection，Public，main；T00 分支 chore/T00-bootstrap-v4。
实际结果见 [核验记录](../../evidence/bootstrap.md)。远端仓库、PR #24、23个Issues及Project #1均已创建；完整待审内容在chore/T00-bootstrap-v4，main保持最小README种子直到人工合并。
两位成员用户名尚未提供；用户已同意 Write 开发权限，未邀请/未接受。不得默认 Admin。

质量层仅保护main：PR、两名非作者批准、新提交使旧批准失效、讨论解决、管理员不绕过、禁止强推与删分支。
repo-baseline 已在真实PR成功后设为必需检查，固定GitHub Actions app_id 15368，严格要求最新基线；后续提交须重跑，不能通过关闭检查解决失败。
已核验两个独立active规则集，仅作用于main：24044105质量层无任何bypass；24044107更新限制仅User 316439266（liyingqi-habit）在pull_request路径获准通过。这不豁免质量层，不允许直接推main。当前唯一管理员是所有者；新增管理员/规则变更需重新审核。
CODEOWNERS不能代替两份批准，未知账号不填。即使规则生效，拥有管理权限者仍可能修改规则，不能宣称绝对不可绕过。
Project #1已关联仓库及24个条目，仅展示同一套Issue/PR状态；未指派未知成员。不得给公开PR配置连接电机/高权限的自托管runner。
