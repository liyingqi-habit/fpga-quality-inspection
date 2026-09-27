# CPU-WR-03 写响应及复位实验接口 v0.1

2026-09-27：按所有者本轮指令实现并验证；**DRAFT_IMPLEMENTED，待两名非作者评审，不冻结整机ABI**。这是单时钟、无Cache、无LR/SC/MMU、单槽单beat实验，不替代DDR/DMA设计。

## 真实LSU改造

固定VexRiscv提交7445c66bb4bb508f096c1d4814b4fae1ea8643c0。在只读来源的临时快照上对DBusSimplePlugin做五处带匹配校验的修改，开启waitForWriteResponse参数，强制emitCmdInMemoryStage=true。

命令在memory级握手进入桥；原指令进入writeBack级，成功响应前haltItself，阻塞年轻指令。writeBack处的访问错误通过原异常机制报告：store为cause7，load为cause5；未对齐异常不等待未发出的请求响应。不是仅将cmd.ready延迟，更没有修改观测数据来制造退休。

cmd在memory级、rsp在writeBack级避免了“同一级halt后再次发送”的问题；桥busy与rsp_valid使ready在占用或响应周期关闭。异常冲刷、PC和地址由真实流水线/CSR处理，需继续补充分支、load、各种指令混合回归。本实验未使用上游toAxi4Shared：它原有的B错误处理并不能直接满足合同。

## 信号合同

|接口|含义及约束|
|---|---|
|cmd_valid/ready|CPU到桥的单笔接受；32位地址/数据、4位mask、write；握手后桥持有数据|
|dBus_rsp_ready（历史名称）/error/data|此ready实际是返回有效事件，不是CPU反压。每次已接受命令最多一个响应；write的data无意义；write错误取非零B码|
|AWVALID/AWREADY、AWADDR|桥到独立目标的写地址通道；接受后不重复，未接受时保持|
|WVALID/WREADY、WDATA/WSTRB|数据与地址独立握手；未接受时保持载荷|
|BVALID/BREADY、BRESP|目标写结果；code0成功，2/3为测试错误；不支持独占，因此不把code1当独占成功|
|bus_reset|仅实验初始化，同时复位CPU、桥和目标；禁止用它证明真实DDR在途复位安全|
|reset_request|同一时钟域CPU局部复位请求；测试脉冲至少一个上升沿；复位优先于同沿B完成|
|cpu_reset|bus_reset或reset_request或cancelled；已发事务取消后，排空旧B前一直保持CPU复位|
|busy/cancelled|桥状态；已接受cmd必须排空，不能用CPU复位清掉；永不返回B则无限隔离，不自动恢复|
|admit/allow_b|实验流控输入；分别制造CPU命令背压和B背压，不是整机寄存器|

AW没有ID/burst/cache/prot等完整AXI属性，本实现不能直接替换完整AXI互连。桥在此夹具中对load仅返回访问错误，没有真实读存储目标；不能直接接替已有mini_soc使用。固定测试地址不是整机内存映射。

## 复位状态边界

1. cmd尚未握手：CPU复位可撤销该内部请求，无外部事务。
2. cmd已握手：桥已承担事务，即使AW/W尚未接受，也继续保持VALID并排空，不随CPU复位撤回。只接受AW或W时继续另一通道。
3. B与复位同周期：B可被排空，但不回送该CPU旧响应；CPU从复位入口重新启动。
4. 已取消且没有B：保持busy/cancelled/CPU复位，不复用槽位。当前没有有界超时报错控制器，所以BUS-07的完整超时要求仍未完成。
5. 排空不撤销目标已发生的写。目标“错误不写内存”是测试模型政策，真实设备可能部分写入；软件缓冲有效性策略另行实现。

## 验证观察口

- obs_cmd_pc来自memory.PC；issue取真实cmd握手，不由测试台安排。
- obs_store_retire来自writeBack.isFiring与真实MEMORY_ENABLE/MEMORY_STORE；obs_retire_pc来自writeBack.PC。
- trap事件在真实异常处理程序首条指令退休时采样；mepc/mtval/mcause读取真实CSR。异常未到处理程序会缺失事件并被计数/超时拒绝。
- 年轻副作用检查来自真实第二笔MMIO命令握手；错误测试还禁止该地址的有效请求出现，不绑零、不合成成功。
- CSV只在相应事件有效时记录PC/CSR，其余填0；有效事件出现X仍使解析失败。

本方案通过的是下列[限定配置的RTL证据](../../evidence/real-lsu-20260927.md)，不是原mini_soc或最终Cache系统已完成改造。待评审后才决定向T10整机接口升级。
