# Audit Log — Correlation Pass Handoff Review

**Date**: 2026-07-12T03:18Z
**Reviewer**: Hermes (default profile, deepseek-v4-pro)
**Handoff file**: `correlation-pass-integration.zip` → extracted to `/tmp/correlation-review/`

---

## 1. Files Received (unzip -l)

```
14 files, 28,806 bytes total

CORRELATION_HANDOFF.md                             3,340 bytes
new-files/scripts/forensics-verify.py             13,712 bytes
new-files/scripts/test_forensics_verify.py         4,027 bytes
new-files/skills/correlation/SKILL.md              3,199 bytes
sample-case/findings.json                          2,033 bytes
sample-case/timeline.json                          1,044 bytes
sample-case/evidence.json                            248 bytes
sample-case/README.md                              1,203 bytes
```

## 2. Understanding of What This Does

### Core concept
A **read-only advisory tool** that runs after findings are drafted, before the report is generated. For each finding in `findings.json`, it checks whether the same entity (IP, hash, file, domain) appears in an **independent** source elsewhere in the case (`timeline.json`, `evidence.json`, other findings).

### Four verdicts
| Verdict | Trigger | Suggested confidence |
|---|---|---|
| CORROBORATED | Different tool references same entity | HIGH |
| SINGLE-SOURCE | Entity only in finding's own source | LOW |
| CONTRADICTED | Same filename, two different SHA-256 | REVIEW |
| UNVERIFIED | No checkable entity extracted | (honest default) |

### Guarantees (from code + handoff)
- Writes ONLY `correlation-proposals.json` + `correlation-summary.txt`
- Never modifies `findings.json`, `timeline.json`, `evidence.json`, or any report
- No REFUTED verdict ever exists
- Never invents a finding
- No network, no tool execution, no evidence access — pure JSON in, advisory out

## 3. What Was Installed (per handoff instructions)

### Handoff says:
```bash
cp new-files/scripts/forensics-verify.py      scripts/
cp new-files/scripts/test_forensics_verify.py scripts/
mkdir -p skills/correlation && cp new-files/skills/correlation/SKILL.md skills/correlation/
chmod +x scripts/forensics-verify.py scripts/test_forensics_verify.py
```

### Target location:
`/home/niel/hermes-forensics-lab/` (the Git repo)

### Target subdirectories in repo:
```
scripts/    — already contains forensics-*.sh, session-canary.sh, etc.
skills/     — already contains forensic-artifacts/, memory-forensics/, etc.
```

### What was NOT installed:
- `sample-case/` — reference/testing only, per handoff
- No patches to any existing files

## 4. Repo State Before Install

### Git log HEAD:
```
e9567d4 fix: canary/inventory alignment, real MemProcFS version check, install MFTECmd (v4.2.0)
7aa8f21 docs: move Architecture section above Sample Report
2bd5300 docs: remove stats table from sample report section
59b69e7 docs: cache-bust architecture diagram
92d433b docs: update architecture diagram screenshot
```

### Issues found:
- `.git/AUTO_MERGE` — stale merge artifact, cleaned up
- `.git/ORIG_HEAD` — stale, cleaned up  
- `.git/FETCH_HEAD` — stale, cleaned up
- `git status` — clean after cleanup

## 5. Validation Results

### Acceptance test (synthetic data):
```
$ python3 test_forensics_verify.py
F-001: expected CORROBORATED  got CORROBORATED  [ok]
F-002: expected SINGLE-SOURCE got SINGLE-SOURCE [ok]
F-003: expected CONTRADICTED  got CONTRADICTED  [ok]
F-004: expected UNVERIFIED    got UNVERIFIED    [ok]
ALL ASSERTIONS PASSED
```

### Invariants checked by test:
- CORROBORATED must have non-empty `corroborated_by`
- REFUTED must not exist
- `findings.json` byte-for-byte unchanged after run

### BelkaCTF #7 sample case:
```
4 finding(s): 4 CORROBORATED · 0 SINGLE-SOURCE · 0 CONTRADICTED · 0 UNVERIFIED

F-niel-001 → CORROBORATED (corroborated by TL-002, TL-004, TL-005, EVID-001)
F-niel-002 → CORROBORATED (corroborated by TL-004, TL-005, EVID-001)
F-niel-003 → CORROBORATED (corroborated by EVID-001 — SHA-256 match)
F-niel-004 → CORROBORATED (corroborated by TL-006, TL-004, TL-005, EVID-001)
```

## 6. Code Review — Key Logic Points

### Entity extraction (entities() function):
- IPv4 addresses (with octet range validation)
- SHA-256 hashes (64 hex chars)
- MD5 hashes (32 hex chars)
- Domain names (validates TLD against allowlist)
- Filenames (common PE/script extensions: exe, dll, sys, ps1, bat, scr, vbs, js, jar, bin)
- Windows paths (C:\...)
- PIDs (tagged `PID:NNNN`)

### Tool label normalization (tool_label()):
- Lowercases, then splits on `[/\s@:]` and takes first token
- So `"MemProcFS 5.17.8"` → `"memprocfs"`, `"tshark 4.0"` → `"tshark"`

### Corroboration independence check (line 197):
```python
if label and label != ftool:  # independent tool/source
```
This is the gate — same tool finding same entity = NOT corroboration.

### Hash conflict detection (build_hash_conflicts):
- Collects all filename→SHA-256 pairs from evidence + findings
- Flags any file with >1 distinct hash as CONTRADICTED

### PIDs are excluded as sole corroboration keys (line 192):
```python
if ent.startswith(("pid:",)):  # PIDs are weak on their own; skip as sole key
    continue
```

## 7. Dependencies

- Python 3 stdlib only: `argparse, json, os, re, sys, subprocess, tempfile, datetime`
- No pip dependencies
- No external tools called
- No network access

## 8. Rollback Procedure (per handoff)

```bash
rm scripts/forensics-verify.py scripts/test_forensics_verify.py
rm -r skills/correlation
```

Nothing else was touched — fully reversible.

## 9. What Was NOT Done (deliberately excluded from v1 per handoff)

- Report routing (anti-forensics section, ruled-out appendix) — not wired
- Writing verdicts back into `findings.json` — not done
- Auto-confidence in the rendered report — not done
- Additional artifact-class correlation rules — not done
- Any patches to existing files — not done

## 10. Skills Loaded During Review

- `forensics-agent` — confirmed correlation pass fits after Phase 3 (Synthesis), before Phase 4 (Report)
- `forensics-lab` — confirmed repo structure, install locations, handoff pattern
- `correlation` (from zip) — SKILL.md loaded and understood

## 11. Potential Gaps / Questions for Claude

1. Should `sample-case/` be committed to the repo? Handoff doesn't say to install it, but the README inside it says "Do NOT commit correlation-proposals.json or correlation-summary.txt" — implying the JSON files should be committed minus generated output.

2. Should this be wired into `forensics-pipeline.sh` as an automatic step? The handoff says "Report routing is deliberately not included yet" — but should the pipeline at least run the correlation pass after findings?

3. Should the forensics-agent SKILL.md be updated to mention the correlation pass as a step between Phase 3 and Phase 4? Currently the Turn 1-4 pattern doesn't include it.

4. Should `project-metadata.yaml` be updated? It tracks script counts — adding 2 scripts would increase the count.

5. Should a CHANGELOG entry be created? The handoff doesn't mention one, but the repo has `CHANGELOG.md`.
