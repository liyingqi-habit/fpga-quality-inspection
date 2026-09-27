# CSR 只读保护与合法取值边界：验证完成，DUT FAIL

2026-09-27，T06，基于 `c300444`。本次只新增验证夹具与证据，未修补生产 CPU、生成器、桥、SoC 或板级约束。失败不能改成 PASS，也不能把原有限回归通过解释为完整特权符合性。

## 实跑结果

固定 CPU SHA256 `6bc91de7f76e88d7edf056e8d30790c645876bf13e7177e7827c949ff12d141e`；UART SHA256 `12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e`。WSL Ubuntu、Icarus 12、RISC-V GCC 14.2、Python 3。

|套件|定向用例|启动数|通过的用例执行|失败的用例执行|字段不匹配|
|---|---:|---:|---:|---:|---:|
|只读访问/不存在CSR|116|2|64|168|552|
|合法取值边界|79|2|146|12|12|
|合计|195|各2次|210|180|564|

共3120条实际记录。`run_csr.sh` 最终退出码 **1**，`audit.json` 为 **FAIL**。564是字段不匹配次数，不是564个独立根因。17项检查器负向自测通过：13项字段破坏、4项条数/地址破坏；使用独立规则构造的黄金轨迹，仅证明检查器能拒绝指定错误，不冒充 CPU PASS。

最终运行标识 `axil-csr.o3x145AK`，保留两个套件的固件、反汇编、符号表、CSV、日志、audit.json、输入哈希。初轮 `axil-csr.V257Ok9X` 中，负向自测的突变值没有改变被掩码的MPP位，已修正；另外误要求 mtvec 支持 Vectored，经核实此配置 xtvecModeGen=false，改为合法 Direct-only 预期。这两项夹具修正后完整重跑，以下三个问题仍存在。

## 三个已复现问题

1. **只读 CSR 的读改写路径缺少写保护**：对 mvendorid/marchid/mimpid/mhartid、cycle/cycleh/instret/instreth 的写操作，rd非零的8种写入变体，每次启动64项都未产生应有的非法指令异常，并错误更新 rd。例如 `0xf11014f3`（`csrrw s1,mvendorid,zero`）在 `0x80000160` 执行后 trap_count=0、rd=0；应有 cause=2 且保留 rd 哨兵 `0x5a5aa5a5`。对身份CSR读回值仍为0，不应据此宣称“只读保护通过”。源码定位指向 CsrPlugin 的只读映射在存在读操作时清除 illegalAccess，没有同时拒绝写操作。
2. **mepc低位未规范化**：无C扩展、IALIGN=32，写 `0x80000101/102/103` 后原值读回；另一个有效ROM地址末端的三种低位也如此。应读出低两位为0；每次启动6项失败。生成 RTL 的 mepc 写入保留全部32位，与轨迹一致。本轮未让 mret 跳到这些非对齐值。
3. **mret后的MPP值不符合仅M模式配置**：确实触发异常并返回的16项rd=zero只读写入及4项未映射CSR访问，每次启动20项读到MPP=0，而仅M模式应为3。源码 mret 路径无条件将MPP写0。当前配置的实际 privilege 为固定M，不能据此推断CPU真的进入了U模式。

规范依据：[Zicsr 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html) 的零操作数/读写语义；[Machine-Level ISA 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html) 的 mepc 对齐、MPP 合法模式与返回规则。CSRRS/CSRRC使用x0可合法只读；使用非x0寄存器，即使内容为0，仍属于写操作。misa是可写地址上的固定WARL字段，不与架构只读地址混同。

## 已覆盖且未见不匹配的范围

- 8个只读CSR各4种不写入的访问形式；动态计数值不作精确数值比较。
- 7种 mscratch 全宽数据往返；7种 misa 写入后固定 `0x40001100`。
- mie 的32个单bit及全1写入，仅本配置三源使能位可读回。
- mstatus 的4种MPP输入×4种MIE/MPIE组合，写入后的所测字段合法；与前述mret后的问题区分。
- mepc 两个合法对齐地址可保持；mtvec 的8种先前模式/尝试模式组合始终读回 Direct。

## 复现与后续门槛

按 `validation/axil/README.md` 设置合法本地输入，运行 `bash validation/axil/run_csr.sh`。当前固定基线应报告FAIL；不要用忽略退出码或放宽断言的方法验收。案例按固件实际执行顺序记录 trap_count、mcause、精确符号mepc、mtval、rd、读回值、MPP；非法指令mtval允许0或实际指令编码，符合规范允许范围。

既有 `run_soc.sh` 重跑：`axil-soc.zwDujADj`，199结果×2启动与负向对照 PASS。`run_irq.sh` 重跑：`axil-irq.nmouDtVb`，144处理、14轨迹负向与真实优先级反转负向 PASS。它们没有覆盖本轮失败边界，不互相抵消。`bash -n`通过。

下一项：先修复上述三个明确问题，再生成新CPU哈希，重新执行CSR、SoC、中断优先级及真实在途取消回归；因CPU版本改变，PDS/网表/时序证据也需重跑。此轮未实施这些生产修复。

未覆盖全部4096 CSR、全部指令操作数组合、S/U权限切换、计数溢出/精确计数、PMP、嵌套或IRQ竞争；动态计数只读别名未核对背后计数器不变性。没有PDS、网表、SDF、上板或执行器操作。R07保持PARTIAL且存在已知FAIL，等待两名非作者审核，所有者手动合并。
