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
     'mepc := mepcCaptureStage.input(PC)\n              mtval := 0\n              if(exceptionPortCtrl')):
    if source.count(before)!=1:raise ValueError('Pinned CSR patch context changed')
    source=source.replace(before,after)
path.write_text(source)
print('Applied ECALL/EBREAK/interrupt mtval-zero fixes to disposable snapshot')
