from pathlib import Path
import sys
raw = Path(sys.argv[1]).read_bytes()
if len(raw)>16384: raise SystemExit('ROM overflow')
raw = raw.ljust(16384,b'\x00')
Path(sys.argv[2]).write_text(''.join(f'{int.from_bytes(raw[i:i+4], "little"):08x}\n' for i in range(0,len(raw),4)),encoding='ascii')
