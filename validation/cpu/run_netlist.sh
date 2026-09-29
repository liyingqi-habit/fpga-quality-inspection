#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${CPU_NETLIST:?Set CPU_NETLIST to the vetted PDS synthesis netlist}"
: "${PDS_SIM_LIB:?Set PDS_SIM_LIB to the installed vendor simulation directory}"
net=$(realpath "$CPU_NETLIST")
lib=$(realpath "$PDS_SIM_LIB")
expected=4bcec54e7264f8da13f020d1794e2c5b5cb68a0ccb8ee9218285e2bfd666aa0d
test "$(sha256sum "$net" | cut -d ' ' -f1)" = "$expected"
test -f "$lib/GTP_GRS.v"
out=$(mktemp -d "${TMPDIR:-/tmp}/cpu-netlist-regression.XXXXXXXX")
echo "OUTPUT=$out"
iverilog -g2012 -s cpu_netlist_tb -y "$lib" -Y .v -M "$out/dependencies.txt" \
  -o "$out/sim" "$net" "$here/tb/cpu_netlist_tb.sv" > "$out/compile.log" 2>&1
(cd "$out"; vvp sim) | tee "$out/simulation.log"
grep -q '^PASS: synthesis netlist functional regression' "$out/simulation.log"
echo 'LIMITS: functional only, no SDF or board validation'
