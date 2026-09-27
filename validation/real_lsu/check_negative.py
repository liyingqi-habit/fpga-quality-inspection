"""A disabled-wait *real CPU* must fail for early retirement, not an arbitrary error."""
from pathlib import Path
import sys
from check_real import read, check

rows = read(Path(sys.argv[1]))
try:
    check(rows, 0)
except ValueError as err:
    if str(err) != 'RETIRE_BEFORE_SUCCESS':
        raise SystemExit('Unexpected negative-control failure: ' + str(err))
    print('PASS: disabled-wait real CPU rejected: RETIRE_BEFORE_SUCCESS')
else:
    raise SystemExit('FAIL: disabled-wait CPU escaped')
