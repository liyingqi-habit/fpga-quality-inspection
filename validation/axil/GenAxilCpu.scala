package workshop

import spinal.core._
import vexriscv._
import vexriscv.plugin._

// Experimental configuration: real VexRiscv pipeline, no cache, single-slot bridge.
class WriteObserve(bus: DBusSimplePlugin) extends Plugin[VexRiscv] {
  override def build(p: VexRiscv): Unit = {
    import p._
    import p.config._
    out(UInt(32 bits)).setName("obs_cmd_pc") := memory.input(PC)
    out(Bool()).setName("obs_store_retire") :=
      writeBack.arbitration.isFiring && writeBack.input(bus.MEMORY_ENABLE) && writeBack.input(bus.MEMORY_STORE)
    out(UInt(32 bits)).setName("obs_retire_pc") := writeBack.input(PC)
    out(Bool()).setName("obs_retire_valid") := writeBack.arbitration.isFiring
  }
}
object GenAxilCpu extends App {
  val bus = new DBusSimplePlugin(catchAddressMisaligned=true, catchAccessFault=true,
    emitCmdInMemoryStage=true, waitForWriteResponse= !sys.env.get("WR_NEGATIVE_CONTROL").contains("1"))
  SpinalConfig(targetDirectory=sys.env("VEX_OUTPUT")).generateVerilog(new VexRiscv(
    VexRiscvConfig(plugins=List(
      new IBusSimplePlugin(resetVector=0x80000000L, cmdForkOnSecondStage=false,
        cmdForkPersistence=true, prediction=NONE, catchAccessFault=true, compressedGen=false),
      bus, new CsrPlugin(CsrPluginConfig.all(0x80000080L).copy(ebreakGen=true, misaExtensionsInit=0x1100, misaAccess=CsrAccess.READ_ONLY, mvendorid=0, marchid=0, mimpid=0)),
      new DecoderSimplePlugin(catchIllegalInstruction=true),
      new RegFilePlugin(regFileReadyKind=vexriscv.plugin.SYNC, zeroBoot=true),
      new IntAluPlugin, new SrcPlugin(separatedAddSub=false, executeInsertion=true),
      new FullBarrelShifterPlugin,
      new HazardSimplePlugin(bypassExecute=true,bypassMemory=true,bypassWriteBack=true,
        bypassWriteBackBuffer=true,pessimisticUseSrc=false,pessimisticWriteRegFile=false,
        pessimisticAddressMatch=false),
      new MulPlugin, new DivPlugin,
      new BranchPlugin(earlyBranch=false,catchAddressMisaligned=true),
      new WriteObserve(bus)
    ))).setDefinitionName("VexAxilCpu"))
}
