---
name: evidence-handling
description: "Chain of custody, evidence registration, hashing, and case directory structure"
version: 1.0.0
category: forensics
always_load: false
---

# Evidence Handling

## When to Use
- Starting a new case
- Registering new evidence
- Closing a case — finalize, verify hashes
- Any time evidence changes hands

## Pre-flight
- Read /home/niel/forensics/tools/tool-catalog.yaml for tool versions
- Evidence must be at rest before hashing

## Case Initialization

### Step 1: Create case directory
```
mkdir -p /home/niel/forensics/cases/INC-YYYY-MMDD-NNNN/{evidence,raw,reports,audit}
```
Replace YYYY-MMDD-NNNN with date and sequential number.

### Step 2: Create CASE.yaml
Write to /home/niel/forensics/cases/INC-YYYY-MMDD-NNNN/CASE.yaml:
```yaml
case_id: INC-YYYY-MMDD-NNNN
status: active
opened: <ISO8601 timestamp>
examiner: niel
description: "<brief description>"
```

### Step 3: Initialize audit trail
Append to audit/actions.jsonl:
```json
{"case_id": "INC-YYYY-MMDD-NNNN", "action": "case_open", "timestamp": "<ISO8601>"}
```

## Evidence Registration

### Step 1: Hash the evidence
```bash
bash /home/niel/forensics/scripts/sift-exec.sh "hashdeep -c sha256 /cases/INC-YYYY-MMDD-NNNN/evidence/FILENAME"
```
If SIFT VM is unavailable, use: `sha256sum /home/niel/forensics/cases/INC-YYYY-MMDD-NNNN/evidence/FILENAME`

### Step 2: Copy evidence to case directory
Copy the evidence file into case/evidence/
Set read-only: `chmod 444 /home/niel/forensics/cases/INC-YYYY-MMDD-NNNN/evidence/FILENAME`

### Step 3: Verify copy hash matches original
Compare hashes — must match exactly.

### Step 4: Register in evidence.json
Write to /home/niel/forensics/cases/INC-YYYY-MMDD-NNNN/evidence.json:
```json
[{
  "evidence_id": "EVID-001",
  "filename": "FILENAME",
  "sha256": "<hash>",
  "source": "<where it came from>",
  "acquired_by": "niel",
  "acquired_at": "<ISO8601>",
  "tool": "<acquisition tool + version>",
  "readonly": true
}]
```

### Step 5: Log in audit trail
Append to audit/actions.jsonl.

## Case Closure

### Step 1: Verify all evidence hashes
Re-hash all evidence files and compare against evidence.json.

### Step 2: Finalize findings
Ensure all DRAFT findings are addressed.

### Step 3: Record tool versions
Run `docker images --format "{{.Repository}}:{{.Tag}}" | grep forensics-` and save to case/tool_versions.json.

### Step 4: Close case
Update CASE.yaml status to 'closed'. Log to audit trail.

### Step 5: Verify audit chain integrity
Before closing, verify the tamper-evident hash chain is intact:
```bash
python3 /home/niel/forensics/scripts/forensics-verify-audit.py /home/niel/forensics/cases/INC-YYYY-MMDD-NNNN
```
A broken chain at closure indicates tampering — do not close until resolved.

## Audit Trail (Tamper-Evident Hash Chain)

Every action logged to `audit/actions.jsonl` is part of a cryptographic hash
chain. Each record carries two additional fields:

- **`prev_hash`** — SHA-256 of the previous record (genesis constant for the first)
- **`entry_hash`** — SHA-256 over a canonical serialization of the record's
  content fields concatenated with `prev_hash`

The canonical serialization uses `json.dumps(obj, sort_keys=True,
separators=(",", ":"))` — sorted keys, no whitespace, deterministic.

### Threat Model

**Tamper-EVIDENT, not tamper-PROOF.** This scheme detects surgical edits:
changing a field, deleting a record, or inserting a record will break the
`entry_hash` or `prev_hash` of every subsequent record.

However, an attacker with **write access to the file** can rewrite the entire
chain with valid recomputed hashes. This is a hash chain, not a blockchain —
there is no distributed trust anchor or append-only medium. The defense
assumes:

1. The file is on a LUKS-encrypted volume that is only mounted during active
   investigations.
2. The examiner verifies the chain (`forensics-verify-audit.py`) before
   closing a case.
3. Copies of the audit log stored off-system (backup, report appendix) provide
   an independent reference point to detect full-chain replacement.

If full-chain integrity beyond the host is required, periodically commit
verified hashes to an external immutable log (git, a timestamping service, or
a witness server).

### Verification

```bash
# Check a case's audit chain
python3 scripts/forensics-verify-audit.py /path/to/case_dir
# Exit 0 = chain intact. Exit 1 = broken.

# The check also runs automatically as part of forensics-verify.py
python3 scripts/forensics-verify.py /path/to/case_dir
# Exit 2 = audit chain broken (before correlation pass).
```

## Hostile Evidence Handling

**This host is not a malware detonation sandbox.** Live or unknown-malicious
samples must NEVER be executed — only parsed by the containerized or read-only
tools. Specifically:

- Memory dumps: analyzed via MemProcFS (FUSE mount, no code execution) or
  volatility3 (static parsing in Docker). The dump file is never executed.
- Disk images: mounted READ-ONLY. Write-blocking is enforced at the mount
  level.
- Malware samples: if a sample file is extracted, it is hash-verified,
  chmod'd to 444, and never executed. Do NOT run `file`, `strings`, or any
  tool that may trigger format-parsing vulnerabilities outside the Docker
  containers.
- True detonation (sandbox execution) belongs on a **disposable,
  network-isolated VM** — not on this host and not on the SIFT VM. Use a
  dedicated malware analysis sandbox (Cuckoo, CAPE, Joe Sandbox, or a
  throwaway VM with no network adapter and no shared folders).

If you encounter a file you are unsure about, treat it as hostile: hash it,
register it read-only, and analyze it through Docker tools only.

## Pitfalls
- Never modify evidence in place — copy, hash, then chmod 444
- Hash before AND after copy — network transfers can corrupt
- Use ISO 8601 with timezone on all timestamps
- Log EVERY transfer in the chain of custody
