#!/usr/bin/env python3
"""
test_forensics_verify.py — self-contained acceptance test.

Builds a synthetic case engineered to produce exactly one of each verdict, runs
forensics-verify.py against it, and asserts the verdicts. Exits non-zero (loudly)
on ANY mismatch. No SKIPs — every case is asserted.

Run:  python3 test_forensics_verify.py
Pass: prints "ALL ASSERTIONS PASSED" and exits 0.
Fail: prints the mismatch and exits 1.
"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "forensics-verify.py")

# Engineered case:
#  F-001 CORROBORATED — C2 IP appears in a finding (MemProcFS) AND a timeline event (tshark).
#  F-002 SINGLE-SOURCE — a file seen only in its own finding, no independent source.
#  F-003 CONTRADICTED — payload.exe has one SHA-256 in evidence, a different one in a finding.
#  F-004 UNVERIFIED — no extractable entity at all.
FINDINGS = [
    {"id": "F-001", "title": "C2 beacon to 104.21.1.247 from lsass.exe",
     "confidence": "HIGH", "tool": "MemProcFS 5.17.8", "evidence_ref": "EVID-001"},
    {"id": "F-002", "title": "Wow64 flag on oddtool.exe",
     "confidence": "LOW", "tool": "MemProcFS 5.17.8", "evidence_ref": "EVID-002"},
    {"id": "F-003", "title": "Dropper payload.exe with hash "
                             "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
     "confidence": "HIGH", "tool": "mft-tools 1.2.0.0", "evidence_ref": "EVID-003"},
    {"id": "F-004", "title": "Suspicious activity observed during triage",
     "confidence": "MEDIUM", "tool": "analyst-note", "evidence_ref": "EVID-004"},
]
TIMELINE = [
    {"id": "TL-001", "timestamp": "2026-07-01T10:00:00Z",
     "event": "Outbound TCP to 104.21.1.247:443", "source": "tshark 4.0"},
    {"id": "TL-002", "timestamp": "2026-07-01T09:59:00Z",
     "event": "User login on workstation", "source": "regripper"},
]
EVIDENCE = [
    {"evidence_id": "EVID-003", "filename": "payload.exe",
     "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
     "source": "disk image /dev/sdb1"},
]

EXPECTED = {
    "F-001": "CORROBORATED",
    "F-002": "SINGLE-SOURCE",
    "F-003": "CONTRADICTED",
    "F-004": "UNVERIFIED",
}


def main() -> int:
    with tempfile.TemporaryDirectory() as case:
        json.dump(FINDINGS, open(os.path.join(case, "findings.json"), "w"))
        json.dump(TIMELINE, open(os.path.join(case, "timeline.json"), "w"))
        json.dump(EVIDENCE, open(os.path.join(case, "evidence.json"), "w"))

        r = subprocess.run([sys.executable, SCRIPT, case, "--json-only"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print("FAIL: script exited", r.returncode, "\n", r.stderr); return 1

        proposals = json.load(open(os.path.join(case, "correlation-proposals.json")))
        got = {p["finding_id"]: p["verdict"] for p in proposals}

        ok = True
        for fid, want in EXPECTED.items():
            have = got.get(fid)
            mark = "ok" if have == want else "MISMATCH"
            if have != want:
                ok = False
            print(f"  {fid}: expected {want:<13} got {str(have):<13} [{mark}]")

        # invariant checks
        for p in proposals:
            if p["verdict"] == "CORROBORATED" and not p["corroborated_by"]:
                print("FAIL invariant: CORROBORATED with empty corroborated_by:", p["finding_id"]); ok = False
            if p["verdict"] == "REFUTED":
                print("FAIL invariant: REFUTED must not exist:", p["finding_id"]); ok = False

        # read-only proof: findings.json unchanged
        after = json.load(open(os.path.join(case, "findings.json")))
        if after != FINDINGS:
            print("FAIL: findings.json was modified — must be read-only!"); ok = False

        if ok:
            print("\nALL ASSERTIONS PASSED"); return 0
        print("\nASSERTIONS FAILED"); return 1


if __name__ == "__main__":
    raise SystemExit(main())
