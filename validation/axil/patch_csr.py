"""Guarded fixes in disposable pinned source; never edit the upstream checkout."""
from pathlib import Path
import sys
path=Path(sys.argv[1])/'src/main/scala/vexriscv/plugin/CsrPlugin.scala'
source=path.read_text()
for before,after in (
    ('selfException.valid := True\n          switch(privilege)',
     'selfException.valid := True\n          selfException.badAddr := 0\n          switch(privilege)'),
    ('selfException.code := 3\n        }',
     'selfException.code := 3\n          selfException.badAddr := 0\n        }'),
    ('mepc := mepcCaptureStage.input(PC)\n              if(exceptionPortCtrl',
     'mepc := mepcCaptureStage.input(PC)\n              mtval := 0\n              if(exceptionPortCtrl'),
    ('if (withRead) illegalAccess.clearWhen(input(CSR_READ_OPCODE))',
     'if (withRead) illegalAccess.clearWhen(input(CSR_READ_OPCODE) && !input(CSR_WRITE_OPCODE))'),
    ('forceFail setWhen(privilege < csrAddress(9 downto 8).asUInt)',
     'forceFail setWhen(privilege < csrAddress(9 downto 8).asUInt)\n          forceFail setWhen(input(CSR_WRITE_OPCODE) && csrAddress(11 downto 10) === B"11")'),
    ('mepcAccess(CSR.MEPC, mepc)',
     'val mepcMask = U((BigInt(1) << xlen) - (if(pipeline.config.withRvc) 2 else 4), xlen bits)\n'
     '      if(mepcAccess.canRead) r(CSR.MEPC, mepc & mepcMask)\n'
     '      if(mepcAccess.canWrite) onWrite(CSR.MEPC){ mepc := writeData().asUInt & mepcMask }'),
    ('mstatus.MPP := U"00"',
     'mstatus.MPP := U(if(userGen) 0 else if(supervisorGen) 1 else 3, 2 bits)')):
    if source.count(before)!=1:raise ValueError('Pinned CSR patch context changed')
    source=source.replace(before,after)
path.write_text(source)
print('Applied guarded mtval, read-only access, mepc alignment and MRET MPP fixes to disposable snapshot')
