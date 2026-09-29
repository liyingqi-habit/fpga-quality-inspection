# BA-0.1 board acceptance draft — 2026-09-29

Status: **UNVERIFIED / BUILD_ONLY**. No functional execution evidence.

Base commit: `f44357ab527d7f4ea9cccc64b6cb24ee5b701053`.
Scope: isolated firmware and operating instructions; existing PDS projects and
firmware images were not replaced. User explicitly paused simulation.

## Checks actually performed

- `bash -n firmware/board_acceptance/build.sh`: exit 0.
- `bash firmware/board_acceptance/build.sh` under WSL with existing RISC-V GCC,
  binutils and Python: exit 0. Fresh private output directory per build.
- Final size: text 1956 bytes, data 0, bss 0; ROM capacity 16384 bytes.
- Build gates: `_start=80000000`, data/bss zero, padded hex has 4096 lines.
- Disassembly inspected: reset entry, fallback trap entry at 0x80000080,
  aligned trap vector at 0x80000424, exception sites and mret instructions.
- No stack is used by this assembly. Full-RAM self-test is destructive.
- Two builds produced the same ROM hex SHA256. ELF hashes differed across
  fresh output directories; this is not claimed as a reproducible ELF build.

|Input/output|SHA256|
|---|---|
|start.S|50b9d0492a6835209da19e63d4368f0921b4bd953a60f0d329288e945cbd0951|
|build.sh|bf7848ec78d2cbeaa07b3148e7ea7b24830b00d068cfea336c6626c74dbf9d6c|
|shared link.ld|50dbe092b7c1aa871e01ab084815147e72956b27780d96036ed23505d8393915|
|shared bin_to_hex.py|917f3b528be086ff5e7ad6c3194adcb17ffea64dd7e4b47cc334eb3df1ae78c5|
|final firmware.elf|035058cc4a53ba1c62358289d576df55f6fa9d0057d5827cbf74b0cd45b16c87|
|firmware.hex|7f5d7e11c7cba256c980ef6ac3193f435748c26cfc1d8df9287d20f5cffd6bbd|

## NOT_RUN

UART decoding; RAM normal/fault tests; ECALL/illegal/EBREAK execution;
software/timer/external interrupt execution; key timeout/bounce/held cases;
reset during execution; UART busy timeout; RTL and netlist regressions;
PDS rebuild/timing for this firmware; bitstream generation; board download;
physical UART/key/reset/power-cycle acceptance. All remain NOT_RUN.

Expected PASS strings in source and instructions are specifications, not results.
Existing RC1 results do not validate this newly added firmware.

## Next gate

When simulation resumes, independently decode UART and exercise normal, fault,
timeout and reset cases. Then rebuild the same candidate through netlist/PDS,
complete board preconditions and two non-author reviews, and perform supervised
hardware acceptance. No actuator control is included.
