"""Negative controls mutate observed events, not checker expectations."""
import copy
import sys
from check_trace import check, read_trace, Violation

original = read_trace(sys.argv[1])
check(original)


def reject(name, select, changes, expected):
    rows = copy.deepcopy(original)
    row = next(r for r in rows if select(r))
    row.update(changes(row) if callable(changes) else changes)
    try:
        check(rows)
    except Violation as error:
        assert str(error) == expected, (name, str(error), expected)
        print("REJECTED:", name, expected)
    else:
        raise AssertionError("Mutation escaped: " + name)


reject("premature retirement", lambda r: r["case"] == 0 and r["issue"], {"retire": 1}, "RETIRE_WITHOUT_SUCCESS")
reject("error treated as success", lambda r: r["case"] == 3 and r["trap"], {"trap": 0, "retire": 1}, "RETIRE_WITHOUT_SUCCESS")
reject("wrong fault PC", lambda r: r["trap"], {"trap_pc": 0}, "TRAP_CONTEXT")
reject("wrong fault address", lambda r: r["trap"], {"trap_addr": 0xdead}, "TRAP_CONTEXT")
reject("wrong fault cause", lambda r: r["trap"], {"cause": 5}, "TRAP_CONTEXT")
reject("younger MMIO side effect", lambda r: r["case"] == 3 and r["issue"], {"young": 1}, "YOUNG_SIDE_EFFECT")
reject("release before old write drained", lambda r: r["case"] == 8 and r["reset"], {"release": 1}, "RESET_DRAIN")
reject("late old retirement", lambda r: r["case"] == 9 and r["release"], {"retire": 1}, "STALE_COMPLETION")
reject("AW changes under backpressure", lambda r: r["case"] == 2 and r["av"] and r["ar"], {"addr": 999}, "AW_STABILITY")
reject("W changes under backpressure", lambda r: r["case"] == 2 and r["wv"] and r["wr"], {"data": 0}, "W_STABILITY")
reject("B changes while blocked", lambda r: r["case"] == 0 and r["bv"] and r["br"], {"resp": 2}, "B_STABILITY")
reject("new work reuses quarantined slot", lambda r: r["case"] == 11 and r["reset"], {"issue": 1}, "SLOT_REUSE")
print("PASS: 12 negative controls rejected with expected reasons")
