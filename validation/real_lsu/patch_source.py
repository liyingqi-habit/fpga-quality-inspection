"""Apply guarded LSU experiment to an expendable, pinned upstream snapshot only."""
from pathlib import Path
import sys

path = Path(sys.argv[1]) / "src/main/scala/vexriscv/plugin/DBusSimplePlugin.scala"
text = path.read_text()
changes = [
    ("memoryTranslatorPortConfig : Any = null) extends Plugin",
     "memoryTranslatorPortConfig : Any = null, waitForWriteResponse : Boolean = false) extends Plugin"),
    ("  var dBus  : DBusSimpleBus = null",
     "  require(!waitForWriteResponse || (emitCmdInMemoryStage && !earlyInjection && !withLrSc && memoryTranslatorPortConfig == null))\n  var dBus  : DBusSimpleBus = null"),
    ("input(MEMORY_ENABLE) && !input(MEMORY_STORE) && (!dBus.rsp.ready",
     "input(MEMORY_ENABLE) && (!input(MEMORY_STORE) || Bool(waitForWriteResponse)) && !input(ALIGNEMENT_FAULT) && (!dBus.rsp.ready"),
    ("if(catchAccessFault) when(dBus.rsp.ready && dBus.rsp.error && !input(MEMORY_STORE))",
     "if(catchAccessFault) when(dBus.rsp.ready && dBus.rsp.error && (!input(MEMORY_STORE) || Bool(waitForWriteResponse)))"),
    ("          memoryExceptionPort.code := 5",
     "          memoryExceptionPort.code := (input(MEMORY_STORE) ? U(7) | U(5)).resized"),
]
for old, new in changes:
    if text.count(old) != 1:
        raise SystemExit("Pinned source mismatch: " + old)
    text = text.replace(old, new)
path.write_text(text)
print("Applied five guarded LSU experiment edits to disposable snapshot")
