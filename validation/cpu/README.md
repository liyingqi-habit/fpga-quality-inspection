# CPU 离线测试包

关联 #6、#20。首次提交的是先导测试与证据，不是完整可上板工程，不自动关闭父任务。

依赖：Bash、Python 3、Icarus Verilog/vvp、riscv64-unknown-elf-gcc/objcopy/objdump、sha256sum。已测试版本 Icarus 12.0、GCC 14.2.0。

## RTL 测试

本包不附带第三方 CPU RTL 或厂家文件。需要独立准备合法本地 CPU 工程目录，含 inputs.sha256 中四个精确版本文件；不匹配时脚本停止，不能通过修改哈希冒充同版本复现。没有这些输入时状态为 BLOCKED，不是已支持全新电脑一键构建。

设置 `CPU_INPUT_ROOT` 为该目录，然后从仓库根运行：

```bash
bash validation/cpu/run.sh
```

运行器只读外部输入，将公开测试放进唯一临时目录，运行原固件启动/独立UART、27项定向案例、异常及运行中复位、两项错误预期负向对照。结束打印证据位置，保留结果供检查。不修改外部固件，不调用PDS或下载器。

## 综合后功能仿真

另行合法准备对应 PDS 网表及已安装厂家库，设置 `CPU_NETLIST`、`PDS_SIM_LIB` 后运行 `bash validation/cpu/run_netlist.sh`。入口校验已测网表哈希；该网表和厂家模型不公开上传。27MHz原参数的门级模型运行较慢，有周期进度和400000周期仿真超时。不使用SDF，不证明时序或实板通过。

## 来源、许可与边界

新增汇编测试、测试平台、运行脚本及最小自检固件来自本项目本地先导工作，发布前已逐文件检查；未复制厂商原语实现、资料包、许可证或整个上游仓库。根许可证仍待团队决策，本次不自行选择开源许可。

外部候选 VexRiscv 上游为 SpinalHDL/VexRiscv，先导记录固定提交 7445c66bb4bb508f096c1d4814b4fae1ea8643c0，许可证 MIT（Copyright 2016 Spinal HDL contributors）；如将来引入其代码，应保留完整许可证并复核生成器/依赖。现有外部输入不等于本仓库已拥有可复现的CPU生成流水线。

原理图/电平/SCBV仍未最终确认。无DDR/DMA/Cache/中断完整验证，非法写精确异常尚缺失。测试通过不得换成最终工作站验收。见 [公开验证摘要](../../evidence/cpu-validation-20260927.md) 和 [接口草案](../../docs/interfaces/CPU_BUS_CONTRACT_DRAFT.md)。
