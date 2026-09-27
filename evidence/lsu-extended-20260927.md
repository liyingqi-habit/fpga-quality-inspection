# CPU-WR-05：在途复位与混合指令实跑

日期2026-09-27，父提交 `50f4144310bbfb5e9f4bb62d290fb4c0ca338d9a`；受测源码为首次加入本报告的提交。真实CPU与mini_soc RTL未修改。接口仍为限定实验，非整机ABI批准。

## 复现与输入

沿用[CPU-WR-04环境](../validation/lsu_soc/README.md)，设置REAL_LSU_BUILD、CPU_INPUT_ROOT、TMPDIR后执行：

```bash
bash validation/lsu_soc/run_extended.sh
bash validation/lsu_soc/run.sh
```

WSL Ubuntu / Icarus12.0 / RISC-V GCC14.2.0 / Python3。CPU SHA256 `63bb55e1bb43cc472699a09f1e2dbd674a68cab562da0df9d988b16f9b321140`，SoC SHA256 `95d528658edb507a1eb3e0ef94663fe7ea6fda25435f6967a3e0ff3cb4cc7046`，UART输入按脚本固定哈希检查。无受限输入或本机路径上传。

|新增受测输入|SHA256|
|---|---|
|reset.S|d8c5d44dc3d6ff5c0f5dae56d7addc2d0fbc3e425aeba890a3b406baf1218608|
|reset_tb.sv|b6882005c28ce684e6146d3053cb58b21971c39ae54a2a8742f8a440db3de964|
|mixed.S|05ac1e5a030b05d93bfcd4befe8fb1a40b178a981447f661e430d3e34c9a228a|
|mixed_tb.sv|164a43616c493d1140a9b828047e2043b5bfce361e7301cf44362d24a23d20e5|
|mixed_model.py|de27500435ddc4fdc18ca2f6d6397707b1cdf79fa305951653a9367ac2e58e99|

## 实际输出

扩展运行 `lsu-extended.5M1yW4mR`，退出0，无正向失败重试：

- 4类事务（RAM写、RAM读、非法读、非法写）×3个窗口（接受后、计数器剩1、响应已出现但尚未采样）×延迟7/31，共24例通过。
- 每例确实中断一笔已接受事务，校验 `accepted = responses + cancelled`、cancelled恰好1；复位清除pending/response/count，已接受RAM写保持，重启后重新完成程序与两次精确异常。写退休必须匹配成功响应及PC。
- 混合程序每轮32组输入，8个显式边界值+24个固定种子LCG值；独立Python整数模型产生256个预期RAM字。不是从RTL输出反推预期。
- 连续覆盖ROM load→移位/乘法/加法/XOR→有符号DIV/REM→RAM写读→SB/LB/LBU/SH/LH/LHU→数据相关BLT→JAL/JALR→校验和。分支数据15个负值、17个非负值，循环包含跳转和落空。
- 延迟0/7/31，各两轮；每轮256个结果字全部一致，192次读、321次写、513次响应，零错误响应。
- 两个负向对照按指定原因失败：强制残留响应被 `Stale response after reset` 拒绝；修改混合算术被 `Mixed reference mismatch` 拒绝。

原迁移全回归 `lsu-soc.3mrRNK1c` 退出0：启动、UART、27例两轮、异常/除法/UART等待复位、三档读写/子字/冲刷两轮及原5个负向对照通过。新增runner的Bash语法检查通过。

## 边界与交接

此处cancelled表示本地全局复位丢弃尚未消费的响应，不表示撤销目标写；不覆盖仍运行的DDR/DMA、CPU局部复位或跨时钟。未覆盖每个指令/数据组合、每个复位相位、随机种子空间，不是完整ISA认证。混合测试是RTL，不是综合后网表。

完成本步后进入隔离PDS综合和时序检查，结果须独立记录；仿真通过不代表时序闭合。两名非作者审核后由所有者手动合并。
