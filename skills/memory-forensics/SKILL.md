---
name: memory-forensics
description: "Memory dump analysis — MemProcFS primary (filesystem mount), volatility3 fallback"
version: 2.0.0
category: forensics
---

# Memory Forensics

## Tool Strategy
- **Primary: MemProcFS v5.17.8** — mounts dump as virtual filesystem at /mnt/mem
- **Fallback: volatility3 2.7.0** — for Linux dumps, malware analysis, cross-validation
- **Rule:** Always try MemProcFS first. If dump is non-Windows, use volatility3.

## Pre-flight
1. Run session canary
2. Read /home/niel/forensics/tools/tool-catalog.yaml — check memprocfs + volatility3 entries
3. Record dump hash

## Workflow (MemProcFS — Primary)

### Step 1: Mount the memory dump
```bash
mkdir -p /mnt/mem
/home/niel/memprocfs/memprocfs -device /home/niel/forensics/cases/CASE_ID/evidence/DUMP_FILE -mount /mnt/mem -forensic 1
```
This mounts the dump as a virtual filesystem. The agent can now browse it like a directory.

### Step 2: Browse processes
```bash
ls /mnt/mem/sys/proc/              # All processes as directories
cat /mnt/mem/sys/proc/proc.txt     # Process list with PIDs, names, paths
cat /mnt/mem/sys/proc/proc-vad.txt # Virtual Address Descriptors (memory regions)
cat /mnt/mem/sys/proc/proc-dlls.txt # Loaded DLLs per process
```

### Step 3: Network connections
```bash
cat /mnt/mem/sys/net/tcp.txt       # TCP connections
cat /mnt/mem/sys/net/udp.txt       # UDP listeners
cat /mnt/mem/sys/net/net.txt       # All network summary
```

### Step 4: Registry in memory
```bash
ls /mnt/mem/sys/registry/          # Registry hives loaded in memory
```

### Step 5: Files in memory
```bash
ls /mnt/mem/sys/files/             # Files referenced in memory
```

### Step 6: Auto-detected malware
```bash
cat /mnt/mem/forensic/findevil.txt # Auto-generated malware detection report
cat /mnt/mem/forensic/forensic.txt # Full forensic scan results
```

### Step 7: Unmount
```bash
fusermount -u /mnt/mem
```

## Workflow (volatility3 — Fallback)

Use when: dump is Linux/macOS, or need specific plugin MemProcFS doesn't cover (malfind, yarascan).

### System info
```bash
docker run --rm \
  -v /home/niel/forensics/cases/CASE_ID:/evidence:ro \
  -v /home/niel/forensics/cases/CASE_ID/raw:/output \
  forensics-volatility3:2.7.0 \
  -f /evidence/DUMP_FILE windows.info.Info > /output/info.json
```

### Process list + hidden processes
```bash
docker run --rm \
  -v /home/niel/forensics/cases/CASE_ID:/evidence:ro \
  forensics-volatility3:2.7.0 \
  -f /evidence/DUMP_FILE windows.pslist.PsList > /output/pslist.csv
docker run --rm \
  -v /home/niel/forensics/cases/CASE_ID:/evidence:ro \
  forensics-volatility3:2.7.0 \
  -f /evidence/DUMP_FILE windows.psscan.PsScan > /output/psscan.csv
```

### Malware detection
```bash
docker run --rm \
  -v /home/niel/forensics/cases/CASE_ID:/evidence:ro \
  forensics-volatility3:2.7.0 \
  -f /evidence/DUMP_FILE windows.malfind.Malfind > /output/malfind.json
```

## Cross-Validation
For critical findings:
1. Compare MemProcFS process list vs volatility3 pslist + psscan
2. Compare MemProcFS network output vs volatility3 netscan
3. If significant discrepancies, flag for human review

## Pitfalls
- MemProcFS is Windows-only — Linux dumps need volatility3
- /mnt/mem must be empty before mounting
- Always unmount with fusermount -u after analysis
- Large dumps (>8GB): MemProcFS loads into RAM, monitor memory usage
- volatility3 Docker image entrypoint is already 'volatility' — start commands with flags directly, no 'vol' prefix
