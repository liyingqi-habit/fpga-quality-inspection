# CPU-WR-01：写完成与退休路径审计

2026-09-27，状态：源码审计完成；改造建议 DRAFT；RTL未修改，接口未批准。关联 #6 / #20，接入去向 T10。

## 结论

当前 Simple 配置的 store 不等待写响应，也没有写访问错误回送到异常端口的路径。把 ready 延迟或接上现有 toAxi4Shared 不能直接证明精确写完成。建议先实现并验证无Cache、单在途、显式写应答的最小实验版本，之后再讨论缓存；此为建议，不是已批准路线。

## 固定证据版本

本地上游 HEAD：`7445c66bb4bb508f096c1d4814b4fae1ea8643c0`，审计时上游工作区干净。源码行号均相对于该提交，非上游当前主分支。许可证为MIT；本文只列定位和分析，不复制库实现。

当前生成器选择 DBusSimplePlugin 默认 earlyInjection=false、emitCmdInMemoryStage=false，无MMU/LRSC；五级流水下 cmdStage=execute、rspStage=memory。Cache路径仅作候选对比，并非当前CPU已实例化。

## 源码定位与证据

|位置（固定提交）|所见行为|可以得出的结论|
|---|---|---|
|DBusSimplePlugin.scala 285–292、379–384|默认选项；响应级选择；异常端口建立在响应级|当前错误归属须遵守memory级异常控制，不是外设单独打一个错误脉冲|
|同文件 411–427|cmdSent仅在rspStage=execute的配置生成；本配置不使用；valid排除stuckByOthers/flush/skipCmd|若新增“发出后继续停顿”，必须重新设计一次发送记忆，不能机械复用当前cmdSent|
|同文件 418–425|对齐检查置skipCmd|未对齐可在外部命令发出前拒绝；不代表物理地址权限检查已齐全|
|同文件 435–436|命令未ready时haltItself|现有等待只保证请求被接收，不保证远端写完成|
|同文件 483–503|响应等待及accessFault处理只针对非store；store仅有对齐异常代码6|没有store响应等待/代码7访问错误通路|
|Pipeline.scala 132–144|flush形成removeIt；更晚级停顿传播到更早级；isFiring=有效且不阻塞且不移除|可利用流水线屏障，但必须验证发请求周期与更老异常的先后关系|
|CsrPlugin.scala 1171–1178|通用计数实现以lastStage.isFiring推进minstret|这是最终级推进参考点；本小配置计数CSR未启用，不能声称用minstret测到了退休|
|同文件 1247–1260|异常使相关级removeIt/flushNext，并保存异常上下文、随级推进异常有效位|新增写错误须与仍在流水线的原指令及上下文一致，不能在其离开后借下一条PC报错|
|同文件 1390–1421|trap冲刷；mepc从捕获级PC取得，mcause/mtval取异常信息|必须同时保存/保持正确PC和故障地址；只回送B错误位不够|

固定版本源码入口：[Simple 插件](https://github.com/SpinalHDL/VexRiscv/blob/7445c66bb4bb508f096c1d4814b4fae1ea8643c0/src/main/scala/vexriscv/plugin/DBusSimplePlugin.scala)、[流水线](https://github.com/SpinalHDL/VexRiscv/blob/7445c66bb4bb508f096c1d4814b4fae1ea8643c0/src/main/scala/vexriscv/Pipeline.scala)、[CSR](https://github.com/SpinalHDL/VexRiscv/blob/7445c66bb4bb508f096c1d4814b4fae1ea8643c0/src/main/scala/vexriscv/plugin/CsrPlugin.scala)。本轮实际依据本地对应源码，不声称联网阅读这些页面。

## AXI转换器与Cache候选

DBusSimplePlugin.scala 130–162：pendingWrites在写命令握手时加、B握手时减；读在写未排空时受阻。rsp.ready/error/data接R通道，B ready常开。共享命令cache属性常量1111。因此“等待计数存在”不能推出“CPU写退休等待B”或“B错误精确报告”；统一cache属性也不能直接当作MMIO策略。

[DataCache.scala](https://github.com/SpinalHDL/VexRiscv/blob/7445c66bb4bb508f096c1d4814b4fae1ea8643c0/src/main/scala/vexriscv/ip/DataCache.scala) 281–317 的该 toAxi4Shared 路径同样计数B、只用R回送rsp.error。997–1015 显示常规非原子IO store和写穿store的writeBack halt可因mem.cmd.ready清除，而不是以成功B清除。结论限定于此版本和此转换器，不能推广到所有Vex配置或其它总线转换器。

当前 mini_soc 根本没有AXI：d_fire接受RAM/MMIO写，d_rsp_ready只对读有效，非法写增加fault_count。已有UART背压和非法写负例验证的是这个最小系统，不是上述AXI桥。

## 最小改造边界（待评审）

|组件|需要改变/增加|不得偷换|
|---|---|---|
|LSU|单在途状态，保存store PC/地址/宽度/数据/掩码，已发送标志，响应等待和错误态|不能因ready握手就将槽位释放|
|流水线屏障|原store停留或持有可恢复退休上下文；阻止年轻不可撤回副作用；更老分支/异常先决|不能把下游已接受事务当作可撤销|
|写响应接口|显式success/error和事务归属，异常端口接入及优先级|不能复用下一条load的响应槽报告旧store错误|
|AXI桥|AW/W独立接受记录、B归属、背压稳定性、范围/MMIO属性|pending计数不能替代每笔错误归属|
|复位控制|未完成请求排空或隔离；CPU局部复位与桥/DDR复位边界|超时/换epoch不等于旧事务消失|
|验证观察口|验证专用的store接受/完成/退休/异常归属事件；独立目标记分板|不得让DUT的done同时作为唯一正确预期|

两条路线：A，扩展Simple LSU和桥，先单在途无Cache验证精确语义，改造面较可控；B，直接修改DCache/写穿/AXI路径，可更早接近最终结构，但需同时处理命中、refill、写应答与错误状态，验证面更大。建议A作为实验，不承诺A满足最终Cache目标。局部CPU替换仍是未启动的备选门。

## 必须先建的三个独立反例

|合同编号|激励|独立检查与通过条件|当前状态|
|---|---|---|---|
|BUS-01|目标先接受地址/数据，扣住成功B，再释放|B前store成功退休次数为0，B后恰好1；AW/W均恰好接受一次；内存结果正确|NOT_RUN，显式响应LSU未实现|
|BUS-03|写接受后延迟错误，后接有副作用MMIO|原store不成功退休，mepc=原PC、mtval=原地址、cause正确；年轻MMIO接受次数0；错误内存不标为有效|NOT_RUN|
|BUS-06|分别在未发、只收地址、只收数据、等B及B握手边缘复位|跟踪旧事务到排空/隔离；不得复用旧槽位或缓冲；新任务不能收到旧完成|NOT_RUN|

测试目标需要独立AW/W队列、B调度和副作用计数；响应延迟取短/长/永不返回，并将允许的超时策略单独记录。软件可以检查CSR与哨兵，但不能仅靠最后打印PASS证明B前未退休。无响应/延迟错误不能在当前Simple外设模型中凭空伪造为已覆盖。

## 本步检查与交接

后续CPU-WR-02已建立[独立合成测试设施](../../validation/write_response/README.md)，执行结果见[2026-09-27证据](../../evidence/write-response-20260927.md)。这不改变上表真实CPU验收的NOT_RUN状态。

执行：核对上游提交与干净状态，阅读上述源码及当前生成器/SoC；核对PR #25远端头为7b476dc且#20无人认领；文档位置/敏感路径和diff检查。没有运行新的硬件仿真，没有修改生成器、CPU RTL或固件，没有板卡操作。

产出：本审计及源代码证据表。卡点：写完成路线尚未批准，异常/退休接口尚未设计落地。下一步建议CPU-WR-02：先写独立写响应测试目标/记分板和接口提案，评审后才实现LSU。仍要求两名非作者审核，所有者手动合并；此审计完成不使T06或T06-01自动Done。
