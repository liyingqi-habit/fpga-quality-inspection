# GitHub 实际设置与验收

目标：个人账号 liyingqi-habit/fpga-quality-inspection，Public，main；T00 分支 chore/T00-bootstrap-v4。
这里只描述目标；实际远端结果见 evidence/bootstrap.md，未核验不得说已生效。
两位成员用户名尚未提供；用户已同意 Write 开发权限，未邀请/未接受。不得默认 Admin。

质量层仅保护main：PR、两名非作者批准、新提交使旧批准失效、讨论解决、管理员不绕过、禁止强推与删分支。
repo-baseline 必须先在真实PR产生并成功再设为必需检查；严格要求最新基线。不能通过关闭检查解决失败。
唯一合并人要与质量层分离：个人仓库可能不能采用组织式推送限制；核实规则集能力后单独限制更新，不能用绕过质量规则达成。
CODEOWNERS不能代替两份批准，未知账号不填。即使规则生效，拥有管理权限者仍可能修改规则，不能宣称绝对不可绕过。
Project仅展示Issue状态；权限不足不伪报创建。不得给公开PR配置连接电机/高权限的自托管runner。
