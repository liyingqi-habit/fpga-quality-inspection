# CPU-WR-02 执行证据（2026-09-27）

范围：独立写目标、合成驱动、独立事件检查器及检查器负向对照。**不包含真实CPU、LSU、桥、PDS或上板验证。**

## 复现

在仓库根运行：

```bash
bash validation/write_response/run.sh
```

本次环境：WSL Ubuntu，Icarus Verilog 12.0，Python 3.14.4。最终加强复位阶段与B背压覆盖检查后重新执行，退出码0。仿真在2.65微秒结束，未触发2000周期超时。运行器保留原始trace.csv、run.log和输入SHA256于其打印的本地临时目录；公开记录不包含本机路径。

## 实际结果

|项目|结果|
|---|---|
|合成场景|12个通过；11个关闭，1个永久无响应场景保持隔离|
|请求顺序|AW先、W先、同时到达均覆盖；同时到达例施加4周期请求背压|
|响应延迟|最短、7及31周期成功，以及延迟9/3周期的错误响应|
|错误响应|代码2和3；合成异常上下文PC、地址及cause=7匹配，无合成成功退休|
|CPU局部复位|未接受、AW-only、W-only、等待B、B握手同周期、永不响应六阶段覆盖|
|B背压|所有返回响应场景至少3周期保持；载荷稳定检查通过|
|隔离窗口|永久无响应场景复位后至少30周期，未释放或复用槽位|
|目标内存|返回响应场景的字节掩码与模型错误不写政策检查通过|

检查器最终输出：

```text
PASS: independent synthetic-trace scoreboard {'scenarios': 12, 'closed': 11, 'quarantined': 1}
PASS: 12 negative controls rejected with expected reasons
LIMITS: synthetic verification infrastructure only; no CPU/LSU under test
```

12项负向对照均被预定错误码拒绝：提前退休、错误当成功、错误PC/地址/cause、年轻MMIO副作用、未排空即释放、旧退休、AW/W/B背压载荷变更、隔离槽位重用。这里修改的是观测轨迹，不是对真实CPU注入故障。

## 结论与交接

已具备可运行的写响应验证夹具和会拒绝错误轨迹的独立检查器；其独立性是检查算法不依赖驱动的完成判断，并非独立第三方审计。当前retire/trap/young是合成事件，不能推断真实流水线正确。目标错误不写内存只是模型政策，不保证真实设备写错误可回滚。

BUS-01、BUS-03、BUS-06的**真实CPU验收仍为NOT_RUN**，现有精确store异常缺口未关闭。下一步：评审写响应/复位合同与观察口，再接入单在途LSU/桥，从真实流水线取得退休、异常及年轻副作用事件，重跑这些场景。不得仅将合成PASS改名为CPU PASS。

关联：#6、#20、PR #25；两名非作者审核，所有者手动合并。
