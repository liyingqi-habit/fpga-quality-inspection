"""Create deliberately broken test-only variants in an unused output directory."""
from pathlib import Path
import sys
source = (Path(__file__).parent / 'bridge.sv').read_text()
output = Path(sys.argv[1])
mutations = {
    'lost_error': ('rsp_error<=writing ? bresp!=0 : rresp!=0;', "rsp_error<=1'b0;"),
    'stale_response': ('if(!cancelled && !reset_request)', "if(1'b1)"),
    'lost_backpressure': ('ar_sent && allow_response;', 'ar_sent;'),
}
for name, (before, after) in mutations.items():
    if source.count(before) != 1:
        raise ValueError(f'Fault context changed: {name}')
    target = output / f'{name}.sv'
    with target.open('x') as handle:
        handle.write(source.replace(before, after))
