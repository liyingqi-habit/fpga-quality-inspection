"""Independent bus-event scoreboard; never imports the target or driver logic.

Checks this fixture's contract, not full AXI conformance or real CPU retirement.
"""
import csv
import sys

DELAYS = [0, 7, 31, 9, 3, 0, 8, 8, 15, 2, 0, 0]
RESPONSES = [0, 0, 0, 2, 3, 0, 0, 0, 0, 2, 0, 0]
CANCELLED = {5, 6, 7, 8, 9, 11}


class Violation(ValueError):
    pass


def require(condition, code):
    if not condition:
        raise Violation(code)


def read_trace(path):
    with open(path, newline="", encoding="ascii") as stream:
        return [{k: int(v) for k, v in row.items()} for row in csv.DictReader(stream)]


def check(rows):
    active = None
    seen, closed = set(), set()
    held_aw = held_w = held_b = None
    last_cycle = -1
    for row in rows:
        require(row["cycle"] > last_cycle, "CYCLE_ORDER")
        last_cycle = row["cycle"]
        if held_aw is not None:
            require(row["av"] and row["addr"] == held_aw, "AW_STABILITY")
        if held_w is not None:
            require(row["wv"] and (row["data"], row["strb"]) == held_w, "W_STABILITY")
        if held_b is not None:
            require(row["bv"] and row["resp"] == held_b, "B_STABILITY")
        held_aw = row["addr"] if row["av"] and not row["ar"] else None
        held_w = (row["data"], row["strb"]) if row["wv"] and not row["wr"] else None
        held_b = row["resp"] if row["bv"] and not row["br"] else None

        if row["issue"]:
            require(active is None, "SLOT_REUSE")
            ident = row["case"]
            require(ident in range(12) and ident not in seen, "ISSUE_ID")
            require(row["pc"] == 0x80000100 + 4*ident and row["addr"] == 4*ident, "ISSUE_CONTEXT")
            require(not row["reset"], "ISSUE_DURING_RESET")
            seen.add(ident)
            active = dict(id=ident, pc=row["pc"], addr=row["addr"], epoch=row["epoch"],
                          aw=None, w=None, b=False, outcome=False, cancel=False,
                          reset_cycle=None, b_stalls=0)
        if active is None:
            require(not any((row["av"] and row["ar"], row["wv"] and row["wr"],
                             row["bv"], row["retire"], row["trap"], row["release"])), "ORPHAN_EVENT")
            continue
        ident = active["id"]
        require(row["case"] == ident, "CASE_CHANGED")
        if row["reset"]:
            require(not active["cancel"], "DUPLICATE_RESET")
            phase = (active["aw"] is not None, active["w"] is not None)
            require(phase == {5: (False, False), 6: (True, False),
                              7: (False, True), 8: (True, True),
                              9: (True, True), 11: (True, True)}.get(ident), "RESET_PHASE")
            if ident == 9:
                require(row["bv"] and row["br"], "RESET_B_EDGE")
            else:
                require(not row["bv"], "RESET_WAIT_PHASE")
            active["cancel"] = True
            active["reset_cycle"] = row["cycle"]
        if row["av"] and row["ar"]:
            require(active["aw"] is None, "DOUBLE_AW")
            require(row["addr"] == active["addr"], "AW_CONTEXT")
            active["aw"] = row["cycle"]
        if row["wv"] and row["wr"]:
            require(active["w"] is None, "DOUBLE_W")
            require(row["data"] == 0xAABBCC00 + ident and row["strb"] == 5, "W_CONTEXT")
            active["w"] = row["cycle"]
        if row["bv"]:
            if not row["br"]:
                active["b_stalls"] += 1
            require(active["aw"] is not None and active["w"] is not None, "B_WITHOUT_REQUEST")
            require(ident != 11, "UNEXPECTED_RESPONSE")
            require(row["cycle"] > max(active["aw"], active["w"])+DELAYS[ident], "RESPONSE_TOO_EARLY")
            require(row["resp"] == RESPONSES[ident], "RESPONSE_CODE")
            if row["br"]:
                require(not active["b"], "DOUBLE_B")
                active["b"] = True
        # A handshake and CPU reset on the same edge cancels architectural completion.
        if row["retire"] or row["trap"]:
            require(not active["cancel"] and row["epoch"] == active["epoch"], "STALE_COMPLETION")
            require(not active["outcome"], "DOUBLE_OUTCOME")
            require(not (row["retire"] and row["trap"]), "CONFLICT_OUTCOME")
            if row["retire"]:
                require(active["b"] and RESPONSES[ident] == 0, "RETIRE_WITHOUT_SUCCESS")
                require(row["pc"] == active["pc"], "RETIRE_CONTEXT")
            else:
                require(active["b"] and RESPONSES[ident] != 0, "TRAP_WITHOUT_ERROR")
                require((row["trap_pc"], row["trap_addr"], row["cause"]) ==
                        (active["pc"], active["addr"], 7), "TRAP_CONTEXT")
            active["outcome"] = True
        require(not row["young"] or (active["outcome"] and RESPONSES[ident] == 0), "YOUNG_SIDE_EFFECT")
        if row["release"]:
            if active["cancel"]:
                require((active["aw"] is None and active["w"] is None) or active["b"], "RESET_DRAIN")
            else:
                require(active["outcome"], "RELEASE_WITHOUT_OUTCOME")
            require(active["cancel"] == (ident in CANCELLED), "RESET_COVERAGE")
            if ident != 5:
                require(active["b_stalls"] >= 3, "B_BACKPRESSURE_COVERAGE")
            if ident == 0:
                require(active["aw"] < active["w"], "AW_FIRST_COVERAGE")
            if ident == 1:
                require(active["w"] < active["aw"], "W_FIRST_COVERAGE")
            if ident == 2:
                require(active["w"] == active["aw"], "SIMULTANEOUS_COVERAGE")
            closed.add(ident)
            active = None
    require(seen == set(range(12)) and closed == set(range(11)), "INCOMPLETE_COVERAGE")
    require(active is not None and active["id"] == 11 and active["cancel"] and
            active["aw"] is not None and active["w"] is not None and
            not active["b"] and not active["outcome"], "QUARANTINE_LOST")
    require(last_cycle - active["reset_cycle"] >= 30, "QUARANTINE_WINDOW")
    require(held_aw is None and held_w is None and held_b is None, "UNFINISHED_CHANNEL")
    return {"scenarios": 12, "closed": 11, "quarantined": 1}


if __name__ == "__main__":
    print("PASS: independent synthetic-trace scoreboard", check(read_trace(sys.argv[1])))
