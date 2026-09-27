"""Audit actual firmware CSR records using spec-derived expected order, not RTL state."""
import argparse
import copy
import csv
import json
from pathlib import Path


def verify(rows,expected,symbols):
    if len(rows)!=len(expected)*2: raise ValueError('RECORD_COUNT')
    for index,row in enumerate(rows):
        slot=index%len(expected)
        if row['boot']!=index//len(expected)+1 or row['addr']!=0x80004800+slot*4:
            raise ValueError('RECORD_ADDRESS')
        rule=expected[slot]
        value=row['data']
        if rule['name']=='mepc':
            if value%4 or not symbols[rule['lo']]<=value<symbols[rule['hi']]: raise ValueError('MEPC_RANGE')
        elif value!=rule['value']: raise ValueError('VALUE:'+rule['name'])


def main():
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path);args=parser.parse_args()
    expected=json.loads((args.output/'expected.json').read_text())
    cases=json.loads((args.output/'cases.json').read_text())
    wanted={(tuple(s),bool(d),g) for s in ((11,3),(11,7),(3,7),(11,3,7)) for d in (0,1) for g in (0,1)}
    if len(cases)!=16 or {(tuple(c['sources']),c['defer_high'],c['gate']) for c in cases}!=wanted:
        raise ValueError('CASE_COVERAGE')
    if len(expected)!=460 or sum(r['name']=='mcause' for r in expected)!=36:raise ValueError('ORACLE_COVERAGE')
    symbols={parts[2]:int(parts[0],16) for line in (args.output/'symbols.txt').read_text().splitlines()
             if len(parts:=line.split())==3}
    negatives=0
    for delay in (0,9):
        rows=[{k:int(v) for k,v in row.items()} for row in csv.DictReader((args.output/f'delay{delay}/irq.csv').open())]
        verify(rows,expected,symbols)
        for name in ('mcause','pending_after_clear_one','trap_status','mtval','mret_restored_mie','no_duplicate_after_return','mepc'):
            bad=copy.deepcopy(rows);idx=next(i for i,r in enumerate(expected) if r['name']==name)
            bad[idx]['data']=0 if name=='mepc' else bad[idx]['data']^1
            try: verify(bad,expected,symbols)
            except ValueError as error:
                wanted='MEPC_RANGE' if name=='mepc' else 'VALUE:'+name
                if str(error)!=wanted: raise
            else: raise ValueError('NEGATIVE_ESCAPED')
            negatives+=1
    bad=[{k:int(v) for k,v in row.items()} for row in csv.DictReader((args.output/'negative/irq.csv').open())]
    try:verify(bad,expected,symbols)
    except ValueError as error:
        if str(error)!='VALUE:mcause':raise
    else:raise ValueError('RTL_PRIORITY_FAULT_ESCAPED')
    result=dict(status='PASS',cases_per_boot=16,boots=4,handler_entries=144,records_per_boot=len(expected),negative_audits=negatives,rtl_priority_fault_rejected=True)
    (args.output/'audit.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__=='__main__':main()
