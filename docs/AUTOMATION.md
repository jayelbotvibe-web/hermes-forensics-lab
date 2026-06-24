# Forensics Automation Scripts

> **One command, system ready.** No more walking the runbook — these scripts collapse the entire bring-up, case initialization, and shutdown workflow into single commands.

---

## Quick Start

```bash
# Bring everything online (~60 seconds)
bash ~/forensics/scripts/forensics-up.sh

# Create a new case (returns CASE_ID to stdout)
CASE_ID=$(bash ~/forensics/scripts/forensics-case.sh "BelkaCTF 7 — Memory Dump Analysis")

# Work... (download evidence, run vol3, analyze, report)

# Shut down cleanly
bash ~/forensics/scripts/forensics-down.sh
```

**That's it.** Three commands, no manual steps, no runbook, no thinking.

---

## Script Reference

### `forensics-up.sh` — System Bring-Up

**What it does:**
1. Opens and mounts the LUKS-encrypted evidence volume
2. Starts the SIFT Workstation VM and waits for SSH
3. Verifies Docker is running with forensic images
4. Runs the session canary (validates all 12 tools)
5. Reports full system status

**Expected output (all green):**
```
╔══════════════════════════════════════════════╗
║   Hermes Forensics — Environment Bring-Up    ║
╚══════════════════════════════════════════════╝

[1/4] LUKS Evidence Volume
  ✓ Already mounted at /home/niel/forensics
  6.5G used / 30G total

[2/4] SIFT Workstation VM
  ✓ VM already running
  ✓ SSH ready — up 6 minutes — IP: 172.16.146.128

[3/4] Docker Runtime
  ✓ Docker running — 6 forensic images

[4/4] Session Canary
=== Results: 9 passed, 0 failed ===
✓ All tools operational

╔══════════════════════════════════════════════╗
║   ✓ FORENSICS SYSTEM READY                   ║
╚══════════════════════════════════════════════╝
```

**Options:**
- Set `FORENSICS_KEYFILE` env var to use a non-default LUKS keyfile path
- Set `SIFT_HOST` env var to override the default VM IP

---

### `forensics-case.sh` — Case Initialization

**What it does:**
1. Generates a case ID: `INC-YYYY-MMDD-NNNN` (auto-increments)
2. Creates the full directory structure under `/home/niel/forensics/cases/`
3. Writes `CASE.yaml`, empty `evidence.json`, `findings.json`, `timeline.json`
4. Initializes `audit/actions.jsonl` with the case_open event
5. Prints case info to stderr, returns CASE_ID to stdout

**Usage:**
```bash
# Interactive — see the output
bash forensics-case.sh "Case description"

# Capture CASE_ID for scripting
CASE_ID=$(bash forensics-case.sh "Case description")
echo "Case: $CASE_ID"

# View help
bash forensics-case.sh --help
```

**Structure created:**
```
INC-YYYY-MMDD-NNNN/
├── CASE.yaml              # Case metadata (status, examiner, description)
├── evidence.json          # Evidence registry (empty — register evidence here)
├── findings.json          # Findings register (empty — add findings here)
├── timeline.json          # Event timeline (empty — add events here)
├── evidence/              # ← Copy evidence here, then chmod 444
├── raw/                   # ← Tool output goes here
├── reports/               # ← Final reports
└── audit/actions.jsonl    # Chain of custody
```

---

### `forensics-down.sh` — System Shutdown

**What it does:**
1. Unmounts all MemProcFS mounts
2. Gracefully stops the SIFT Workstation VM (30s timeout, then force-stop)
3. Locks the LUKS evidence volume

**Usage:**
```bash
# Interactive — confirmation prompt
bash forensics-down.sh

# Skip confirmation (for scripting)
bash forensics-down.sh --force

# View help
bash forensics-down.sh --help
```

---

## Troubleshooting

### SIFT VM Not Reachable

**Symptom:** `forensics-up.sh` shows "SIFT VM SSH unreachable"

**Causes & fixes:**

| Cause | Fix |
|-------|-----|
| VM not started | Script auto-starts it — wait 3 minutes for cold boot |
| IP changed (bridged networking) | Switch to NAT: edit VMX → `ethernet0.connectionType = "nat"` |
| DHCP lease expired | Script auto-retries with VM restart (2 cycles) |
| SSH key not installed | `ssh-copy-id sansforensics@<VM_IP>` |
| VMware networking dead | `sudo vmware-networks --stop && sudo vmware-networks --start` |

**Manual check:**
```bash
vmrun list                                    # Is VM running?
ssh sansforensics@172.16.146.128 'echo OK'    # Can we SSH?
bash ~/forensics/scripts/sift-exec.sh whoami  # Wrapper test
```

### LUKS Won't Mount

**Symptom:** "LUKS NOT MOUNTED — cannot proceed"

**Causes & fixes:**

| Cause | Fix |
|-------|-----|
| Keyfile missing/wrong password | `echo -n '<password>' > ~/.forensics-keyfile && chmod 600 ~/.forensics-keyfile` |
| LUKS image not at expected path | Check `~/forensics.img` exists |
| cryptsetup not installed | `sudo apt install cryptsetup` |
| Device mapper busy | `sudo cryptsetup close forensics_crypt` then retry |

**Manual mount:**
```bash
echo -n '<password>' | sudo cryptsetup open ~/forensics.img forensics_crypt --key-file=-
sudo mount /dev/mapper/forensics_crypt ~/forensics
sudo chown $USER:$USER ~/forensics
```

### Docker Not Accessible

**Symptom:** "Docker not accessible"

**Fix:**
```bash
sudo systemctl start docker
# Verify: docker run --rm hello-world
```

### Canary Failures

**Symptom:** Specific tool shows "FAIL — DEGRADED"

**Degraded tools are TRIAGE-ONLY.** Do not use them for evidentiary analysis.

| Tool | Common fix |
|------|-----------|
| volatility3 | `docker pull` the image, rebuild if needed |
| plaso | Same — `docker pull forensics-plaso:latest` |
| mft-tools | Same — `docker pull forensics-mft-tools:latest` |
| SIFT tools | VM may need `sudo apt install --reinstall <package>` |

### Case Script Numbering Issues

**Symptom:** Case numbers jump unexpectedly

**Cause:** The script finds the highest existing case number for today's date. Old cases with high numbers will cause the next number to be high.

**Fix:** Clean up old test case directories from `/home/niel/forensics/cases/`

---

## Architecture Notes

### SIFT VM Networking (NAT)

The SIFT VM runs on VMware NAT networking (`vmnet8`) at `172.16.146.128`. This is more reliable than bridged networking because:
- DHCP lease comes from VMware's internal server, never expires across sessions
- No dependency on external network or WiFi AP
- IP is stable across reboots

**To switch from bridged to NAT:**
```bash
# In the VMX file:
ethernet0.connectionType = "nat"

# Restart VM
vmrun -T ws stop SIFT.vmx
vmrun -T ws start SIFT.vmx nogui
```

### LUKS Keyfile

The bring-up script uses a keyfile at `~/.forensics-keyfile` for passwordless LUKS opening. Set it up once:
```bash
echo -n 'your-password' > ~/.forensics-keyfile
chmod 600 ~/.forensics-keyfile
```

Override the path: `FORENSICS_KEYFILE=/path/to/keyfile bash forensics-up.sh`

---

## Script Locations

| Script | Path |
|--------|------|
| System bring-up | `/home/niel/forensics/scripts/forensics-up.sh` |
| Case initialization | `/home/niel/forensics/scripts/forensics-case.sh` |
| System shutdown | `/home/niel/forensics/scripts/forensics-down.sh` |
| Session canary | `/home/niel/forensics/scripts/session-canary.sh` |
| SIFT SSH wrapper | `/home/niel/forensics/scripts/sift-exec.sh` |
| Cross-validation | `/home/niel/forensics/scripts/cross-validate.sh` |
| Handoff (pentest↔forensics) | `/home/niel/forensics/scripts/handoff.sh` |

---

> **Last updated:** 2026-06-24 — v2.0 with review fixes applied
