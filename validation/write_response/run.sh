#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d "${TMPDIR:-/tmp}/write-response.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -V 2>&1 | head -n 2 || true
python3 --version
sha256sum "$here/target.sv" "$here/driver_tb.sv" "$here/check_trace.py" "$here/test_mutations.py" > "$out/inputs.sha256"
iverilog -g2012 -s driver_tb -o "$out/sim" "$here/target.sv" "$here/driver_tb.sv"
(cd "$out"; vvp sim)
python3 -B "$here/check_trace.py" "$out/trace.csv"
python3 -B "$here/test_mutations.py" "$out/trace.csv"
echo 'LIMITS: synthetic verification infrastructure only; no CPU/LSU under test'
