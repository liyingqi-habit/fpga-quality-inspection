#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${AXIL_CPU_BUILD:?normal generated AXIL CPU build required}"
test "$(sha256sum "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" | cut -d ' ' -f1)" = d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-competition.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -g2012 -s competition_tb -o "$out/sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$here/bridge.sv" "$here/cancel_target.sv" "$here/competition_tb.sv"
for w in 0 1;do
 for s in 3 7 11;do
  for m in 0 1;do
   fw="$out/fw_w${w}_s${s}_m${m}";mkdir "$fw"
   riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -T "$here/../cpu/sw/link.ld" -DWRITE="$w" -DSOURCE="$s" -DMASKED="$m" "$here/competition.S" -o "$fw/program.elf"
   riscv64-unknown-elf-nm -n "$fw/program.elf" > "$fw/symbols.txt"
   riscv64-unknown-elf-objdump -d "$fw/program.elf" > "$fw/program.dis"
   riscv64-unknown-elf-objcopy -O binary "$fw/program.elf" "$fw/program.bin"
   python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$fw/program.bin" "$fw/firmware.hex"
   for p in 0 1 2;do
    for c in 2 3;do
     for d in 3 17;do
      dir="$out/w${w}_s${s}_m${m}_p${p}_c${c}_d${d}";mkdir "$dir"
      cp "$fw/firmware.hex" "$AXIL_CPU_BUILD/rtl/"*.bin "$dir/"
      (cd "$dir";vvp "$out/sim" +SOURCE="$s" +PHASE="$p" +CODE="$c" +DELAY="$d") > "$dir/simulation.log" 2>&1
     done
    done
   done
   echo "TRACES_COMPLETE write=$w source=$s masked=$m"
  done
 done
done
# Actual bridge mutation, kept outside source tree; oracle and firmware unchanged.
python3 -B - "$here/bridge.sv" "$out/lost_error.sv" <<'PY'
import sys
from pathlib import Path
source=Path(sys.argv[1]).read_text()
old='rsp_error<=writing ? bresp!=0 : rresp!=0;'
assert source.count(old)==1
Path(sys.argv[2]).write_text(source.replace(old,"rsp_error<=1'b0;"))
PY
iverilog -g2012 -s competition_tb -o "$out/negative.sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$out/lost_error.sv" "$here/cancel_target.sv" "$here/competition_tb.sv"
for w in 0 1;do
 dir="$out/negative_w$w";mkdir "$dir"
 cp "$out/fw_w${w}_s3_m0/firmware.hex" "$AXIL_CPU_BUILD/rtl/"*.bin "$dir/"
 set +e
 (cd "$dir";vvp "$out/negative.sim" +SOURCE=3 +PHASE=0 +CODE=2 +DELAY=17) > "$dir/simulation.log" 2>&1
 status=$?
 set -e
 # Error suppression omits the expected exception, so firmware may time out.
 test "$status" -eq 0 || { test "$status" -eq 1 && grep -q 'Competition timeout' "$dir/simulation.log"; }
done
python3 -B "$here/check_competition.py" "$out"
sha256sum "$here/competition.S" "$here/competition_tb.sv" "$here/check_competition.py" "$here/run_competition.sh" "$here/bridge.sv" "$here/cancel_target.sv" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$out"/fw_*/firmware.hex > "$out/inputs.sha256"
