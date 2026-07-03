# Changelog

All notable changes to the Hermes Forensics Lab.

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
