#!/usr/bin/env python3
"""
forensics-verify-audit.py — Verify the tamper-evident hash chain.

Walks a case's audit/actions.jsonl, recomputes the SHA-256 hash chain, and
reports:
    - CHAIN INTACT — all records correctly linked
    - BROKEN CHAIN — first broken link, with the line number and mismatch

Exit 0 = chain intact. Exit 1 = tamper detected or file not found.

Usage:
    python3 forensics-verify-audit.py <case_dir>
    python3 forensics-verify-audit.py <actions.jsonl>    # direct file path
"""

import hashlib
import json
import os
import sys

GENESIS = "0000000000000000000000000000000000000000000000000000000000000000"


def canonical(obj: dict) -> str:
    """Sorted keys, no whitespace, deterministic serialization."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def verify(log_path: str) -> tuple[bool, int]:
    """
    Verify the hash chain. Returns (ok, record_count).
    Prints diagnostics to stdout on failure.
    """
    prev_hash = GENESIS
    count = 0

    with open(log_path, "r") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue

            try:
                record = json.loads(line)
            except json.JSONDecodeError as e:
                print(f"BROKEN CHAIN at line {line_no}: invalid JSON — {e}")
                return False, count

            actual_prev = record.get("prev_hash", "MISSING")
            if actual_prev != prev_hash:
                print(f"BROKEN CHAIN at line {line_no}: prev_hash mismatch")
                print(f"  expected: {prev_hash}")
                print(f"  got:      {actual_prev}")
                return False, count

            actual_entry = record.get("entry_hash")
            if not actual_entry:
                print(f"BROKEN CHAIN at line {line_no}: missing entry_hash")
                return False, count

            # Recompute expected entry_hash
            content = {
                k: v
                for k, v in record.items()
                if k not in ("prev_hash", "entry_hash")
            }
            expected = hashlib.sha256(
                (canonical(content) + prev_hash).encode("utf-8")
            ).hexdigest()

            if actual_entry != expected:
                print(
                    f"BROKEN CHAIN at line {line_no}: entry_hash mismatch "
                    f"(record content tampered or prev_hash corrupted)"
                )
                print(f"  expected: {expected}")
                print(f"  got:      {actual_entry}")
                return False, count

            prev_hash = actual_entry
            count += 1

    return True, count


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "Usage: forensics-verify-audit.py <case_dir_or_actions.jsonl>",
            file=sys.stderr,
        )
        return 1

    path = sys.argv[1]
    if os.path.isdir(path):
        log_path = os.path.join(path, "audit", "actions.jsonl")
    else:
        log_path = path

    if not os.path.exists(log_path):
        print(f"ERROR: audit log not found: {log_path}", file=sys.stderr)
        return 1

    ok, count = verify(log_path)
    if ok:
        print(f"CHAIN INTACT — {count} record(s) verified")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
