#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${PDS_STAGE:?Actual AXIL PDS stage}"
: "${PDS_SIM_LIB:?Installed vendor simulation library}"
net="$PDS_STAGE/prj_tasks/syn_1/synthesize/mini_soc_first_board_syn.vm"
test "$(sha256sum "$net" | cut -d ' ' -f1)" = ce350750ba9a4c08a3fa48cb80e204d9718172a21f39d2d82454e4544bf0e325
test "$(sha256sum "$PDS_STAGE/firmware.hex" | cut -d ' ' -f1)" = 773e5cbb012284d43806645e83d90c6e879e85d6ea70ee806b855775839791b1
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-netlist.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
for mode in rtl gate poison negative;do
 dir="$out/$mode";mkdir "$dir"
 python3 -B "$here/program.py" "$dir"
 cmp "$dir/expected.hex" "$PDS_STAGE/expected.hex"
 cp "$PDS_STAGE/firmware.hex" "$PDS_STAGE/"*.bin "$dir/"
 if [ "$mode" = rtl ];then
  sources=("$PDS_STAGE/VexAxilCpu.v" "$PDS_STAGE/mini_uart.v" "$PDS_STAGE/bridge.sv" "$PDS_STAGE/soc.sv" "$PDS_STAGE/mini_soc_first_board.v")
 else
  sources=(-DGATE -y "$PDS_SIM_LIB" -Y .v "$net")
  if [ "$mode" = poison ];then sources+=(-DPOISON_RAW);fi
  if [ "$mode" = negative ];then sources+=(-DEXPECTATION_MUTATION);fi
 fi
 iverilog -g2012 -I "$dir" -s netlist_tb -M "$dir/dependencies.txt" -o "$dir/sim" "${sources[@]}" "$here/netlist_tb.sv" > "$dir/compile.log" 2>&1
 status=0
 (cd "$dir";vvp sim) > "$dir/simulation.log" 2>&1 || status=$?
 if [ "$mode" = negative ];then
  if [ "$status" = 0 ] || ! grep -q 'ISA result mismatch word=4' "$dir/simulation.log";then cat "$dir/simulation.log";exit 1;fi
  echo 'PASS: netlist independent oracle negative control';continue
 fi
 cat "$dir/simulation.log"
 test "$status" = 0
 grep -q 'PASS: integrated boot=2 results=199' "$dir/simulation.log"
done
cmp "$out/rtl/results.csv" "$out/gate/results.csv"
cmp "$out/rtl/results.csv" "$out/poison/results.csv"
while IFS= read -r file;do test ! -f "$file" || sha256sum "$file";done < "$out/gate/dependencies.txt" > "$out/dependencies.sha256"
echo 'PASS: RTL / synthesis netlist / collision-poison architectural results identical; no SDF or hardware'
