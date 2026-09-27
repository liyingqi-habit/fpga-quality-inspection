#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-bridge.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -g2012 -s bridge_tb -o "$out/sim" "$here/bridge.sv" "$here/bridge_tb.sv"
vvp "$out/sim"
sha256sum "$here/bridge.sv" "$here/bridge_tb.sv" > "$out/inputs.sha256"
