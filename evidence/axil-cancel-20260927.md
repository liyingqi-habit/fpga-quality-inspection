# CPU-AXIL-03：真实 CPU + 新桥在途取消

2026-09-27；父提交5957d3370fb3bb9c7419cf13d8af263badbc0cce。新增专用RTL仿真，不修改生成CPU、bridge.sv、综合SoC或板级接口。使用相同正常CPU SHA256 `6bc91de7f76e88d7edf056e8d30790c645876bf13e7177e7827c949ff12d141e`。

## 场景与独立预期

真实VexAxilCpu发起命令、执行依赖指令、产生退休和异常；测试台只提供取指ROM、总线时序和局部复位，不伪造CPU请求/退休/CSR。独立AXIL目标只有初始全局reset输入，没有CPU局部reset输入；已经接受的旧事务继续完成。

写8种场景：正常、桥已收但AW/W均未收、仅AW、仅W、等待B、B握手同沿复位、B有效但背压时复位、B永不返回。读6种：正常、桥已收但AR未收、等待R、R握手同沿复位、R有效但背压时复位、R永不返回。每种交叉OKAY/SLVERR/DECERR与3/17周期目标延迟，共84场景。

两套明确区分的测试ROM：初始程序访问0x10000000，写0xaabbccdd或读到0xdeadbeef；局部复位时切到重启测试ROM，访问0x10000010，写0x55667788或读到0xcafebabe。ROM切换仅用于仿真夹具，不能宣称真实板卡会自动更换程序。读结果通过真正依赖该load的后续store写出；正常错误控制通过实际handler读取并写出mcause/mepc/mtval。

Python检查器从CSV重建单槽事务和AW/W/AR/B/R握手，不读取DUT内部busy作为交易参考模型。检查载荷稳定、无重复、响应延迟、取消后隔离、同沿取消优先、禁止旧完成事件、原指令PC0x80000010的退休次数/启动代际、新程序结果、异常CSR、无年轻副作用及目标内存。成功旧写允许已生效且不回滚；目标自身选择错误不改内存，该策略不推广为真实外设承诺。

## 命令与实跑

设置AXIL_CPU_BUILD为合法正常生成目录后：

```bash
bash validation/axil/run_cancel.sh
# 对已有输出独立审计：
python3 -B validation/axil/check_cancel.py <输出目录>
```

环境同AXIL基线：WSL Ubuntu、Icarus12、GCC14.2 rv32im_zicsr/ilp32、Python3。输出`axil-cancel.C9x5AC1M`完成84场景；检查器补强未知控制、场景集合及实际延迟检查后，对该轨迹重新审计通过。最终整套脚本重跑输出`axil-cancel.KDLSd312`：84场景、36轨迹负向、6个RTL故障全部达到预期。

- 84正常/错误/取消控制场景PASS，其中12个永不响应场景持续观察复位后100周期，没有新命令、旧退休或解除隔离。
- 36轨迹突变对照：读写等待响应窗口×3RESP×2延迟，分别伪造旧响应、提前释放、篡改依赖结果，全部按指定原因拒绝。
- 6真实RTL故障注入：隔离副本分别去掉错误传播、去掉取消响应屏蔽、去掉cpu_reset中的cancelled；每种跑真实CPU读/写各一例，分别以COMPLETION_VALUE、STALE_RESPONSE、EARLY_RELEASE拒绝。生产bridge.sv不改，正常和负向日志分开。
- 原桥回归`axil-bridge.RLSW3pes`：576+2和三种RTL故障对照PASS。
- 原SoC回归`axil-soc.QBJ0ajTl`：两轮199结果、异常/中断及预期突变PASS。

## 失败记录与限制

初次测试目标三元表达式紧邻十六进制常量造成词法编译错误，加入空格后修复。第一轮可执行测试被独立检查器拒绝UNDRAINED：测试台在写入完成标记后过早结束，最后B尚未返回。改为等待桥空闲且响应结束再收尾，不放宽检查器，不修改CPU/桥。

范围：32位对齐LW/SW、单时钟单在途、固定两档延迟和若干取消窗口。未覆盖所有周期穷举、子字取消、重复复位、随机长跑、真正DDR或多主机。无响应100周期是有界观察，不是无限时间证明。综合SoC局部cancel仍固定0；本次通过的是专用真实CPU集成测试台，不是物理复位方案或新PDS取消功能验收。未重跑PDS/SDF/板卡（综合输入未改）。第二项同时中断优先级仍待补。
