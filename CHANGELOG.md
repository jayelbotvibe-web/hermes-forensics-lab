# Changelog

All notable changes to the Hermes Forensics Lab.

## [4.2.0] — 2026-07-09

### Fixed
- session-canary.sh: now probes all 8 SIFT tools from the Tool Inventory — photorec and ddrescue were previously never checked despite README claiming 12/12 validation
- session-canary.sh: MemProcFS version is now read from the actual binary and compared against the catalog pin (was a hardcoded "v5.17.8" string that would never detect an upgrade/downgrade)
- session-canary.sh: SIFT tool labels now match Tool Inventory names (sleuthkit, not fls)
- session-canary.sh: when the SIFT VM is unreachable, its 8 tools are counted as DEGRADED in the totals instead of silently disappearing (4/12, not 4/4)
- session-canary.sh: LUKS vault and SIFT SSH reclassified from TOOLS to ENVIRONMENT — tool count now maps 1:1 to the 12-tool inventory
- mft-tools/validate.sh: MFTECmd invoked via dotnet (was mono, which was never installed); validation failures now exit non-zero instead of warning and passing
- README + AUTOMATION.md: canary example outputs now match what the script actually prints

### Added
- mft-tools Dockerfile: MFTECmd (Eric Zimmerman, .NET 9) is now actually installed — previously referenced in validate.sh, tool-catalog.yaml, and the README cross-validation example but absent from the image. Archive is SHA256-pinned so a silent upstream release change fails the build loudly; version recorded at build time in /opt/mftecmd/VERSION
- session-canary.sh: MEMPROCFS_EXPECTED_VERSION env override for catalog version pin

### Changed
- project-metadata.yaml: canary_checks corrected to 20 (12 tools + 8 environment)
- Canary badge: 12 tools + 8 env

## [4.1.0] — 2026-07-03

### Fixed
- Documentation audit: canonicalized all tool counts (12), script counts (7), and version numbers (v4.1)
- Sleuthkit version corrected from 4.12.1 to 4.11.1 (per tool-catalog.yaml source of truth)
- Sample report: removed `?` placeholders for sift-vm and session_canary infrastructure rows
- Sample report: fixed DEGRADED status inconsistency with section header claim
- Sample report: redacted Telegram bot token for public publication safety
- Removed undefined internal jargon ("ponytail-pruned") from site copy

### Added
- project-metadata.yaml: single source of truth for counts and versions
- CHANGELOG.md (this file): version history tracking
- Sanitization note on sample reports
- Infrastructure note on tools table explaining SIFT VM / canary as environment

### Changed
- README: sample report link moved above the fold for zero-setup proof-of-work
- README: all badge numbers and canary examples now match actual values
- index.html: all stats unified to canonical counts
- docs/AUTOMATION.md: version and canary output updated
- docs/forensics-architecture.html: sleuthkit version + version number corrected
- forensics-report.sh: tools table now skips infrastructure entries (sift-vm, session_canary)

## [4.0.0] — 2026-06-24

### Added
- Data-first report template (primary) with labeled sections 01–09
- 25-entry artifact interpretation encyclopedia (forensic-artifacts skill)
- Sample BelkaCTF #7 report (HTML + PDF)
- 7 automation scripts: forensics-up, forensics-down, forensics-case, session-canary, cross-validate, sift-exec, handoff
- Analysis scripts: register, vol3, mount, find, report, screenshots, artifacts, pipeline
- Docker-pinned tools: volatility3 2.7.0, plaso 20240512, mft-tools 1.2.0.0
- SIFT VM native tools: sleuthkit 4.11.1, foremost 1.5.7, dc3dd 7.3.1, ddrescue 1.27, regripper 3.0, hashdeep 4.4, tshark 4.0
- MemProcFS 5.17.8 memory forensics
- Session canary: automated tool validation on every session start
- Cross-validation engine: dual-tool corroboration for critical artifacts
- Chain-of-custody audit trail
- Pentest-to-forensics handoff integration (handoff.sh)

### Changed
- Architecture decision: Docker on host (not in VM), terminal.backend: local
- SIFT VM networking: NAT (vmnet8) replaces bridged for stability
- HOME sandbox awareness: all paths use absolute references
