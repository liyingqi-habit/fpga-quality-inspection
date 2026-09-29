# CPU-AXIL-09：RC1固定候选统一回归

日期：2026-09-27。冻结源提交 `1d86be3642daf0cca175e6c2066fc8b93406d0e6`。
本轮不修改CPU生成配置、生产CPU/桥/SoC或既有测试预期；新增统一入口、更新经审计网表哈希白名单并记录证据。提交RC1记录不等于团队审核通过。

## 固定输入

|输入|SHA256或版本|
|---|---|
|生成CPU，normal模式|d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25|
|mini_uart.v|12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e|
|SoC基线firmware.hex|773e5cbb012284d43806645e83d90c6e879e85d6ea70ee806b855775839791b1|
|候选FDC|cc4dda537a7c352392b9cdeebfbc08c7980a23a679247b5f8b69570f752cdebe|
|本次综合网表|8efd765ae42e010c993f8544b69be9c903a51bd1870be5f98e4aea6332f88352|
|PDS|2025.2 build211867，ADS，PG2L200H / -6 / FBB676|

`run_candidate.sh`核对固定提交的RTL/测试输入差异，逐套运行八个入口，并在结束复核输入SHA256。日志保留HEAD、候选提交、每套输出目录和前后输入摘要。文档、统一入口和单独审核的网表哈希入口不作为RTL输入版本差异；运行期间所有现存validation/axil文件（统一入口除外）仍做前后摘要检查。

## RTL统一实跑

首次完整输出 `axil-candidate.R1UGk8yJ`：八套均PASS，源差异为空，全部前后输入摘要一致。

统一入口完善文档/网表入口排除后再次完整运行 `axil-candidate.a8CVEAG1`：八套再次PASS，前后摘要再次一致。不是只对脚本做语法检查；两轮生产和RTL测试输入相同。

|套件|本次通过范围（细节沿用各独立证据，不扩大）|
|---|---|
|soc|199独立结果/启动，2次启动；预期突变必须失败|
|bridge|576组合、2种永不响应隔离、3实际RTL故障对照|
|irq|16配置、4次启动/配置、144次处理；14检查器负向、1优先级反转|
|csr|195用例各2次、3120记录；17检查器负向、3实际修复撤销|
|cancel|84场景、36轨迹负向、6实际RTL故障|
|competition|144配置/288启动、432处理；20检查器负向、2桥故障|
|sync_competition|126配置/252启动、378处理；140检查器负向、1取指错误抑制|
|nested|36正常/324局部复位配置、132非零pending保留；25检查器负向、2实际故障|

测试失败对照是预期的拒绝，不是忽略失败码。八套RTL不是八套网表回归；网表仅覆盖下面的基线固件。

## PDS与新综合网表实跑

隔离工程标识 `pds_axil_a4b63ea97e7e473dbba47b476339a1af`。执行现有run_pds.ps1，使用本轮soc输出 `axil-soc.FgWKMQJG`。compile、synthesize、dev_map、pnr、report_timing和save_project均成功，约3分30秒。

新旧网表完整diff共15行替换：7条生成时间注释和8条临时FDC路径注释；没有逻辑变化，层次探针保持不变。新精确SHA256加入allow-list，未放开任意网表；原始厂商网表/仿真库不公开上传。

`run_netlist.sh`输出 `axil-netlist.tcRZO2XQ`：RTL、实际综合网表、寄存器堆碰撞原始读值X注入均各2次启动，每次199结果通过，三份CSV逐字节相同。每轮网表两读口碰撞计数200/45；expected[4]变异以指定ISA mismatch拒绝。未修改厂商模型、没有SDF，不声称所有寄存器冲突程序都安全。

`check_pds.py <stage> --self-test`实际返回 `CONSTRAINED_PATHS_PASS_WITH_PROFILE_LIMITATIONS`、`board_status=NOT_VALIDATED`；negative_hold、missing_setup、failing_endpoint、no_clock四负向均拒绝。

|约束/指标|本次结果|
|---|---|
|sys_clk|37.037 ns / 27 MHz|
|slow setup / hold|27.178 / 0.063 ns|
|fast setup / hold|30.676 / 0.043 ns|
|slow recovery / removal / mpw|33.713 / 0.554 / 17.558 ns|
|fast recovery / removal / mpw|35.003 / 0.372 / 17.863 ns|
|setup/hold端点|29682；全部十类报告TNS=0、失败端点=0|
|LUT / registers / latches|5013 / 1506 / 0|
|DRM36K等效 / APM|5 / 4|

no_clock、loops、latch_loops、latchs为0；no_input_delay=3、io_min_max_delay_consistency=4、virtual_clock=1仍存在。工具Fmax行101.4302 MHz不是板级Fmax；未把异步例外和输出零延迟包装为完整闭合。

## 失败记录、限制与下一步

初次统一入口 `axil-candidate.7s2qMmu4`在WSL Git解析Windows工作树路径时失败，尚未运行测试；入口支持CANDIDATE_GIT指定Windows Git后重跑。另一次报告命令跨Shell丢失stage参数，读报告失败；显式传递路径后报告检查及网表套件通过。保留实际失败而不算CPU缺陷。

板级核对见[RC1板级清单](../docs/board/CPU_RC1_BOARD_AUDIT.md)。新达芬奇资料只补强Logos2通用规则；MINI实物SCBV/供电仍缺依据。综合SoC局部cancel固定0，专用嵌套/复位夹具未迁入板级；基线ROM依赖测试台判分和IRQ激励，不是板级验收固件。

未做：全套指令/特权认证、Cache/预测、DDR/DMA、SDF、bitstream、上板、执行器。下一项为独立板级串口验收固件及离线验证，同时补全电源/版号/SCBV和复位约束准入材料。两名非作者审核，所有者手动合并；本轮不合并main。
