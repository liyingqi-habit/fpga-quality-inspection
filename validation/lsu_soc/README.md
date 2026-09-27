# CPU-WR-04：读写验证与最小SoC迁移

状态：RTL实验集成，待团队审核；不是完整比赛工作站、PDS时序或板卡验收。原vex_minimal板级工程未修改，迁移版mini_soc.v单独保存在本目录。

## 与前一步的关系

复用CPU-WR-03正常生成的真实CPU，不再通过只接受写的实验write_bridge连接外设，而是把同一LSU显式响应合同接到本地ROM/RAM/UART/GPIO/计时MMIO。前一步AXI-like写桥保留独立回归，其读通道仍未实现；本步不是新增AXI AR/R总线。

CPU在memory级发命令，writeBack级等待读/写响应。mini_soc对每次已接受命令恰好返回一次响应，RESPONSE_DELAY为0、7、31时分别验证；等待期间禁止新命令进入，读数据与错误信息保持到消费。RAM字节使能独立更新；非法写、ROM写、只读MMIO写报告错误并计数，CPU产生精确cause7。正常read返回ROM/RAM/MMIO数据，非法read产生cause5。

## 运行

依赖Bash、Icarus/vvp、Python3、RISC-V裸机GCC/objcopy/objdump、sha256sum。先按[真实LSU生成说明](../real_lsu/README.md)准备正常CPU。

设置REAL_LSU_BUILD为正常生成目录，CPU_INPUT_ROOT为合法旧最小SoC输入目录（本步只读取rtl/mini_uart.v，固定哈希校验），TMPDIR可设置为持久结果父目录。然后在仓库根执行：

```bash
bash validation/lsu_soc/run.sh
```

脚本创建独立临时工作目录，复制公开测试、迁移SoC与已核实UART，只修改暂存脚本以启用MIGRATED_SOC测试预期；不覆盖原工程或原固件。当前仍需外部UART输入及生成CPU，不能宣称全新电脑无依赖一键构建。无厂家库或原资料包上传。

## 覆盖内容

|检查|操作与独立判据|
|---|---|
|正常读|ROM常数、RAM读回、RAM末字、load立即使用、MMIO；汇编用独立常量检查|
|字节/半字|四个SB通道、两个SH位置、LB/LBU/LH/LHU正负值与扩展；测试台核对mask及最终RAM|
|分支冲刷|beq后错误路径RAM写、jal后UART写、bne后非法读；测试台禁止前两地址任何总线请求，并要求非法读只接受合法测试的1次；另测未跳转分支的正确写|
|异常|非法read、非法write、ROM write、只读MMIO write、未对齐LH/SH；逐次检查mcause/mepc/mtval、mret返回及六次trap|
|响应时序|记录每次命令/响应，检查一进一出、最小延迟、store在匹配成功响应之后退休、背压载荷稳定|
|重新启动|三种延迟均两轮启动；每轮必须19次读、13次写，命令/响应数一致|
|原功能迁移|启动、data/BSS、M、UART收发/回显、GPIO/按键、计时；原27例与异常/复位测试重新执行|

旧27例中的case26过去预期“非法写只计数并继续”。MIGRATED_SOC宏改为实际检查cause7/原PC/地址及mret，默认宏关闭时保留旧语义。旧UART复位定位增加accepted==1、tx_busy及字符B判据，避免将等待上一笔响应误认为第二个UART字符受阻。

负向测试包含原有错误MUL、错误mcause，加上新错误半字结果、错误LBU符号预期、故意改变分支使错误路径store真实发出；必须以对应错误信息被拒绝，不能任意失败就算通过。

## 复位及副作用边界

此最小SoC的rstn复位整个本地CPU/响应寄存器/UART；RAM不清零。片上写在命令接受时已生效，响应延迟只延迟确认；复位不回滚RAM。UART读在接受时弹出接收数据。这不是CPU局部复位与外部DDR仍运行的场景，不能替代CPU-WR-03桥的排空/隔离验证。

旧地址图及MMIO宽度策略仅作迁移兼容，不冻结最终整机ABI。无Cache/预测/完整中断/DDR/DMA、多ID/burst或跨时钟验收；新迁移版尚未跑PDS综合、布局布线或板卡。

输出run.log、各轮固件ELF/反汇编/HEX、access_trace.csv、输入哈希与负向日志。详见[本步证据](../../evidence/lsu-soc-20260927.md)。物理步骤仍需人工监管。

## CPU-WR-05：在途复位与混合指令

保持相同环境变量，执行 `bash validation/lsu_soc/run_extended.sh`。24个复位窗口覆盖读、写、读错误、写错误，延迟7/31，在接受后、即将响应、响应已出现但未采样时全局复位。检查响应清除、事务计数守恒、RAM已接受写不回滚、无旧响应及正常重启。

混合程序32组输入串联load依赖、算术/移位/MUL/DIV/REM、子字读写、符号分支和JAL/JALR。Python整数模型给出256字独立预期；三档延迟各两轮，逐字核对及核对访问次数。两项负向故障必须被指定检查拒绝。详见[扩展实跑证据](../../evidence/lsu-extended-20260927.md)。不宣称完整ISA或外部AXI/DDR复位通过。
