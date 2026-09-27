# CPU-AXIL-01：读写桥与机器模式集成

日期 2026-09-27；父提交 42e254bf302f7b0804c6e60cf89136ebaeebc67d。受测输入、运行入口和范围见 [README](../validation/axil/README.md)。结果是有限离线基线通过，不升级赛题完整 ISA/中断为完成。

实跑环境：WSL Ubuntu、Icarus 12.0、riscv64-unknown-elf GCC 14.2.0（rv32im_zicsr / ilp32 / mno-relax）、Java17、sbt1.10.7、Spinal1.13.0；固定 Vex 上游 7445c66。生成 CPU SHA256：`6bc91de7f76e88d7edf056e8d30790c645876bf13e7177e7827c949ff12d141e`。程序 ROM：`773e5cbb012284d43806645e83d90c6e879e85d6ea70ee806b855775839791b1`。

- `bash validation/axil/run_bridge.sh`：输出 axil-bridge.dijX4u0C，576 组合及 2 个无响应隔离 PASS。
- `bash validation/axil/run_soc.sh`：输出 axil-soc.gJYXqGg2，真实生成 CPU + AXIL 桥 + 可综合 ROM/RAM/自定义 MMIO；两轮启动各 199 个独立结果、9 类同步异常、3 类屏蔽/pending 中断 PASS。
- 独立 expected[4] 翻转一位：如期以 `ISA result mismatch word=4` 非零退出。正常和负向日志分开保留。
- 固定生成快照 axil-cpu-v3；既有 source checkout 未修改。

## 实际发现的失败及修补

初版更完整 CSR 配置在 ECALL 返回 mtval=0x73，固件拒绝。原始失败输出 axil-soc.7s86dGdF 保留；没有降低预期来过测。查核 [RISC-V Machine-Level ISA 的 mtval 规则](https://docs.riscv.org/reference/isa/priv/machine.html)：ECALL/中断应写零，EBREAK 可为零或指令地址。对固定副本添加 ECALL/EBREAK badAddr=0，并在机器 trap 入口清 mtval，再由同步异常覆盖真实 badAddr。上下文匹配不唯一立即拒绝；修补后上述异常/中断测试通过。

初次脚本也暴露 SoC wire 声明语法错误，已拆分声明；失败日志没有算作通过。

## 未升级的结论

独立桥取消组合不是完整真实 CPU 的新 AXIL 在途取消交叉；前一步 CPU-WR-09 使用旧 write_bridge，不能混算。新 SoC 综合配置将局部 cancel 固定 0，只用共同复位。UART 串行波形未在本次新增 SoC 套件重测。完整优先级/嵌套中断、架构认证、DDR/DMA/Cache/预测、性能与实物仍未验收。

PDS 与对应综合网表属于下一份证据；不能以 RTL PASS 代替第四步。
