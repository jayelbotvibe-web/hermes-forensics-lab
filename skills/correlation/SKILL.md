---
name: correlation
description: "Read-only correlation advisor. After analysis, before reporting, checks whether each DRAFT finding is confirmed by an independent source and proposes a verdict. Advisory only — proposes, never decides; the examiner confirms. Load after findings are drafted."
version: 1.0.0
category: forensics
---

# Correlation Pass

You do not discover findings and you do not write the report. After the analysis
skills have drafted findings, you check each one against **independent** evidence
and propose a verdict. You propose; the examiner decides. Every finding stays DRAFT.

## The one idea

A finding is a claim from one tool looking at one source. To raise confidence in it,
find the **same entity** (an IP, hash, file, or domain) in a **different** source or
from a **different** tool. Convergence across independent sources is corroboration.

## Run it

```bash
python3 scripts/forensics-verify.py <case_dir>
```

It reads `findings.json`, `timeline.json`, `evidence.json` from the case and writes
one advisory file — `correlation-proposals.json` — plus `correlation-summary.txt`.
It modifies nothing else.

## The four verdicts (advisory)

| Verdict | Means | Suggested confidence |
|---|---|---|
| **CORROBORATED** | an independent source (different tool) references the same entity | HIGH |
| **SINGLE-SOURCE** | the entity appears only in the finding's own source | LOW — examiner review |
| **CONTRADICTED** | a mechanical conflict (same file, two different SHA-256) | REVIEW — possible substitution or labeling error |
| **UNVERIFIED** | no checkable entity, or nothing to check against | — honest default |

## Ground rules (do not weaken)

- **Read-only.** The pass writes `correlation-proposals.json` and the summary. It
  NEVER edits `findings.json`, the timeline, the evidence, or the report.
- **No REFUTED.** The pass never declares a finding benign or removes it. The most
  it does on a conflict is flag CONTRADICTED for the examiner.
- **It never invents a finding.** A contradiction is surfaced for the examiner, not
  turned into a new finding automatically.
- **A read/parse problem is UNVERIFIED**, never CONTRADICTED and never CORROBORATED.
  Absence of evidence is not evidence.
- **Independence is required.** The corroborating source's tool/source must differ
  from the finding's own tool. Same tool twice is not corroboration.
- **CORROBORATED always names its sources.** Every CORROBORATED verdict lists the
  independent reference IDs it relied on.

## What the examiner does next

Read `correlation-summary.txt`. Promote, adjust, or reject each proposal by hand.
The verdicts are suggestions to speed your review — not automatic report changes.
Findings remain DRAFT until you approve them, exactly as before.

## Scope (v1)

Correlates against artifacts **already collected into the case**. If a corroborating
source was never collected, the finding stays SINGLE-SOURCE or UNVERIFIED — the pass
does not go run tools to fetch more. Report routing (anti-forensics section,
ruled-out appendix) is intentionally **not** wired in v1; this is an advisory layer
first. Trust it on real cases, then we wire it into the report.
