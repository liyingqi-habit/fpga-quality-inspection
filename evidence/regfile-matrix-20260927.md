# CPU-WR-07：间隔、寄存器、停顿与冲刷矩阵

日期2026-09-27；父提交 `778483be04e046441f58178e3d3b895ba3d2ed98`。受测工具为首次加入本报告的提交。结论：**480组所选组合在RTL、对应综合网表及冲突读值X注入下均得到预期架构结果；不是穷尽或上板证明。**

## 输入与复现

入口、依赖、参数和执行顺序见[运行手册](../validation/lsu_soc/README.md#cpu-wr-07可扩展寄存器堆定向矩阵)。Icarus12.0、RISC-V GCC14.2.0、PDS2025.2 build211867 ADS；PG2L200H -6 FBB676，27MHz测试时钟，无SDF。

正常CPU SHA256 `63bb55e1bb43cc472699a09f1e2dbd674a68cab562da0df9d988b16f9b321140`，迁移SoC `95d528658edb507a1eb3e0ef94663fe7ea6fda25435f6967a3e0ff3cb4cc7046`；未修改CPU、SoC、原工程或厂家模型。包装层及旧候选约束沿用CPU-WR-05的固定输入检查；厂家模型只读使用、未公开上传。

|批次|参数与固件体积|固件SHA256|新综合网表SHA256|
|---|---|---|---|
|基础432|8寄存器×6间隔×3角色×3上下文；13716字节|`8b2ea278d401e1f505dfec991fca1da466193833b1259d11e7f1fcf85ce20e17`|`748fcb0c840d9572349257354c02e47ad274f18e5912a31aec458bf868fcbd7c`|
|叠加48|x0/x2/x15/x27；NOP0/1/3/5；3角色；divide_flush；2148字节|`4476e023cd8969af7fad9d87b775583f1ac5eb9939c72c58f588221a388c8acb`|`7c72538e07fc774364beddcfea295c920277313df3a37f2e578a8af978ce900f`|

本地固件目录标识分别为regfile-matrix.h2cZHynZ、regfile-matrix.TP56bGwO；独立PDS保留目录标识pds-regfile-base-0110278d、pds-regfile-combined-d4b7a2f9。完整绝对路径、第三方文件和日志留本地，不随公开仓库提交。

## 检查机制与实际结果

生成器输出cases.json，覆盖每个选定的(上下文、寄存器、NOP数、源操作数角色)。生产者写入带符号立即数；消费者为ADDI/SUB/ADD；x0恒为0。Python独立整数运算产生32位预期，不读取仿真结果。每组以连续SW输出结果，测试台检查地址、数据、顺序、非X及完成条件，任何非法地址写、额外读写或trap均失败。

|实跑检查|结果|
|---|---|
|基础矩阵RTL、网表、X注入|各2轮×432组通过；每轮实际DIV计数144，安排的分支用例144；三份命令CSV各866条、逐字节一致|
|叠加矩阵RTL、网表、X注入|各2轮×48组通过；每轮实际DIV计数48，安排的分支用例48；三份命令CSV各98条、逐字节一致|
|错误参考负向对照|两批综合网表分别把case0预期翻转1位，都以指定的Matrix reference mismatch case=0拒绝；不是任意退出算成功|
|生成器单元测试|4项通过：432唯一交叉组合及x0/手算值、叠加生成、保留寄存器拒绝、结果区溢出拒绝|
|Shell语法检查|build_matrix.sh与run_matrix_netlist.sh的bash -n通过|

最终网表运行标识：基础regfile-netlist.V0lxIEu5、叠加regfile-netlist.YREgIm35。早期基础regfile-netlist.wkuD8kgJ也通过；随后加强未知写使能检查并重跑最终版本。原语冲突在正常网表与X注入中每轮一致：

|当前用例上下文|rs1副本冲突|rs2副本冲突|
|---|---:|---:|
|普通|71|23|
|DIV停顿|38|15|
|分支冲刷|14|14|
|DIV＋分支冲刷（第二批）|9|9|

冲突定义为真实GTP_DRM18K_E1时钟沿WEA有效且ADDRA==ADDRB。测试台在冲突后1ns将相应原始读值强制为X，跨下一消费沿后释放；没有改厂家模型或综合网表。命令接受观测沿用CPU-WR-06：零响应延迟配置下响应寄存器D且非reset；全部用例为SW，使用SoC级d_data。

这些数字是原语事件，包含可能未被有效指令消费的读地址；上下文按当前待完成结果用例分类，可能有相邻指令重叠。不宣称480组每组都发生冲突，也不将branch_cases当作内部冲刷脉冲测量。DIV计数来自实际迭代计数器到10的事件；分支行为以错误路径无副作用及正确结果验证。

## 两份PDS报告

两次均独立完成compile/synthesize/dev_map/pnr/report_timing，退出0；检查器与4项负向自测分别通过。报告数值一致：1431 LUT、1161寄存器、0锁存、13 DRM36K等效、4 APM。slow setup最差裕量27.305ns、fast hold最差裕量0.131ns；快慢角setup/hold/recovery/removal/mpw均无失败端点。两份网表哈希不同，ROM内容各自固化，未混用旧网表。

仍有3个no_input_delay、4个io_min_max_delay_consistency，异步rstn/key/uart_rx例外及旧候选引脚/零输出延迟限制不变。状态只为CONSTRAINED_PATHS_PASS_WITH_PROFILE_LIMITATIONS，板卡NOT_VALIDATED。不把工具102.7538MHz估算当作板卡Fmax。

## 边界与交接

本次只补测试基础设施与证据；不改CPU功能、不消除Adm-4097警告、不生成bitstream、不操作板卡。参数可扩展x0—x27、NOP0—32及四类上下文，但受512结果/16KiB ROM约束，需要分批重新综合；x28—x31是工具寄存器，未作为矩阵目标。

未覆盖：所有寄存器/操作码/实际周期组合、外设随机背压、全部在途复位交叉组合、完整异常中断/Cache/预测、SDF及实物。下一步可在已明确边界下补独立总线背压与冲刷交叉测试，或由人工确认真实板级约束后安排上板。PR仍需两名非作者评审，所有者手动合并；不把本轮测试视为完整赛题验收。
