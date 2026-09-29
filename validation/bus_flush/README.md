# CPU-WR-08：外部写总线背压 × 分支冲刷

真实CPU连接现有CPU-WR-03 `write_bridge`，目标侧由独立测试台控制AWREADY/WREADY/BVALID以及实验桥的B接收许可；不修改CPU或桥，不用force驱动CPU内部信号。这里的“外部”指CPU外的仿真写目标，**不是物理总线、完整AXI或DDR**；桥的读通道尚未实现，不将本轮称为读写全总线验收。

## 运行

准备[正常生成CPU](../real_lsu/README.md)，设置REAL_LSU_BUILD，TMPDIR可选。依赖Bash、Python3、Icarus/vvp、RISC-V GCC/objcopy/objdump/nm与sha256sum；不需要PDS或板卡。

```bash
bash validation/bus_flush/run.sh
```

CPU哈希不匹配即停止。脚本创建唯一输出目录，不覆盖原工程。生成24个小程序并运行432个配置，每个配置两轮全系统空闲复位启动。输出ELF、反汇编、固件、逐周期trace.csv、独立expected.json、summary.json及输入哈希；`python3 -B validation/bus_flush/check.py <输出目录>`可重查轨迹。

|维度|值|
|---|---|
|控制流|BEQ跳转/不跳转、BNE跳转/不跳转、JAL、JALR|
|旧store到分支的NOP数|0、1、3、5，不等于实际等待周期|
|AW/W顺序|地址先、数据先、同周期；每种均有真实VALID等待READY|
|AW/W都完成后的目标响应延迟|0、7、31；BVALID在最后一个握手后delay+1沿被观察到|
|命令准入等待|0、5；另有桥busy造成的正常阻塞|
|B接收背压|每笔BVALID至少保持4个采样周期，随后允许接收|

共6×4×3×3×2=432配置。目标延迟不是CPU响应总延迟，后者还包含AW/W和B接收等待。

## 判据

- 旧store必须完成且精确退休；分支正确目标store必须随后完成。BEQ/BNE不跳转时，落空路径的合法store也必须完成。
- 跳转后错误路径store的地址为专用禁止地址；连CPU有效请求出现都拒绝，不仅检查最后内存状态。异常入口发不同禁止地址，意外异常同样失败。
- Python按真实握手分别配对CPU命令、AW、W、B、CPU响应和真实store退休PC；检查槽位守恒、VALID与载荷在背压期间稳定、无重复、顺序与数据正确、成功响应之前不得退休。
- 根据ELF的tested_branch符号定位受测分支，只统计该PC在memory级发起重定向且桥busy的重叠周期，排除启动跳转及结束循环。零NOP的四种跳转场景，每个时序配置都必须观测到重叠。重叠周期数不等于分支条数。
- 目标效果以独立AW/W握手轨迹重建，不宣称验证实际DDR或外设存储阵列。CPU仅执行SW，写掩码必须1111；B响应固定成功。

负向对照包括真实固件把BEQ改为不跳转，从而发出禁止地址请求；以及检查器轨迹注入AW不稳定、提前退休、错误独立预期三项，必须由指定错误拒绝。

## 边界

仅RTL、单时钟、单槽、单beat、无Cache/预测，无读AR/R、多ID/burst、中断与总线错误交叉矩阵。两轮启动不是在途复位交叉证明。原CPU-WR-03的错误/排空隔离/复位测试应单独回归，不能冒充本轮分支×错误×复位全部交叉覆盖。

没有运行本夹具的PDS综合、综合网表、SDF或板卡；上一步寄存器矩阵的网表结果不能外推到本夹具。参见[实跑证据](../../evidence/bus-flush-20260927.md)。
