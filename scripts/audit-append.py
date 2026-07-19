#!/usr/bin/env python3
"""
audit-append.py — Tamper-evident hash-chained audit log append.

Every record in a case's audit/actions.jsonl gains prev_hash and entry_hash
fields, forming a verifiable chain. The first record chains from a genesis
constant (64 zero-bytes). Each entry_hash = SHA-256 over a canonical
(sorted-key, no-whitespace) JSON serialization of the record's content fields
plus the previous record's entry_hash.

Usage:
    python3 audit-append.py <actions.jsonl-path> '<json-record>'

The JSON record should NOT include prev_hash or entry_hash — those are
computed and injected here.

Threat model: tamper-EVIDENT, not tamper-PROOF. An attacker with write access
to the file can rewrite the entire chain, recomputing all hashes. This scheme
detects surgical edits of individual lines but cannot prevent a full-chain
replacement. See skills/evidence-handling/SKILL.md for the full analysis.
"""

import hashlib
import json
import os
import sys

GENESIS = "0000000000000000000000000000000000000000000000000000000000000000"


def canonical(obj: dict) -> str:
    """Sorted keys, no whitespace, deterministic serialization."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def compute_entry_hash(record: dict, prev_hash: str) -> str:
    """SHA-256 over canonical(content fields) + prev_hash."""
    content = {
        k: v for k, v in record.items() if k not in ("prev_hash", "entry_hash")
    }
    payload = canonical(content) + prev_hash
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def main() -> None:
    if len(sys.argv) < 3:
        print(
            "Usage: audit-append.py <actions.jsonl-path> '<json-record>'",
            file=sys.stderr,
        )
        sys.exit(1)

    log_path = sys.argv[1]
    record_str = sys.argv[2]

    try:
        record = json.loads(record_str)
    except json.JSONDecodeError as e:
        print(f"ERROR: invalid JSON record: {e}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(record, dict):
        print("ERROR: record must be a JSON object", file=sys.stderr)
        sys.exit(1)

    # Read existing log to get the last entry_hash for the chain link
    prev_hash = GENESIS
    if os.path.exists(log_path) and os.path.getsize(log_path) > 0:
        last_hash = None
        with open(log_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    last_entry = json.loads(line)
                    last_hash = last_entry.get("entry_hash")
                except json.JSONDecodeError:
                    pass
        if last_hash:
            prev_hash = last_hash

    # Inject chain fields and compute entry_hash
    record["prev_hash"] = prev_hash
    record["entry_hash"] = compute_entry_hash(record, prev_hash)

    # Append
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "a") as f:
        f.write(json.dumps(record, sort_keys=True, ensure_ascii=False) + "\n")

    print(f"OK entry_hash={record['entry_hash'][:16]}...")


if __name__ == "__main__":
    main()
