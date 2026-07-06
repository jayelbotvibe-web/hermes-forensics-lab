# Validation Fixtures

This directory contains validation test images for the session canary and tool
validation scripts. Each entry documents a known-good evidence sample, its
expected hash, and the findings it should produce — enabling deterministic
"does this tool still work?" checks.

**No large binary evidence files are committed to the repo.** Only this manifest
with hashes and expected findings is tracked. Binary files are treated as
`.gitignore`-excluded evidence artifacts obtained from public CTF sources.

---

## Included Fixtures

### BelkaCTF #7 — Compromised ATC Workstation Memory Dump

| Field | Value |
|-------|-------|
| **File** | `belkactf7-dump.mem` |
| **Source** | BelkaCTF #7 / CyberMirror (https://belkactf.github.io/) |
| **SHA-256** | `<download-and-hash>` |
| **Size** | ~2 GB (Windows 10 memory dump) |
| **Type** | Windows memory dump (Win10P x64) |

**Expected findings (canary checks):**

| Tool | Validation | Expected Output |
|------|-----------|-----------------|
| MemProcFS mount | `ls <mount>/sys/proc/` returns 50+ process dirs | PID directories present |
| MemProcFS findevil | `cat <mount>/forensic/findevil.txt` flags 3+ modules | 3 suspicious modules detected |
| volatility3 pslist | `vol -f dump.mem windows.pslist` | 50+ processes listed |
| volatility3 netscan | `vol -f dump.mem windows.netscan` | Network connections present |
| volatility3 malfind | `vol -f dump.mem windows.malfind` | Injected code detected |

**Expected MITRE ATT&CK mappings (from known case analysis):**

| Finding | Technique | Artifact |
|---------|-----------|----------|
| Typo-squatted process name | T1036.005 | `epxlorer.exe` (PID 9920) |
| Browser download artifact | T1566.001 / T1204.002 | `.crdownload` ADS marker |
| C2 beacon over HTTPS | T1071.001 / T1573 | `104.21.1.247:443` from PID 9920 |
| Encrypted C2 channel | T1573 | Consistent packet size, periodic |

---

## Adding New Fixtures

1. Obtain a known-good evidence sample from a public CTF or sanctioned source
2. Hash it: `sha256sum <file>`
3. Add a new section above with the hash and expected findings
4. **Do NOT commit the binary file** — add it to `.gitignore` and document
   where to obtain it
5. Update `encyclopedia/mitre-allowlist.txt` if new ATT&CK IDs are referenced
