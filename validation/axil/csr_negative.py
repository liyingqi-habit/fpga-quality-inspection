"""Undo each CSR repair in disposable pinned RTL; audit actual resulting traces."""
import csv
import hashlib
import json
import sys
from pathlib import Path
from check_csr import audit


def replace(text,before,after,count=1):
    if text.count(before)!=count:raise ValueError('RTL_MUTATION_CONTEXT')
    return text.replace(before,after)


action,source_arg,out_arg=sys.argv[1:]
source=Path(source_arg);out=Path(out_arg)
if action=='generate':
    if hashlib.sha256(source.read_bytes()).hexdigest()!='d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25':
        raise ValueError('CPU_HASH')
    text=source.read_text()
    readonly=replace(text,'(execute_CSR_READ_OPCODE && (! execute_CSR_WRITE_OPCODE))','execute_CSR_READ_OPCODE',8)
    readonly=replace(readonly,"(execute_CSR_WRITE_OPCODE && (execute_CsrPlugin_csrAddress[11 : 10] == 2'b11))","1'b0")
    align=replace(text,"assign CsrPlugin_mepcMask = 32'hfffffffc;","assign CsrPlugin_mepcMask = 32'hffffffff;")
    mpp=replace(text,"CsrPlugin_mstatus_MPP <= 2'b11;\n            CsrPlugin_mstatus_MIE <= CsrPlugin_mstatus_MPIE;",
                "CsrPlugin_mstatus_MPP <= 2'b00;\n            CsrPlugin_mstatus_MIE <= CsrPlugin_mstatus_MPIE;")
    for name,data in [('readonly',readonly),('align',align),('mpp',mpp)]:
        with (out/(name+'.v')).open('x') as handle:handle.write(data)
elif action=='check':
    summary={}
    for mode,fields in [('readonly',{'trap_count','mcause','mepc','rd'}),('align',{'readback'}),('mpp',{'post_mret_mpp'})]:
        failures=[]
        for suite in ('readonly','boundary'):
            path=source/suite
            rules=json.loads((path/'expected.json').read_text());cases=json.loads((path/'cases.json').read_text())
            symbols={p[2]:int(p[0],16) for line in (path/'symbols.txt').read_text().splitlines() if len(p:=line.split())==3}
            rows=[{k:int(v) for k,v in r.items()} for r in csv.DictReader((out/mode/suite/'csr.csv').open())]
            failures+=audit(rows,rules,cases,symbols,(path/'program.bin').read_bytes())
        actual={f['field'] for f in failures}
        if actual!=fields:raise ValueError(f'WRONG_RTL_FAILURE:{mode}:{actual}')
        summary[mode]=dict(rejected=True,mismatches=len(failures),fields=sorted(actual))
    (out/'audit.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('PASS: three actual CSR RTL repair reversals rejected: '+json.dumps(summary))
else:raise ValueError('ACTION')
