#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-bridge.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -g2012 -s bridge_tb -o "$out/sim" "$here/bridge.sv" "$here/bridge_tb.sv"
vvp "$out/sim"
python3 -B "$here/negative_bridge.py" "$out"
for mode in lost_error stale_response lost_backpressure;do
  iverilog -g2012 -s bridge_tb -o "$out/$mode.sim" "$out/$mode.sv" "$here/bridge_tb.sv"
  status=0
  vvp "$out/$mode.sim" > "$out/$mode.log" 2>&1 || status=$?
  case "$mode" in
    lost_error) reason='wrong completion';;
    stale_response) reason='stale completion after cancel';;
    lost_backpressure) reason='response backpressure';;
  esac
  if [ "$status" = 0 ] || ! grep -q "$reason" "$out/$mode.log";then cat "$out/$mode.log";exit 1;fi
  echo "PASS: rejected $mode with $reason"
done
sha256sum "$here/bridge.sv" "$here/bridge_tb.sv" > "$out/inputs.sha256"
