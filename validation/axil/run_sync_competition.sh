#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${AXIL_CPU_BUILD:?normal generated AXIL CPU build required}"
test "$(sha256sum "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" | cut -d ' ' -f1)" = d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-sync-competition.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -g2012 -s competition_tb -o "$out/sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$here/bridge.sv" "$here/cancel_target.sv" "$here/competition_tb.sv"
for k in 0 1 2 3 4 5 6;do
 for s in 3 7 11;do
  for m in 0 1;do
   fw="$out/fw_k${k}_s${s}_m${m}";mkdir "$fw"
   riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -T "$here/../cpu/sw/link.ld" -DSYNC_KIND="$k" -DWRITE=0 -DSOURCE="$s" -DMASKED="$m" "$here/competition.S" -o "$fw/program.elf"
   riscv64-unknown-elf-nm -n "$fw/program.elf" > "$fw/symbols.txt"
   riscv64-unknown-elf-objdump -d "$fw/program.elf" > "$fw/program.dis"
   riscv64-unknown-elf-objcopy -O binary "$fw/program.elf" "$fw/program.bin"
   python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$fw/program.bin" "$fw/firmware.hex"
   trigger=$(awk '$3=="fault_pc" {print $1}' "$fw/symbols.txt")
   if test "$k" -eq 6;then trigger=20000000;fi
   for p in 0 1 2;do
    dir="$out/k${k}_s${s}_m${m}_p${p}";mkdir "$dir"
    cp "$fw/firmware.hex" "$AXIL_CPU_BUILD/rtl/"*.bin "$dir/"
    (cd "$dir";vvp "$out/sim" +SOURCE="$s" +PHASE="$p" +CODE=0 +DELAY=3 +KIND="$k" +FAULTPC="$trigger") > "$dir/simulation.log" 2>&1
   done
   echo "TRACES_COMPLETE kind=$k source=$s masked=$m"
  done
 done
done
# Negative fixture: suppress the actual fetch bus error, keeping CPU/oracle/firmware intact.
python3 -B - "$here/competition_tb.sv" "$out/lost_fetch_error.sv" <<'PY'
import sys
from pathlib import Path
source=Path(sys.argv[1]).read_text()
old="ifault<=ip[31:14]!=18'h20000;"
assert source.count(old)==1
Path(sys.argv[2]).write_text(source.replace(old,"ifault<=1'b0;"))
PY
iverilog -g2012 -s competition_tb -o "$out/negative.sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$here/bridge.sv" "$here/cancel_target.sv" "$out/lost_fetch_error.sv"
dir="$out/negative_fetch";mkdir "$dir"
cp "$out/fw_k6_s3_m0/firmware.hex" "$AXIL_CPU_BUILD/rtl/"*.bin "$dir/"
set +e
(cd "$dir";vvp "$out/negative.sim" +SOURCE=3 +PHASE=0 +CODE=0 +DELAY=3 +KIND=6 +FAULTPC=20000000) > "$dir/simulation.log" 2>&1
status=$?
set -e
test "$status" -eq 0 || { test "$status" -eq 1 && grep -q 'Competition timeout' "$dir/simulation.log"; }
python3 -B "$here/check_sync_competition.py" "$out"
sha256sum "$here/competition.S" "$here/competition_tb.sv" "$here/check_sync_competition.py" "$here/run_sync_competition.sh" "$here/bridge.sv" "$here/cancel_target.sv" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$out"/fw_*/firmware.hex > "$out/inputs.sha256"
