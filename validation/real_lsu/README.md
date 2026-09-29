# 真实CPU/LSU写响应实验

区别于[合成驱动](../write_response/README.md)：本目录运行真正的VexRiscv指令流水线，执行program.S。退休来自writeBack，错误归属来自真实CSR，年轻副作用来自真实命令。独立目标仍复用write_response/target.sv；检查器按同组场景适配真实指令和复位重启，不把硬编码的合成事件当CPU结果。

参见[接口合同](../../docs/interfaces/CPU_WRITE_RESPONSE_EXPERIMENT.md)和[实跑证据](../../evidence/real-lsu-20260927.md)。无Cache、单时钟、单beat写实验，读请求仅报访问错误；不替换原工程，不证明完整AXI、DDR、PDS或上板通过。

## 生成及运行

依赖：Git、tar、Bash、Python 3、sha256sum、Java17、sbt、Icarus/vvp、riscv64-unknown-elf-gcc及objcopy。已测sbt1.10.7、SpinalHDL1.13.0、Icarus12.0、GCC14.2.0。sbt首次可能从所配置仓库下载依赖，离线缓存不完整则BLOCKED；脚本不自动安装软件。

先合法取得MIT许可的VexRiscv上游，并定位提交`7445c66bb4bb508f096c1d4814b4fae1ea8643c0`。Bash中设置：

|环境变量|指向什么|
|---|---|
|VEX_SOURCE|上述提交的外部Git checkout；脚本只读取固定提交归档，不修改该checkout|
|SBT_LAUNCH|本机已有sbt launcher jar（本次launcher1.6.0，运行版本由脚本指定1.10.7）|
|SBT_REPOSITORIES|本机sbt仓库配置，须允许所需合法依赖|
|REAL_LSU_BUILD|尚不存在的独立构建目录；不可用其他工程目录|
|TMPDIR（可选）|已经存在的持久结果父目录；默认系统临时目录，系统可能清理，需及时保存|

从本仓库根执行：

```bash
bash validation/real_lsu/generate.sh
bash validation/real_lsu/run.sh
```

generate.sh归档固定源版本，在新目录打带精确匹配检查的补丁，再生成CPU；拒绝覆盖既有目录，生成文件/依赖源码不提交。保存生成日志、生成器输入哈希、RTL哈希与normal/negative模式标记。run.sh拒绝负向模式；每例保留程序ELF/HEX、原始CSV和运行日志。

需要重新生成时选新REAL_LSU_BUILD路径；不删除原工程来腾位置。源或工具版本不同先报告，不修改固定版本门槛来冒充复现。上游MIT条款见[VexRiscv-LICENSE.txt](VexRiscv-LICENSE.txt)，补丁中的上游片段及派生产物保留该声明。技术许可不代表比赛复用资格已确认。

## 同组12例及差异

0 AW先短响应；1 W先延迟7；2 同时且请求背压、延迟31；3/4 延迟9/3返回错误2/3；5 接受CPU命令前复位；6 AW-only复位；7 W-only复位；8 等B复位；9 B握手边缘复位且旧B错误；10 普通成功；11 无响应复位隔离至少30周期。

6—9增加真实CPU排空后自动重启及新写完成；5重启后才有首次总线事务。固定PC为0x80000010故障store、0x80000014年轻store，测试地址0x10000000+4*case；这些不是整机ABI。使用真实SW/WSTRB=15，之前合成夹具的掩码5不由软件SW伪造；字节/半字需要后续新增真实程序验证。

独立检查器检查所有写的握手/响应、原写退休、年轻写退休、错误CSR、背压稳定性、epoch、六种复位阶段及隔离/重启。每例5000周期超时。12个轨迹破坏负向对照必须按指定原因被拒绝。

## 真实CPU故障对照

仅在另一个新的构建目录中，将WR_NEGATIVE_CONTROL设为1后运行generate.sh，得到故意不等待写响应的CPU。然后将REAL_LSU_NEGATIVE_BUILD指向该目录，执行：

```bash
bash validation/real_lsu/run_negative.sh
```

它必须以RETIRE_BEFORE_SUCCESS拒绝真实轨迹，任意其它错误或未拒绝都不算通过。恢复正常实验前取消WR_NEGATIVE_CONTROL并把REAL_LSU_BUILD切回正常构建目录。负向CPU不可用于正常应用。

## 未覆盖

原mini_soc完整回归在新配置下的迁移、正常load、SB/SH、错误路径store、完整中断/取指异常、Cache、DMA、多ID/burst、跨时钟、全局在途复位、有界超时报错、PDS综合时序及实板均未由本实验验证。旧基础CPU的通过结果不能自动转移到此配置。
