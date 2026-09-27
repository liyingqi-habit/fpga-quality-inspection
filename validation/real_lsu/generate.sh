#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${VEX_SOURCE:?Set VEX_SOURCE to the pinned legal upstream checkout}"
: "${SBT_LAUNCH:?Set SBT_LAUNCH to the installed sbt launcher jar}"
: "${SBT_REPOSITORIES:?Set SBT_REPOSITORIES to the local sbt repository configuration}"
: "${REAL_LSU_BUILD:?Set REAL_LSU_BUILD to an unused output directory}"
sha=7445c66bb4bb508f096c1d4814b4fae1ea8643c0
test "$(git -c safe.directory="$VEX_SOURCE" -C "$VEX_SOURCE" rev-parse HEAD)" = "$sha"
test ! -e "$REAL_LSU_BUILD"
mkdir -p "$REAL_LSU_BUILD/source" "$REAL_LSU_BUILD/rtl"
if [ "${WR_NEGATIVE_CONTROL:-0}" = 1 ]; then
  printf 'negative\n' > "$REAL_LSU_BUILD/mode.txt"
else
  printf 'normal\n' > "$REAL_LSU_BUILD/mode.txt"
fi
sha256sum "$here/GenWriteResponse.scala" "$here/patch_source.py" "$SBT_LAUNCH" > "$REAL_LSU_BUILD/generator-inputs.sha256"
git -c safe.directory="$VEX_SOURCE" -C "$VEX_SOURCE" archive "$sha" | tar -x -C "$REAL_LSU_BUILD/source"
python3 -B "$here/patch_source.py" "$REAL_LSU_BUILD/source"
export VEX_OUTPUT="$REAL_LSU_BUILD/rtl"
cd "$REAL_LSU_BUILD/source"
java -Xmx2G -XX:ActiveProcessorCount=4 -Dsbt.version=1.10.7 -Dsbt.override.build.repos=true \
  -Dsbt.repository.config="$SBT_REPOSITORIES" -Dsbt.supershell=false \
  -jar "$SBT_LAUNCH" "set Compile / unmanagedSourceDirectories += file(\"$here\")" \
  'runMain workshop.GenWriteResponse' 2>&1 | tee "$REAL_LSU_BUILD/generate.log"
sha256sum "$VEX_OUTPUT"/* > "$REAL_LSU_BUILD/generated.sha256"
