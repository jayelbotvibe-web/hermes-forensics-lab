#!/usr/bin/env python3
"""
forensics-verify.py — read-only correlation advisor for a forensics case.

WHAT IT DOES
    Reads a case's findings.json, timeline.json, and evidence.json, and for each
    DRAFT finding checks whether an INDEPENDENT source (a different tool, or a
    different artifact class) also points at the same entity. It writes a single
    advisory file — correlation-proposals.json — plus a plain-text summary.

WHAT IT DOES NOT DO  (these are guarantees, not TODOs)
    - It NEVER modifies findings.json, timeline.json, evidence.json, or any report.
    - It NEVER deletes or "rules out" a finding. There is no REFUTED verdict.
    - It NEVER invents a new finding. A contradiction is flagged for the examiner.
    - It NEVER runs a forensic tool or touches evidence. It only reads the case JSON.
    It proposes; the examiner decides. All findings stay DRAFT.

THE FOUR VERDICTS  (advisory only)
    CORROBORATED   an independent source (different tool) points at the same entity
    SINGLE-SOURCE  the entity appears only in the finding's own source
    CONTRADICTED   a mechanical conflict was found (same file, two different SHA-256)
    UNVERIFIED     nothing checkable could be extracted, or no sources to check against

    UNVERIFIED is the honest default. A read/parse problem is UNVERIFIED, never
    CONTRADICTED and never CORROBORATED. Absence of evidence is not evidence.

USAGE
    python3 forensics-verify.py <case_dir>
    python3 forensics-verify.py <case_dir> --json-only     # suppress the text summary
    # <case_dir> must contain findings.json (timeline.json / evidence.json optional)

OUTPUT
    <case_dir>/correlation-proposals.json     machine-readable proposals
    stdout (and <case_dir>/correlation-summary.txt)   human-readable summary

Exit 0 = ran (proposals written). Exit 1 = usage / no findings.json. Nothing else.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

# ── entity extraction ─────────────────────────────────────────────────────────
# Mirrors the IOC patterns already used by forensics-report.sh, plus process
# names and PIDs. Entities are how we decide whether two sources "point at the
# same thing".
RE_IPV4   = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
RE_SHA256 = re.compile(r"\b[a-fA-F0-9]{64}\b")
RE_HASH32 = re.compile(r"\b[a-fA-F0-9]{32}\b")           # md5
RE_DOMAIN = re.compile(r"\b[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
                       r"(?:\.[a-zA-Z]{2,})+\b")
RE_FILE   = re.compile(r"\b[\w.-]+\.(?:exe|dll|sys|ps1|bat|scr|vbs|js|jar|bin)\b",
                       re.IGNORECASE)
RE_WINPATH= re.compile(r"[A-Za-z]:\\[^\s,;\"']+")
RE_PID    = re.compile(r"\bPID[\s:]*?(\d{2,6})\b", re.IGNORECASE)

# TLDs we accept for domains, to avoid treating "explorer.exe" or "5.17.8" as one.
_GOOD_TLD = {"com","net","org","io","gov","mil","edu","ru","cn","co","info",
             "biz","xyz","top","site","online","dev","app","cloud"}


def entities(text: str) -> set:
    """Extract normalized entities from a blob of text."""
    if not text:
        return set()
    out = set()
    for m in RE_IPV4.findall(text):
        parts = m.split(".")
        if all(0 <= int(p) <= 255 for p in parts):   # real IPv4, not a version
            out.add("ip:" + m)
    for h in RE_SHA256.findall(text):
        out.add("sha256:" + h.lower())
    for h in RE_HASH32.findall(text):
        out.add("md5:" + h.lower())
    for d in RE_DOMAIN.findall(text):
        tld = d.rsplit(".", 1)[-1].lower()
        # a file like foo.exe also matches DOMAIN; only keep real TLDs as domains
        if tld in _GOOD_TLD and not RE_FILE.fullmatch(d):
            out.add("domain:" + d.lower())
    for f in RE_FILE.findall(text):
        out.add("file:" + os.path.basename(f).lower())
    for p in RE_WINPATH.findall(text):
        out.add("file:" + os.path.basename(p).lower())
        out.add("path:" + p.lower())
    for pid in RE_PID.findall(text):
        out.add("pid:" + pid)
    return out


def text_of(obj) -> str:
    """Join all string values of a dict/record so entity extraction sees everything."""
    if isinstance(obj, dict):
        return " ".join(str(v) for v in obj.values() if isinstance(v, (str, int, float)))
    return str(obj)


def tool_label(s: str) -> str:
    """Normalize a tool/source label to its base name for independence checks."""
    if not s:
        return ""
    s = s.lower()
    s = re.split(r"[\s/@:]", s)[0]        # drop version suffixes ("memprocfs 5.17.8")
    return s.strip()


def load(path):
    if not os.path.exists(path):
        return None
    try:
        with open(path) as fh:
            return json.load(fh)
    except (json.JSONDecodeError, OSError):
        return None


# ── the correlation logic ──────────────────────────────────────────────────────

def build_hash_conflicts(findings, evidence):
    """filename -> set of distinct sha256 seen. A file with >1 hash is a conflict.
    Evidence hashes are authoritative; finding text may also carry a hash."""
    fmap = {}
    def add(fname, h):
        if not fname or not h:
            return
        fmap.setdefault(fname.lower(), set()).add(h.lower())
    for e in (evidence or []):
        fn = e.get("filename")
        h  = e.get("sha256") or e.get("sha256_verified")
        add(fn, h)
    for f in (findings or []):
        blob = text_of(f)
        files = [os.path.basename(x) for x in RE_FILE.findall(blob)]
        hashes = RE_SHA256.findall(blob)
        if len(files) == 1 and len(hashes) == 1:
            add(files[0], hashes[0])
    return {fn: hs for fn, hs in fmap.items() if len(hs) > 1}


def correlate(findings, timeline, evidence):
    hash_conflicts = build_hash_conflicts(findings, evidence)

    # Index independent sources by entity → list of (source_label, ref_id, kind)
    index = {}
    def index_add(ent, label, ref, kind):
        index.setdefault(ent, []).append((tool_label(label), ref, kind))

    for i, ev in enumerate(timeline or []):
        rid = ev.get("id") or f"TL-{i+1:03d}"
        for ent in entities(text_of(ev)):
            index_add(ent, ev.get("source", ""), rid, "timeline")
    for e in (evidence or []):
        rid = e.get("evidence_id", "EVID-?")
        for ent in entities(text_of(e)):
            index_add(ent, e.get("source", ""), rid, "evidence")
    for f in (findings or []):
        rid = f.get("id", "F-?")
        for ent in entities(text_of(f)):
            index_add(ent, f.get("tool", ""), rid, "finding")

    verdict_conf = {"CORROBORATED": "HIGH", "CONTRADICTED": "REVIEW",
                    "SINGLE-SOURCE": "LOW", "UNVERIFIED": "UNVERIFIED"}
    proposals = []

    for f in (findings or []):
        fid   = f.get("id", "F-?")
        ftool = tool_label(f.get("tool", ""))
        ents  = entities(text_of(f))

        # 1) contradiction: does this finding reference a file with conflicting hashes?
        conflicts = []
        for ent in ents:
            if ent.startswith("file:"):
                fn = ent[5:]
                if fn in hash_conflicts:
                    conflicts.append({"file": fn,
                                      "hashes": sorted(hash_conflicts[fn])})
        if conflicts:
            proposals.append(proposal(f, "CONTRADICTED", verdict_conf, ents,
                                      corroborated_by=[], conflicts=conflicts,
                                      method="hash-conflict",
                                      note="Same filename carries two different SHA-256 "
                                           "values across the case. Examiner review — "
                                           "possible substitution or a labeling error."))
            continue

        # 2) corroboration: same entity seen from an INDEPENDENT tool/source
        corr = []
        for ent in ents:
            if ent.startswith(("pid:",)):     # PIDs are weak on their own; skip as sole key
                continue
            for (label, ref, kind) in index.get(ent, []):
                if ref == fid:
                    continue                  # itself
                if label and label != ftool:  # independent tool/source
                    corr.append({"ref": ref, "kind": kind, "via": ent, "source": label})
        # de-dupe by ref
        seen, corr_u = set(), []
        for c in corr:
            if c["ref"] not in seen:
                seen.add(c["ref"]); corr_u.append(c)

        if corr_u:
            proposals.append(proposal(f, "CORROBORATED", verdict_conf, ents,
                                      corroborated_by=corr_u, conflicts=[],
                                      method="entity-cross-reference",
                                      note=f"Confirmed by {len(corr_u)} independent "
                                           f"source(s) referencing the same entity."))
        elif ents:
            proposal_ents = sorted(e for e in ents if not e.startswith("pid:"))
            proposals.append(proposal(f, "SINGLE-SOURCE", verdict_conf, ents,
                                      corroborated_by=[], conflicts=[],
                                      method="entity-cross-reference",
                                      note="Entity found only in this finding's own "
                                           "source. Uncorroborated — examiner review."
                                      if proposal_ents else
                                      "No independent corroboration found."))
        else:
            proposals.append(proposal(f, "UNVERIFIED", verdict_conf, ents,
                                      corroborated_by=[], conflicts=[],
                                      method="none",
                                      note="No checkable entity (IP, hash, file, domain) "
                                           "could be extracted from this finding."))
    return proposals


def proposal(f, verdict, verdict_conf, ents, corroborated_by, conflicts, method, note):
    return {
        "finding_id": f.get("id", "F-?"),
        "title": f.get("title", "Untitled"),
        "discovery_tool": f.get("tool", "?"),
        "original_confidence": f.get("confidence", "?"),
        "verdict": verdict,
        "suggested_confidence": verdict_conf[verdict],
        "corroborated_by": corroborated_by,
        "conflicts": conflicts,
        "checked_entities": sorted(ents),
        "method": method,
        "note": note,
        "examiner_status": "proposed",
    }


# ── output ─────────────────────────────────────────────────────────────────────

def summary_text(proposals, case):
    tally = {}
    for p in proposals:
        tally[p["verdict"]] = tally.get(p["verdict"], 0) + 1
    lines = []
    lines.append("=" * 66)
    lines.append(f" Correlation proposals — case: {case}")
    lines.append(f" {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}  (ADVISORY — nothing modified)")
    lines.append("=" * 66)
    for p in proposals:
        lines.append(f"\n  {p['finding_id']}  [{p['verdict']}]  {p['title'][:52]}")
        lines.append(f"     tool: {p['discovery_tool']}   suggested confidence: {p['suggested_confidence']}")
        if p["corroborated_by"]:
            refs = ", ".join(f"{c['ref']}({c['via']})" for c in p["corroborated_by"])
            lines.append(f"     corroborated by: {refs}")
        if p["conflicts"]:
            for c in p["conflicts"]:
                lines.append(f"     CONFLICT on {c['file']}: {', '.join(h[:12]+'…' for h in c['hashes'])}")
        lines.append(f"     {p['note']}")
    lines.append("\n" + "-" * 66)
    order = ["CORROBORATED", "SINGLE-SOURCE", "CONTRADICTED", "UNVERIFIED"]
    tallystr = " · ".join(f"{tally.get(v,0)} {v}" for v in order)
    lines.append(f"  {len(proposals)} finding(s): {tallystr}")
    lines.append("  Advisory only. All findings remain DRAFT. Examiner decides.")
    lines.append("-" * 66)
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Read-only correlation advisor for a forensics case.")
    ap.add_argument("case_dir")
    ap.add_argument("--json-only", action="store_true", help="don't print the text summary")
    args = ap.parse_args()

    case = os.path.abspath(args.case_dir)

    # ── Audit chain integrity check ──────────────────────────────────────
    audit_log = os.path.join(case, "audit", "actions.jsonl")
    if os.path.exists(audit_log):
        verify_script = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "forensics-verify-audit.py"
        )
        r = subprocess.run([sys.executable, verify_script, audit_log],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print("AUDIT CHAIN BROKEN — correlation pass aborted:", file=sys.stderr)
            print(r.stdout.strip(), file=sys.stderr)
            print("\nACTION: The audit log hash chain is broken. This must be "
                  "resolved before the case can proceed to report. "
                  "See skills/evidence-handling/SKILL.md for tamper-response "
                  "procedures.", file=sys.stderr)
            return 2  # distinct exit code: audit-chain-broken
        # else: chain intact, proceed silently

    findings = load(os.path.join(case, "findings.json"))
    if findings is None:
        print(f"Error: findings.json not found or unreadable in {case}", file=sys.stderr)
        return 1
    if not isinstance(findings, list) or not findings:
        print("No findings to correlate.")
        # still emit an empty proposals file for pipeline consistency
        findings = []
    timeline = load(os.path.join(case, "timeline.json")) or []
    evidence = load(os.path.join(case, "evidence.json")) or []

    proposals = correlate(findings, timeline, evidence)

    # write advisory file (this is the ONLY thing we write into the case)
    out_json = os.path.join(case, "correlation-proposals.json")
    with open(out_json, "w") as fh:
        json.dump(proposals, fh, indent=2)

    text = summary_text(proposals, os.path.basename(case))
    with open(os.path.join(case, "correlation-summary.txt"), "w") as fh:
        fh.write(text + "\n")
    if not args.json_only:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
