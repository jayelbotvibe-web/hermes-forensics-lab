---
name: system-context
description: "Complete forensics system architecture, tool inventory, paths, and operational procedures. Load on every session."
version: 1.0.0
category: forensics
always_load: true
---

# Forensics Agent — System Context

> **Load this skill on EVERY session.** It contains the full system map — tool locations, paths, runtimes, and operational procedures. Without it, the agent cannot correctly execute forensic tools.

---

## Architecture Overview

```
HOST (terminal.backend: local, HOME=$HERMES_PROFILE_DIR/home)
├── Docker images: volatility3, plaso, mft-tools — run with `docker run --rm`
├── Host binary: MemProcFS v5.17.9 at $MEMPROCFS_BIN
├── Evidence: $FORENSICS_HOME/cases/ (LUKS encrypted, 30GB)
├── Fixtures: $FORENSICS_HOME/fixtures/
├── Scripts: $FORENSICS_HOME/scripts/
└── SIFT VM: $SIFT_HOST — SSH key auth — $SIFT_USER
        │
        ├── Evidence mounted at: ~/cases/ (SSHFS from host)
        └── Native tools: sleuthkit, foremost, dc3dd, regripper, hashdeep, tshark
```

**CRITICAL:** All file paths must be ABSOLUTE (e.g. $FORENSICS_HOME/cases/CASE_ID/evidence/FILE). The profile sandboxes $HOME to $HERMES_PROFILE_DIR/home. Never use ~/ in paths.

---

## Tool Inventory (12 tools, 3 runtimes)

### Runtime 1: Host Docker
| Tool | Image | Version | Command Pattern |
|------|-------|---------|----------------|
| volatility3 | forensics-volatility3:2.7.0 | 2.7.0 | `docker run --rm -v $FORENSICS_HOME/cases/CASE_ID:/evidence:ro -v $FORENSICS_HOME/cases/CASE_ID/raw:/output forensics-volatility3:2.7.0 -f /evidence/FILE PLUGIN` |
| plaso | forensics-plaso:20240512 | 20240512 | `docker run --rm -v $FORENSICS_HOME/cases/CASE_ID:/evidence:ro -v $FORENSICS_HOME/cases/CASE_ID/raw:/output forensics-plaso:20240512 log2timeline.py --storage-file /output/timeline.plaso /evidence/FILE` |
| mft-tools | forensics-mft-tools:1.2.0.0 | 1.2.0.0 | `docker run --rm -v $FORENSICS_HOME/cases/CASE_ID:/evidence:ro -v $FORENSICS_HOME/cases/CASE_ID/raw:/output forensics-mft-tools:1.2.0.0 python3 -m analyzemft -f /evidence/FILE -o /output/analyzemft.csv` |

**IMPORTANT:** volatility3 Docker entrypoint is already `volatility`. Do NOT prefix commands with `vol`. Start directly with flags: `-f /evidence/dump.mem windows.info.Info`.

### Runtime 2: Host FUSE — MemProcFS
| Tool | Binary | Version | Command Pattern |
|------|--------|---------|----------------|
| MemProcFS | $MEMPROCFS_BIN | 5.17.9 | `mkdir -p /mnt/mem && $MEMPROCFS_BIN -device DUMP_FILE -mount /mnt/mem -forensic 1` |

Unmount: `fusermount -u /mnt/mem`
Key paths after mount: /mnt/mem/sys/proc/ (processes), /mnt/mem/sys/net/ (network), /mnt/mem/forensic/findevil.txt (malware detection)
Windows dumps only. For Linux dumps, use volatility3.

### Runtime 3: SIFT VM (SSH wrapper)
Execute via: `bash $FORENSICS_HOME/scripts/sift-exec.sh "COMMAND"`

| Tool | Version | Check Command |
|------|---------|--------------|
| sleuthkit | 4.11.1 | `fls -V` |
| foremost | 1.5.7 | `foremost -V` |
| photorec | 7.1 | `photorec --help` |
| dc3dd | 7.3.1 | `dc3dd --version` |
| ddrescue | 1.27 | `ddrescue --version` |
| hashdeep | 4.4 | `hashdeep -V` |
| tshark | 4.0 | `tshark --version` |
| ewf-tools | (apt) | `ewfacquire --version` |
| regripper | 3.0 | `which regripper` |

Evidence is visible at: `/home/$SIFT_USER/cases/` on the VM (SSHFS mount from host).
Pass paths as: `/home/$SIFT_USER/cases/CASE_ID/evidence/FILE`

---

## Key Paths (ALL ABSOLUTE)

| Purpose | Path |
|---------|------|
| Evidence root | $FORENSICS_HOME/cases/ |
| Case template | $FORENSICS_HOME/cases/INC-YYYY-MMDD-NNNN/ |
| Tool catalog | $FORENSICS_HOME/tools/tool-catalog.yaml |
| Session canary | $FORENSICS_HOME/scripts/session-canary.sh |
| SSH wrapper | $FORENSICS_HOME/scripts/sift-exec.sh |
| Handoff | $FORENSICS_HOME/scripts/handoff.sh |
| Validation fixtures | $FORENSICS_HOME/fixtures/ |
| Pentest profile | $HOME/.hermes/config.yaml |
| Forensics profile | $HERMES_PROFILE_DIR/config.yaml |
| Forensics persona | $HERMES_PROFILE_DIR/SOUL.md |

---

## Session Startup Protocol (Automated)

**PREFERRED: One-command bring-up (use this, not manual steps):**
```bash
bash $FORENSICS_HOME/scripts/forensics-up.sh
```
This single command: opens LUKS → starts SIFT VM → waits for SSH → checks Docker → runs session canary → reports status. System ready in ~60 seconds. No manual steps, no thinking required.

**If up.sh fails** (system not running), do minimal manual bring-up:
1. Check LUKS: `mountpoint -q $FORENSICS_HOME` — if not mounted, open manually
2. Check SIFT VM: `bash $FORENSICS_HOME/scripts/sift-exec.sh "echo OK"` — if not, start VM
3. Check Docker: `docker info >/dev/null 2>&1` — if not, `sudo systemctl start docker`
4. **Run canary:** `bash $FORENSICS_HOME/scripts/session-canary.sh`

### New Case (one command):
```bash
CASE_ID=$(bash $FORENSICS_HOME/scripts/forensics-case.sh "Description")
```

### Shutdown (one command):
```bash
bash $FORENSICS_HOME/scripts/forensics-down.sh
```

### Key Scripts Reference
| Script | Purpose |
|--------|---------|
| `$FORENSICS_HOME/scripts/forensics-up.sh` | Full system bring-up |
| `$FORENSICS_HOME/scripts/forensics-down.sh` | Clean shutdown |
| `$FORENSICS_HOME/scripts/forensics-case.sh` | Rapid case init |
| `$FORENSICS_HOME/scripts/forensics-register.sh` | Evidence registration (hash-verify-audit) |
| `$FORENSICS_HOME/scripts/forensics-vol3.sh` | Volatility3 Docker wrapper |
| `$FORENSICS_HOME/scripts/forensics-mount.sh` | MemProcFS mount/unmount |
| `$FORENSICS_HOME/scripts/forensics-find.sh` | Findings recorder |
| `$FORENSICS_HOME/scripts/forensics-report.sh` | Report generator (HTML + PDF) |
| `$FORENSICS_HOME/scripts/forensics-pipeline.sh` | End-to-end pipeline |
| `$FORENSICS_HOME/scripts/forensics-screenshots.py` | Evidence screenshots (terminal PNGs) |
| `$FORENSICS_HOME/scripts/forensics-artifacts.py` | Artifacts appendix generator |
| `$FORENSICS_HOME/scripts/session-canary.sh` | Tool validation (12 tools, 6 env) |
| `$FORENSICS_HOME/scripts/sift-exec.sh` | SSH wrapper for SIFT VM |

### Evidence Integrity Workflow
After running analysis tools, capture evidence screenshots before generating the report:
```bash
# 1. Capture screenshots of all raw tool output
python3 $FORENSICS_HOME/scripts/forensics-screenshots.py $FORENSICS_HOME/cases/CASE_ID
# - case/raw/screenshots/artifact-01.png ... artifact-NN.png

# 2. Generate report with appendix referencing screenshots
bash $FORENSICS_HOME/scripts/forensics-report.sh CASE_ID --html
bash $FORENSICS_HOME/scripts/forensics-report.sh CASE_ID --pdf
```

---

## Evidence Handling Protocol

### Case Creation (Automated)
Use the one-command script: `CASE_ID=$(bash $FORENSICS_HOME/scripts/forensics-case.sh "Description")`

Manual equivalent (if script unavailable):
1. Create: `mkdir -p $FORENSICS_HOME/cases/INC-YYYY-MMDD-NNNN/{evidence,raw,reports,audit}`
2. Write CASE.yaml with case_id, status=active, examiner=niel
3. Log to audit/actions.jsonl

### Evidence Registration
1. Hash: `sha256sum $FORENSICS_HOME/cases/CASE_ID/evidence/FILE`
2. Copy to case/evidence/
3. Set read-only: `chmod 444 $FORENSICS_HOME/cases/CASE_ID/evidence/FILE`
4. Register in evidence.json with evidence_id, sha256, source, tool
5. Log to audit/actions.jsonl

### Finding Standards
Every finding MUST include:
- Finding ID: F-examiner-NNN
- Tool + version + image hash
- Exact command executed
- Evidence reference (EVID-XXX)
- Raw output path
- Interpretation
- Confidence: HIGH / MEDIUM / LOW / TENTATIVE
- Cross-validation result

Confidence definitions:
- HIGH: Canary validated, encyclopedia match, known OS
- MEDIUM: Canary validated, single tool, known OS
- LOW: Canary passed, evidence OS unknown
- TENTATIVE: Canary failed — triage only

---

## Tool Selection Guide

| Artifact Type | Primary Tool | Fallback |
|--------------|-------------|----------|
| Windows memory dump | MemProcFS (mount + browse) | volatility3 |
| Linux memory dump | volatility3 | — |
| Disk image analysis | sleuthkit (fls/icat/istat) | — |
| MFT parsing | mft-tools (analyzeMFT) | MFTECmd (when available) |
| Timeline | plaso (log2timeline) | sleuthkit mactime |
| Registry | regripper | python-registry |
| File carving | foremost + photorec (both!) | — |
| Evidence hashing | hashdeep | sha256sum |
| Network capture | tshark | — |
| Malware in memory | MemProcFS findevil.txt | volatility3 malfind |

---

## Memory Forensics Strategy (MemProcFS-first)

1. Mount: `$MEMPROCFS_BIN -device DUMP -mount /mnt/mem -forensic 1`
2. Browse: `ls /mnt/mem/sys/proc/` — all processes as directories
3. Network: `cat /mnt/mem/sys/net/tcp.txt`
4. Malware: `cat /mnt/mem/forensic/findevil.txt`
5. Cross-validate with volatility3 for critical findings
6. Unmount: `fusermount -u /mnt/mem`

---

## Cross-Validation

For critical artifacts, consult the artifact encyclopedia for interpretation guidance and run a second tool for manual verification.
Delta >5% → flag for human review.

---

## Pentest ↔ Forensics Handoff

Pentest agent creates a handoff:
```bash
bash $FORENSICS_HOME/scripts/handoff.sh "Title" /path/to/evidence HIGH
```

Forensics agent checks for pending handoffs on session start. Look for handoff.json in $FORENSICS_HOME/cases/INC-*/ directories.

---

## Known Quirks

1. **HOME sandboxed** — all paths must be absolute (e.g. $FORENSICS_HOME/...). ~/ resolves wrong.
2. **volatility3 entrypoint** — Docker image entrypoint is `volatility`. No `vol` prefix needed in commands.
3. **MFTECmd unavailable** — Zimmerman tools CDN changed. analyzeMFT is the primary MFT parser.
4. **SIFT VM IP** — $SIFT_HOST (bridged networking). SSH key auth.
5. **SSHFS mount** — evidence visible at /home/$SIFT_USER/cases/ on VM. Read-only.
6. **SIFT tool paths on VM** — pass as /home/$SIFT_USER/cases/CASE_ID/evidence/FILE.
7. **Session canary** — DEGRADED tools are triage-only. Do not use for evidentiary analysis.
8. **Docker images** — never rebuild mid-investigation. If validation fails, flag it.
# File Carving

## When to Use
- Recovering deleted files from disk images
- Extracting files by file signature (headers/footers)
- Need to run both foremost AND photorec for completeness (different signature databases)

## Pre-flight
1. Read $FORENSICS_HOME/tools/tool-catalog.yaml
2. Both foremost AND photorec must be run — they use different signature DBs
3. Carving output goes to a subdirectory: /cases/CASE_ID/raw/carved/

## Workflow

### Step 1: Create output directory
```bash
mkdir -p $FORENSICS_HOME/cases/CASE_ID/raw/carved/{foremost,photorec}
```

### Step 2: Run foremost
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "foremost -i /cases/CASE_ID/evidence/DISK_IMAGE -o /cases/CASE_ID/raw/carved/foremost"
```

### Step 3: Run photorec
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "photorec /log /d /cases/CASE_ID/raw/carved/photorec /cases/CASE_ID/evidence/DISK_IMAGE"
```

### Step 4: Compare results
Both tools use different file signature databases — files found by one may not be found by the other.

### Step 5: Hash recovered files
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "hashdeep -c sha256 -r /cases/CASE_ID/raw/carved/"
```

### Step 6: Create findings
For significant recovered files: filename, format, size, hash, and relevance to case.

## Pitfalls
- NTFS compression: carved files may be incomplete
- File fragmentation: carvers recover the first fragment only
- Large images: carving runs for hours — warn user and use background execution
- False positives: carvers may produce junk files from random byte sequences
- Space requirement: carved output can exceed source image size

---

# Disk Imaging

## When to Use
- Creating a forensic image of a disk, partition, or removable media
- Verifying an existing image's integrity
- Converting between image formats (raw, E01, AFF)

## Pre-flight
1. Identify source: `bash $FORENSICS_HOME/scripts/sift-exec.sh "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL"`
2. Verify free space: `df -h $FORENSICS_HOME/cases/`
3. Read $FORENSICS_HOME/tools/tool-catalog.yaml for dc3dd known issues
4. Confirm NOT mounted: `bash $FORENSICS_HOME/scripts/sift-exec.sh "mount | grep DEVICE_NAME"`

## Workflow

### Step 1: Hash source (pre-image)
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "sudo hashdeep -c sha256 DEVICE > /cases/CASE_ID/raw/source-hash.txt"
```

### Step 2: Create image (dc3dd primary)
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "sudo dc3dd if=DEVICE of=/cases/CASE_ID/evidence/IMAGE_NAME.raw hash=sha256 log=/cases/CASE_ID/raw/dc3dd.log"
```

### Step 3: If dc3dd fails, fallback to ddrescue
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "sudo ddrescue -f DEVICE /cases/CASE_ID/evidence/IMAGE_NAME.raw /cases/CASE_ID/raw/ddrescue.log"
```

### Step 4: Verify image hash matches source
Compare source-hash.txt vs image hash.

### Step 5: Set read-only
```bash
chmod 444 $FORENSICS_HOME/cases/CASE_ID/evidence/IMAGE_NAME.raw
```

### Step 6: Register in evidence.json

## Pitfalls
- Kernel I/O scheduler: dc3dd block size may drift on 6.x+ kernels — ALWAYS verify hash
- SSD TRIM: SSDs return zeros for trimmed blocks — image immediately after seizure
- USB disconnect: always verify hash post-image
- NEVER image a mounted filesystem — writes happen during imaging
- Write-blocker: for evidentiary imaging, always use hardware write-blocker
