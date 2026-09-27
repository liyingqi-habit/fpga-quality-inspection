"""Reverse priority in a disposable generated RTL copy, never the legal input."""
from pathlib import Path
import sys

source=Path(sys.argv[1]).read_text()
blocks=[]
for suffix,code in (('',"0111"),('_1',"0011"),('_2',"1011")):
    blocks.append(f"      if(when_CsrPlugin_l1304{suffix}) begin\n"
                  f"        CsrPlugin_interrupt_code <= 4'b{code};\n"
                  "        CsrPlugin_interrupt_targetPrivilege <= 2'b11;\n"
                  "      end\n")
before=''.join(blocks)
if source.count(before)!=1:raise ValueError('Pinned RTL priority context changed')
with Path(sys.argv[2]).open('x') as handle:
    handle.write(source.replace(before,''.join(reversed(blocks))))
