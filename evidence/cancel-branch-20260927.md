# CPU-WR-09：分支、错误响应与复位取消

父提交c5688f4dd59c6f0cb52f73f8693401500158cd0e；2026-09-27。真实CPU/原write_bridge不变，BEQ、BNE、JAL三种跳转各运行12场景，36场景通过；独立轨迹审计及9项负向对照通过。输出标识cancel-branch.qfYbuYEs，原始日志只留本地。

运行：设置REAL_LSU_BUILD为正常CPU-WR-03构建，执行`bash validation/real_lsu/run_cancel_branch.sh`。独立审计`python3 -B validation/real_lsu/check_cancel_branch.py <输出目录>`。CPU哈希在入口锁定。

覆盖AW先/W先/同周期、延迟成功、SLVERR/DECERR精确store异常、命令未接受复位、只接受AW或W时复位、等待错误B期间复位、错误B握手同沿复位、目标永不响应隔离。复位后重发得到成功响应；错误旧事务排空而不让旧退休/异常污染新CPU。目标政策是错误不修改内存，不能推断物理目标回滚。

先前check_real检查器只增加显式young_pc和错误计划参数，默认原行为不变；原12场景保存轨迹与12项负向审计再次通过。新增程序的年轻store PC为0x8000001c，错误路径地址0连有效请求出现都拒绝。检查实际CSR mcause/mepc/mtval、退休PC、目标内存、事务计数、AW/W/B稳定性、取消隔离与完成时序。

9个负向对照：每种分支分别注入复位沿旧退休、隔离提前丢失、错误异常cause，由指定错误拒绝。未运行JALR、读错误、所有分支间隔/复位周期穷举、PDS/网表/SDF/板卡。这一步完成不代表后续读写桥/中断/ISA/PDS阶段已完成。
