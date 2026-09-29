"""Keep all CSR mismatches visible; a detected DUT failure is never a PASS."""
import csv
import json
import sys
from pathlib import Path


def values(rule,symbols,binary):
    if 'symbol' in rule: return [symbols[rule['symbol']]]
    if 'opcode' in rule:
        offset=symbols[rule['opcode']]-0x80000000
        return [0,int.from_bytes(binary[offset:offset+4],'little')]
    if 'allowed' in rule:return rule['allowed']
    return None if rule['value'] is None else [rule['value']]


def audit(rows,rules,cases,symbols,binary):
    if len(rows)!=len(rules)*2:raise ValueError('RECORD_COUNT')
    failures=[]
    for i,row in enumerate(rows):
        slot=i%len(rules);rule=rules[slot]
        if row['boot']!=i//len(rules)+1 or row['addr']!=0x80004800+slot*4:
            raise ValueError('RECORD_ADDRESS')
        allowed=values(rule,symbols,binary);mask=rule.get('mask',0xffffffff)
        if allowed is not None and row['data']&mask not in allowed:
            failures.append(dict(boot=row['boot'],case=cases[slot//8]['name'],field=rule['name'],
                                 actual=hex(row['data']&mask),allowed=[hex(x) for x in allowed]))
    return failures


def main():
    root=Path(sys.argv[1]);all_failures=[];counts={};negative=0
    for suite in ('readonly','boundary'):
        path=root/suite
        rules=json.loads((path/'expected.json').read_text());cases=json.loads((path/'cases.json').read_text())
        if len(cases)!={'readonly':116,'boundary':79}[suite] or len(rules)!=len(cases)*8:
            raise ValueError('COVERAGE')
        symbols={p[2]:int(p[0],16) for line in (path/'symbols.txt').read_text().splitlines() if len(p:=line.split())==3}
        binary=(path/'program.bin').read_bytes()
        rows=[{k:int(v) for k,v in r.items()} for r in csv.DictReader((path/'csr.csv').open())]
        failures=audit(rows,rules,cases,symbols,binary)
        all_failures.extend(dict(suite=suite,**f) for f in failures)
        failed_cases={(f['boot'],f['case']) for f in failures}
        counts[suite]=dict(cases=len(cases),boots=2,records=len(rows),mismatches=len(failures),
                           failed_case_runs=len(failed_cases),passed_case_runs=len(cases)*2-len(failed_cases))
        # Synthetic golden rows test the checker independently, not DUT correctness.
        gold=[dict(boot=b,addr=0x80004800+i*4,data=(values(r,symbols,binary) or [0])[0])
              for b in (1,2) for i,r in enumerate(rules)]
        assert not audit(gold,rules,cases,symbols,binary)
        for field in ('trap_count','mcause','mepc','mtval','rd','readback','post_mret_mpp'):
            idx=next((i for i,r in enumerate(rules) if r['name']==field and values(r,symbols,binary) is not None),None)
            if idx is None:continue
            bad=[dict(r) for r in gold]
            bad[idx]['data']=0 if field=='post_mret_mpp' else 0xdeadbeef
            found=audit(bad,rules,cases,symbols,binary)
            if not any(f['field']==field for f in found):raise ValueError('NEGATIVE_ESCAPED:'+field)
            negative+=1
        for reason in ('RECORD_COUNT','RECORD_ADDRESS'):
            bad=[dict(r) for r in gold]
            if reason=='RECORD_COUNT':bad.pop()
            else:bad[0]['addr']+=4
            try:audit(bad,rules,cases,symbols,binary)
            except ValueError as error:
                if str(error)!=reason:raise
            else:raise ValueError('STRUCTURAL_NEGATIVE_ESCAPED')
            negative+=1
    result=dict(status='FAIL' if all_failures else 'PASS',suites=counts,checker_mutations=negative,failures=all_failures)
    (root/'audit.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='failures'}))
    for item in all_failures[:12]:print(json.dumps(item))
    return bool(all_failures)


if __name__=='__main__':sys.exit(main())
