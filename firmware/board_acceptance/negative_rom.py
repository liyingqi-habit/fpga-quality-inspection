"""Test-only mutant: omit the three startup diagnostic CSR writes."""
import sys
from pathlib import Path

source, symbols, output = map(Path, sys.argv[1:])
entries = [line.split() for line in symbols.read_text().splitlines()]
address = int(next(x[0] for x in entries if len(x)==3 and x[2]=="diagnostics_init"), 16)
words = source.read_text(encoding="ascii").splitlines()
index = (address-0x80000000)//4
assert words[index:index+3] == ["34101073", "34201073", "34301073"], "unexpected diagnostic init code"
words[index:index+3] = ["00000013"]*3
output.write_text("\n".join(words)+"\n", encoding="ascii")
