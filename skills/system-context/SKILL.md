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
HOST (terminal.backend: local, HOME=/home/niel/.hermes/profiles/forensics/home)
├── Docker images: volatility3, plaso, mft-tools — run with `docker run --rm`
├── Host binary: MemProcFS v5.17.8 at /home/niel/memprocfs/memprocfs
├── Evidence: /home/niel/forensics/cases/ (LUKS encrypted, 30GB)
├── Fixtures: /home/niel/forensics/fixtures/
├── Scripts: /home/niel/forensics/scripts/
└── SIFT VM: 192.168.88.14 — SSH key auth — sansforensics user
        │
        ├── Evidence mounted at: ~/cases/ (SSHFS from host)
        └── Native tools: sleuthkit, foremost, dc3dd, regripper, hashdeep, tshark
```

**CRITICAL:** All file paths must be ABSOLUTE (/home/niel/...). The profile sandboxes $HOME to /home/niel/.hermes/profiles/forensics/home. Never use ~/ or $HOME in paths.

---

## Tool Inventory (12 tools, 3 runtimes)

### Runtime 1: Host Docker
| Tool | Image | Version | Command Pattern |
|------|-------|---------|----------------|
| volatility3 | forensics-volatility3:2.7.0 | 2.7.0 | `docker run --rm -v /home/niel/forensics/cases/CASE_ID:/evidence:ro -v /home/niel/forensics/cases/CASE_ID/raw:/output forensics-volatility3:2.7.0 -f /evidence/FILE PLUGIN` |
| plaso | forensics-plaso:20240512 | 20240512 | `docker run --rm -v /home/niel/forensics/cases/CASE_ID:/evidence:ro -v /home/niel/forensics/cases/CASE_ID/raw:/output forensics-plaso:20240512 log2timeline.py --storage-file /output/timeline.plaso /evidence/FILE` |
| mft-tools | forensics-mft-tools:1.2.0.0 | 1.2.0.0 | `docker run --rm -v /home/niel/forensics/cases/CASE_ID:/evidence:ro -v /home/niel/forensics/cases/CASE_ID/raw:/output forensics-mft-tools:1.2.0.0 python3 -m analyzemft -f /evidence/FILE -o /output/analyzemft.csv` |

5. **IMPORTANT:** volatility3 Docker entrypoint is already `vol` — the binary inside the container is called `vol` (not `volatility`). Never prefix commands with `vol`. Start directly with flags: `-f /evidence/dump.mem windows.info.Info`.

### Runtime 2: Host FUSE — MemProcFS
| Tool | Binary | Version | Command Pattern |
|------|--------|---------|----------------|
| MemProcFS | /home/niel/memprocfs/memprocfs | 5.17.8 | `mkdir -p /mnt/mem && /home/niel/memprocfs/memprocfs -device DUMP_FILE -mount /mnt/mem -forensic 1` |

Unmount: `fusermount -u /mnt/mem`
Key paths after mount: /mnt/mem/sys/proc/ (processes), /mnt/mem/sys/net/ (network), /mnt/mem/forensic/findevil.txt (malware detection)
Windows dumps only. For Linux dumps, use volatility3.

### Runtime 3: SIFT VM (SSH wrapper)
Execute via: `bash /home/niel/forensics/scripts/sift-exec.sh "COMMAND"`

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

Evidence is visible at: `/home/sansforensics/cases/` on the VM (SSHFS mount from host).
Pass paths as: `/home/sansforensics/cases/CASE_ID/evidence/FILE`

---

## Key Paths (ALL ABSOLUTE)

| Purpose | Path |
|---------|------|
| Evidence root | /home/niel/forensics/cases/ |
| Case template | /home/niel/forensics/cases/INC-YYYY-MMDD-NNNN/ |
| Tool catalog | /home/niel/forensics/tools/tool-catalog.yaml |
| Session canary | /home/niel/forensics/scripts/session-canary.sh |
| Cross-validation | /home/niel/forensics/scripts/cross-validate.sh |
| SSH wrapper | /home/niel/forensics/scripts/sift-exec.sh |
| Handoff | /home/niel/forensics/scripts/handoff.sh |
| Validation fixtures | /home/niel/forensics/fixtures/ |
| Pentest profile | /home/niel/.hermes/config.yaml |
| Forensics profile | /home/niel/.hermes/profiles/forensics/config.yaml |
| Forensics persona | /home/niel/.hermes/profiles/forensics/SOUL.md |

---

## Session Startup Protocol

**ALWAYS run these steps at session start, BEFORE any investigation:**

1. **Run canary:** `bash /home/niel/forensics/scripts/session-canary.sh`
   - Validates all 12 tools
   - Reports DEGRADED tools — these are TRIAGE-ONLY

2. **Read tool catalog:** `cat /home/niel/forensics/tools/tool-catalog.yaml`
   - Contains version pins, known issues, fallback chains for every tool

3. **Check for active cases:** `ls /home/niel/forensics/cases/`
   - Look for handoff.json files from pentest agent

4. **Verify SIFT evidence mount:** `bash /home/niel/forensics/scripts/sift-exec.sh "ls ~/cases/"`

---

## Evidence Handling Protocol

### Case Creation
1. Create: `mkdir -p /home/niel/forensics/cases/INC-YYYY-MMDD-NNNN/{evidence,raw,reports,audit}`
2. Write CASE.yaml with case_id, status=active, examiner=niel
3. Log to audit/actions.jsonl

### Evidence Registration
1. Hash: `sha256sum /home/niel/forensics/cases/CASE_ID/evidence/FILE`
2. Copy to case/evidence/
3. Set read-only: `chmod 444 /home/niel/forensics/cases/CASE_ID/evidence/FILE`
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
- HIGH: Canary validated, dual-tool cross-checked, known OS
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

1. Mount: `/home/niel/memprocfs/memprocfs -device DUMP -mount /mnt/mem -forensic 1`
2. Browse: `ls /mnt/mem/sys/proc/` — all processes as directories
3. Network: `cat /mnt/mem/sys/net/tcp.txt`
4. Malware: `cat /mnt/mem/forensic/findevil.txt`
5. Cross-validate with volatility3 for critical findings
6. Unmount: `fusermount -u /mnt/mem`

---

## Cross-Validation

For critical artifacts (MFT, registry), run dual-tool verification:
```bash
bash /home/niel/forensics/scripts/cross-validate.sh mft /path/to/mft CASE_DIR
```
Delta >5% → flag for human review.

---

## Pentest ↔ Forensics Handoff

Pentest agent creates a handoff:
```bash
bash /home/niel/forensics/scripts/handoff.sh "Title" /path/to/evidence HIGH
```

Forensics agent checks for pending handoffs on session start. Look for handoff.json in /home/niel/forensics/cases/INC-*/ directories.

---

## Known Quirks

1. **HOME sandboxed** — all paths must be absolute (/home/niel/...). ~/ resolves wrong.
2. **volatility3 entrypoint** — Docker image entrypoint is `volatility`. No `vol` prefix needed in commands.
3. **MFTECmd unavailable** — Zimmerman tools CDN changed. analyzeMFT is the primary MFT parser.
4. **SIFT VM IP** — 192.168.88.14 (bridged networking). SSH key auth.
5. **SSHFS mount** — evidence visible at /home/sansforensics/cases/ on VM. Read-only.
6. **SIFT tool paths on VM** — pass as /home/sansforensics/cases/CASE_ID/evidence/FILE.
7. **Session canary** — DEGRADED tools are triage-only. Do not use for evidentiary analysis.
8. **Docker images** — never rebuild mid-investigation. If validation fails, flag it.
