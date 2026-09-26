#!/usr/bin/env bash
# External inputs remain local. Never modify the supplied workshop directory.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${CPU_INPUT_ROOT:?Set CPU_INPUT_ROOT to the local vetted workshop directory}"
input=$(cd "$CPU_INPUT_ROOT" && pwd)
(cd "$input"; sha256sum --strict -c "$here/inputs.sha256")
stage=$(mktemp -d "${TMPDIR:-/tmp}/cpu-public-regression.XXXXXXXX")
echo "STAGE=$stage"
mkdir -p "$stage/rtl/generated"
cp "$input/rtl/mini_soc.v" "$input/rtl/mini_uart.v" "$stage/rtl/"
cp "$input/rtl/generated/VexRiscv.v" "$input/rtl/generated/VexRiscv.v_toplevel_RegFilePlugin_regFile.bin" "$stage/rtl/generated/"
cp -R "$here/sw" "$here/tb" "$here/scripts" "$stage/"
bash "$stage/scripts/test_cpu_directed.sh"
bash "$stage/scripts/test_cpu_traps.sh"
echo "PASS: public test package regression; evidence retained in $stage/build"
