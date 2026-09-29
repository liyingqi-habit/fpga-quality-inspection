#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${PDS_STAGE:?Actual AXIL PDS stage}"
: "${PDS_SIM_LIB:?Installed vendor simulation library}"
net="$PDS_STAGE/prj_tasks/syn_1/synthesize/mini_soc_first_board_syn.vm"
# RC1 rebuild differs only in generated date and temporary FDC path comments.
# Keep an exact allow-list: do not silently accept an arbitrary new netlist.
case "$(sha256sum "$net" | cut -d ' ' -f1)" in
  4cf1fb1932d73a55b954a5929049d9adeda5f6bda85402c11273f23d68eae46d|8efd765ae42e010c993f8544b69be9c903a51bd1870be5f98e4aea6332f88352) ;;
  *) echo 'Unreviewed synthesis netlist hash' >&2; exit 1 ;;
esac
test "$(sha256sum "$PDS_STAGE/VexAxilCpu.v" | cut -d ' ' -f1)" = d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25
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
