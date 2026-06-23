# Hermes Forensics Lab

> **AI-assisted digital forensics system built on Hermes Agent + SIFT Workstation**
>
> 12 forensic tools • 3 runtimes • automated validation • human-in-the-loop

[![Hermes](https://img.shields.io/badge/Hermes-Agent-34d399)](https://github.com/NousResearch/hermes-agent)
[![Tools](https://img.shields.io/badge/tools-12-22d3ee)](#tool-inventory)
[![Canary](https://img.shields.io/badge/canary-9/9-brightgreen)](scripts/session-canary.sh)

---

## Architecture

![Forensics System Architecture](architecture.svg)

**[→ Full interactive version](index.html)**

---

## Tool Inventory

| # | Tool | Runtime | Version | Primary Use |
|---|------|---------|---------|------------|
| 1 | **MemProcFS** | Host FUSE | 5.17.8 | Memory analysis (filesystem mount) |
| 2 | volatility3 | Docker | 2.7.0 | Memory analysis (Linux dumps, cross-val) |
| 3 | plaso | Docker | 20240512 | Super timeline generation |
| 4 | mft-tools | Docker | 1.2.0.0 | MFT parsing (analyzeMFT) |
| 5 | sleuthkit | SIFT VM | 4.11.1 | Filesystem forensics |
| 6 | foremost | SIFT VM | 1.5.7 | File carving |
| 7 | photorec | SIFT VM | 7.1 | File carving (different sig DB) |
| 8 | dc3dd | SIFT VM | 7.3.1 | Forensic imaging |
| 9 | ddrescue | SIFT VM | 1.27 | Damaged media imaging |
| 10 | regripper | SIFT VM | 3.0 | Registry analysis |
| 11 | hashdeep | SIFT VM | 4.4 | Evidence hashing |
| 12 | tshark | SIFT VM | 4.0 | Network capture analysis |

---

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/jayelbotvibe-web/hermes-forensics-lab.git
cd hermes-forensics-lab

# 2. Build Docker images
docker build -t forensics-volatility3:2.7.0 tools/volatility/
docker build -t forensics-plaso:20240512 tools/plaso/
docker build -t forensics-mft-tools:1.2.0.0 tools/mft-tools/

# 3. Install MemProcFS (Linux x64)
wget https://github.com/ufrisk/MemProcFS/releases/latest -O memprocfs.tar.gz
tar xzf memprocfs.tar.gz
sudo apt install -y libfuse2t64 lz4

# 4. Set up SIFT VM (see SETUP.md below)
# 5. Start the forensics agent
hermes -p forensics
```

---

## Hermes Agent Integration

This system runs as a **Hermes Agent profile** (`forensics`). The profile includes:

- **Persona**: Stability-first DFIR analyst — evidence-sovereign, verification-obsessed
- **9 Skills**: evidence-handling, memory-forensics, filesystem-forensics, mft-analysis, registry-analysis, timeline-analysis, file-carving, disk-imaging, system-context
- **Session canary**: Auto-validates all 12 tools on every session start
- **Tool catalog**: Version-pinned, fallback chains, known issues documented
- **Human-in-the-loop**: All findings DRAFT until examiner approves

### Skills

| Skill | Description |
|-------|------------|
| [system-context](skills/system-context/SKILL.md) | Full architecture map, tool locations, operational procedures |
| [evidence-handling](skills/evidence-handling/SKILL.md) | Chain of custody, case creation, evidence registration |
| [memory-forensics](skills/memory-forensics/SKILL.md) | MemProcFS-first memory analysis + volatility3 fallback |
| [filesystem-forensics](skills/filesystem-forensics/SKILL.md) | Sleuth Kit — file listing, inode extraction, mactime |
| [mft-analysis](skills/mft-analysis/SKILL.md) | MFT parsing with analyzeMFT, timestomping detection |
| [registry-analysis](skills/registry-analysis/SKILL.md) | Registry hive analysis, persistence detection |
| [timeline-analysis](skills/timeline-analysis/SKILL.md) | Super timeline with plaso, fallback to mactime |
| [file-carving](skills/file-carving/SKILL.md) | foremost + photorec dual-tool carving |
| [disk-imaging](skills/disk-imaging/SKILL.md) | dc3dd/ddrescue imaging with hash verification |

### Coordination with Pentest Agent

A companion [pentest lab](https://github.com/jayelbotvibe-web/hermes-pentest-lab) can hand off evidence to the forensics agent:

```bash
# Pentest agent creates a handoff:
bash scripts/handoff.sh "Suspicious DC01 memory dump" /path/to/dump.mem HIGH

# Forensics agent picks it up on next session start
hermes -p forensics
```

---

## Session Canary

Every session starts with automated tool validation:

```bash
bash scripts/session-canary.sh
```

Output:
```
=== Forensics Session Canary ===
[docker:volatility3] PASS
[docker:plaso] PASS
[docker:mft-tools] PASS
[sift:connectivity] PASS
[sift:sleuthkit] PASS
[sift:foremost] PASS
[sift:photorec] PASS
[sift:dc3dd] PASS
[sift:ddrescue] PASS
[sift:regripper] PASS
[sift:hashdeep] PASS
[sift:tshark] PASS
=== Results: 12 passed, 0 failed ===
✓ All tools operational
```

Failed tools are marked **DEGRADED** — triage-only, not for evidentiary analysis.

---

## Design Principles

### Stability-First
- Docker images are **immutable and version-pinned** — no `latest` tags
- `validate.sh` per tool image — catches silent breakage
- **Never install tools mid-investigation** — if missing, flag it
- **Dual-tool cross-validation** for critical artifacts — MFT, registry, event logs
- Delta >5% between tools → flagged for human review

### Evidence Sovereignty
- Evidence is read-only after registration (`chmod 444`)
- Every finding includes: tool + version + image hash + exact command
- Chain of custody logged to JSONL audit trail
- **Human-in-the-loop**: AI presents findings as DRAFT; examiner approves

### MemProcFS-First Memory Analysis
Instead of memorizing 200+ volatility3 plugin names, the agent mounts the memory dump as a virtual filesystem and browses it:

```bash
memprocfs -device dump.mem -mount /mnt/mem -forensic 1
ls /mnt/mem/sys/proc/          # All processes as directories
cat /mnt/mem/sys/net/tcp.txt    # Network connections
cat /mnt/mem/forensic/findevil.txt  # Auto-detected malware
```

volatility3 remains as fallback for Linux dumps and cross-validation.

---

## Requirements

- **Hermes Agent** (https://github.com/NousResearch/hermes-agent)
- **Docker** (on host, for volatility3, plaso, mft-tools)
- **SIFT Workstation VM** (Ubuntu 22.04 + forensic tools via apt)
- **VMware Workstation** or KVM/QEMU (for the VM)
- **libfuse2** (for MemProcFS)
- **SSH key auth** to SIFT VM

---

## Related

- [Hermes Pentest Lab](https://github.com/jayelbotvibe-web/hermes-pentest-lab) — companion offensive security agent
- [MemProcFS](https://github.com/ufrisk/MemProcFS) — memory process file system
- [SIFT Workstation](https://www.sans.org/tools/sift-workstation) — SANS forensic toolkit
- [Volatility3](https://github.com/volatilityfoundation/volatility3) — memory forensics framework

---

## License

MIT — toolkit and documentation. Individual tools retain their own licenses (GPL, AGPL, Apache 2.0).
