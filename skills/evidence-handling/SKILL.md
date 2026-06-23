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

## Pitfalls
- Never modify evidence in place — copy, hash, then chmod 444
- Hash before AND after copy — network transfers can corrupt
- Use ISO 8601 with timezone on all timestamps
- Log EVERY transfer in the chain of custody
