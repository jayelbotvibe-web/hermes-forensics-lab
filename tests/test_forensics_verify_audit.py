#!/usr/bin/env python3
"""
test_forensics_verify_audit.py — acceptance tests for the audit hash chain.

Verifies:
  1. forensics-verify-audit.py passes on a clean chain  → exit 0
  2. forensics-verify-audit.py fails on a tampered chain → exit 1
  3. forensics-verify-audit.py fails on a deleted record  → exit 1

Run:  python3 test_forensics_verify_audit.py
Pass: prints "ALL ASSERTIONS PASSED" and exits 0.
Fail: prints the mismatch and exits 1.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "scripts", "forensics-verify-audit.py")
FIXTURES = os.path.join(HERE, "fixtures")


def run(path: str) -> tuple[int, str, str]:
    r = subprocess.run(
        [sys.executable, SCRIPT, path], capture_output=True, text=True
    )
    return r.returncode, r.stdout, r.stderr


def main() -> int:
    ok = True

    # ── 1. Valid chain ──
    valid_path = os.path.join(FIXTURES, "audit-chain-valid", "actions.jsonl")
    rc, out, err = run(valid_path)
    mark = "ok" if rc == 0 and "CHAIN INTACT" in out else "FAIL"
    if mark != "ok":
        ok = False
    print(f"  [1] valid chain:  exit={rc}  [{mark}]")
    if mark != "ok":
        print(f"      stdout: {out.strip()}")
        print(f"      stderr: {err.strip()}")

    # ── 2. Tampered chain (content modified without recomputing hash) ──
    tampered_path = os.path.join(FIXTURES, "audit-chain-tampered", "actions.jsonl")
    rc, out, err = run(tampered_path)
    mark = "ok" if rc == 1 and "entry_hash mismatch" in out else "FAIL"
    if mark != "ok":
        ok = False
    print(f"  [2] tampered chain: exit={rc}  [{mark}]")
    if mark != "ok":
        print(f"      stdout: {out.strip()}")
        print(f"      stderr: {err.strip()}")

    # ── 3. Deleted record (gap in chain) ──
    gap_path = os.path.join(FIXTURES, "audit-chain-gap", "actions.jsonl")
    rc, out, err = run(gap_path)
    mark = "ok" if rc == 1 and "prev_hash mismatch" in out else "FAIL"
    if mark != "ok":
        ok = False
    print(f"  [3] deleted record: exit={rc}  [{mark}]")
    if mark != "ok":
        print(f"      stdout: {out.strip()}")
        print(f"      stderr: {err.strip()}")

    # ── Result ──
    if ok:
        print("\nALL ASSERTIONS PASSED")
        return 0
    print("\nASSERTIONS FAILED")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
