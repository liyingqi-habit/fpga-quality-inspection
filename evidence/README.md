# 证据入口

[T00实际检查和远端状态](bootstrap.md)：区分本地通过、远端已核验与待授权步骤。

没有硬件验收版本或最终发布。T00 工具结果只说明仓库基础可用。
记录模板用 python tools/project.py evidence 生成，默认 NOT_RUN；人工填实际结果后提交受审记录，不自动升级 PASSED。
原始日志/波形/视频应可长期取得并有哈希，不只存截图或会过期CI附件。
状态：PASSED / FAILED / NOT_RUN / BLOCKED；N/A 必须写原因。
隔离仿真、机构人工判定、真实设备内AI必须分开。模板/JSON写PASSED本身不是物理证据。
本地临时记录在 evidence/local（不提交），审核后的公开记录放 evidence/ 下，先排查私人路径、许可证和资料。
