#!/usr/bin/env bash
# Frozen production candidate; no bitstream or hardware actions.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
: "${AXIL_CPU_BUILD:?fixed generated CPU directory required}"
: "${CPU_INPUT_ROOT:?legal UART input directory required}"
candidate=1d86be3642daf0cca175e6c2066fc8b93406d0e6
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-candidate.XXXXXXXX")
echo "CANDIDATE_OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
cd "$root"
git_bin=${CANDIDATE_GIT:-git}
git_root=$root
if [[ "$git_bin" == *.exe ]];then git_root=$(wslpath -w "$root");git_root=${git_root//\\//};fi
"$git_bin" -c "safe.directory=$git_root" -C "$git_root" rev-parse HEAD > "$out/execution-head.txt"
printf '%s\n' "$candidate" > "$out/candidate-source.txt"
# Freeze RTL/test inputs. Documentation and the separately audited netlist hash
# allow-list are not RTL-suite inputs. Any other tracked input change fails.
"$git_bin" -c "safe.directory=$git_root" -C "$git_root" diff --exit-code "$candidate" -- validation/axil ':!validation/axil/run_candidate.sh' ':!validation/axil/run_netlist.sh' ':!validation/axil/*.md' > "$out/source-diff.txt"
find validation/axil -maxdepth 1 -type f ! -name run_candidate.sh -print0 | sort -z | xargs -0 sha256sum > "$out/validation-before.sha256"
sha256sum "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$CPU_INPUT_ROOT/rtl/mini_uart.v" > "$out/external-before.sha256"
printf 'suite\tstatus\toutput\n' > "$out/suites.tsv"
for suite in soc bridge irq csr cancel competition sync_competition nested;do
 echo "START_SUITE=$suite"
 bash "$here/run_${suite}.sh" > "$out/$suite.log" 2>&1
 folder=$(sed -n 's/^OUTPUT=//p' "$out/$suite.log" | head -n 1)
 test -n "$folder" && test -d "$folder"
 printf '%s\tPASS\t%s\n' "$suite" "$folder" >> "$out/suites.tsv"
 echo "PASS_SUITE=$suite OUTPUT=$folder"
done
sha256sum -c "$out/validation-before.sha256" > "$out/validation-after.log"
sha256sum -c "$out/external-before.sha256" > "$out/external-after.log"
echo 'PASS: eight RTL suites; frozen inputs unchanged. PDS/netlist and board audit remain separate.'
