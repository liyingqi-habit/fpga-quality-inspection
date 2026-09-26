# 三个轻量命令

在仓库根使用Python 3.10+与Git；没有第三方Python依赖。

```text
python tools/project.py doctor
python tools/project.py check
python -m unittest discover -s tests -v
python tools/project.py evidence --task T01-01 --test identity --input README.md --output evidence/local/identity.json
```

退出码0仅表示此层检查通过，非0必须处理。doctor实际运行工具版本命令，可用 --require git python 指定必需工具；不猜PDS命令。check校验任务字段/依赖/循环/路径、正式工程依赖清单、本地Markdown文件链接、冲突标记和明显公开风险；不是原生PDS解析器，不保证发现所有秘密或许可问题。厂商二进制不转码；公开前仍需人审。

evidence读取Git SHA、未提交diff哈希和未忽略未跟踪文件哈希，给指定真实输入计算SHA256，只创建NOT_RUN模板并拒绝覆盖。原始diff本身须按需留在私有持久证据处，哈希不能恢复差异。运行后人工填写真实操作者、步骤、结果、日志及未覆盖范围；模板校验不证明实物真实。

CI只运行同样结构和单元测试，不连接硬件，不使用高权限self-hosted runner或pull_request_target。所有目标main的PR均触发稳定检查repo-baseline，无路径过滤。Actions固定SHA来自官方GitHub API的v4/v5引用；此配置尚须远端实际运行后才能设required。

