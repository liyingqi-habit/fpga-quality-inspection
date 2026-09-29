"""Independent literal UART oracle. Never derives expected text from firmware."""
import argparse
import re
from pathlib import Path

BANNER = ["CPU BOARD ACCEPTANCE BA-0.2 UNVERIFIED",
          "CPU=RC1-d0e23f3c CLK=27000000 UART=115200-8N1",
          "BOOT RAM-DESTRUCTIVE NO-ACTUATORS"]
RAM = "PASS RAM 0x80004000..0x80007FFF 4 address-XOR passes"
EXC = "PASS EXCEPTIONS ECALL ILLEGAL EBREAK"
SOFT = "PASS IRQ SOFTWARE"
TIMER = "PASS IRQ TIMER"
RELEASE = "WAIT RELEASE KEY1 (30s timeout, 100ms stable)"
PRESS = "WAIT PRESS KEY1 ONCE (30s timeout)"
FULL = BANNER + [RAM, EXC, SOFT, TIMER, RELEASE, PRESS, RELEASE,
               "PASS IRQ EXTERNAL PRESS/RELEASE",
               "SELFTEST PASS (limited tests only)",
               "MANUAL: KEY0 reset -> repeat entire test; then cold power cycle -> repeat."]

def check(text, case):
    epochs = re.split(r"\n@@RESET \d+\n", text.replace("\r", ""))
    assert len(epochs) == (3 if case in (5, 6, 8, 13) else 2), "reset count"
    assert not epochs[0].strip(), "unexpected pre-reset data"
    lines = [x for x in epochs[-1].splitlines() if x]
    if case in (0, 5, 6, 8, 11, 13):
        assert lines == FULL, f"normal transcript mismatch: {lines!r}"
        if case == 6:
            assert [x for x in epochs[1].splitlines() if x] == FULL[:9], "pre-reset key phase"
        if case == 8:
            assert [x for x in epochs[1].splitlines() if x] == BANNER+[RAM], "pre-reset trap phase"
        if case == 13:
            assert [x for x in epochs[1].splitlines() if x] == FULL[:5], "pre-reset IRQ phase"
    elif case == 7:
        assert not lines, "busy UART must not emit success or other bytes"
    else:
        prefixes = {1:BANNER, 2:FULL[:5], 3:FULL[:9], 4:FULL[:10], 9:FULL[:6], 10:FULL[:8], 12:FULL[:4]}
        codes = {1:"10", 2:"30", 3:"41", 4:"42", 9:"31", 10:"40", 12:"E0"}
        assert lines[:-1] == prefixes[case], "failure phase mismatch"
        assert re.fullmatch(r"FAIL code=0x000000"+codes[case]+r" mcause=0x[0-9A-F]{8} mepc=0x[0-9A-F]{8} mtval=0x[0-9A-F]{8}", lines[-1]), "failure diagnostic mismatch"
        if case == 12:
            assert "mcause=0x00000003" in lines[-1], "wrong-cause injection not observed"

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("log", type=Path)
    ap.add_argument("case", type=int)
    ap.add_argument("--self-test", action="store_true")
    args=ap.parse_args()
    text=args.log.read_text(encoding="ascii")
    check(text,args.case)
    if args.self_test:
        assert args.case==0
        mutations=[text.replace("PASS RAM", "FAIL RAM"),
                   text.replace(EXC+"\n", ""),
                   text.replace("BA-0.2", "BA-9.9"),
                   text+"SELFTEST PASS (limited tests only)\n",
                   text.replace(SOFT, "WRONG IRQ"),
                   text.replace(PRESS+"\n", ""),
                   text.replace("@@RESET 1", "@@RESET 1\n@@RESET 2")]
        for mutant in mutations:
            try: check(mutant,0)
            except (AssertionError,IndexError): pass
            else: raise AssertionError("oracle accepted mutant")
        print(f"PASS oracle mutations={len(mutations)}")
    print(f"PASS serial oracle case={args.case}")

if __name__=="__main__":main()
