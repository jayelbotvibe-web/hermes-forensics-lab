# Changelog

All notable changes to the Hermes Forensics Lab.

## [4.4.0] — 2026-07-21

### Added
- **`install.sh`** — one-command bootstrap with three levels: `--minimal` (host-only),
  interactive (full), and `--dry-run`. Targeted re-runs via `--config-only`,
  `--images-only`, `--deps-only`, `--memprocfs-only`, `--profile-only`.
- **`scripts/create-evidence-vault.sh`** — creates the LUKS2 evidence container.
  This was a hard prerequisite of `forensics-up.sh` that no script created and no
  document described; a new user could not get past bring-up. Rolls back cleanly
  on failure rather than leaving a half-built vault.
- **`scripts/provision-sift.sh`** — provisions the SIFT VM from the host: installs
  the SSH key, apt-installs the eight tools, configures the read-only sshfs mount,
  and persists `SIFT_HOST`/`SIFT_USER` to the config. `--check` re-verifies.
- **`scripts/forensics-doctor.sh`** — diagnoses every component and prints the exact
  fix command for each gap. Exit 0 ready / 1 degraded / 2 blocked.
- **`scripts/lib/common.sh`** — single config loader for all scripts. Resolution
  order: environment → config file → built-in default. Parses rather than sources
  the config file; lines with shell metacharacters are refused, not executed.
- **`forensics.conf.example`** — every setting documented with its default.
- **`Makefile`** and **`docker-compose.yml`** — `make install|doctor|test|up|down`;
  compose builds the three images reproducibly and mounts evidence read-only.
- **`INSTALL.md`** — replaces `SETUP.md`. Three install levels with honest time
  costs (1 min / 20 min / 2 h), configuration reference, and troubleshooting.
- **Host-only mode** — `SIFT_ENABLED=false` or an unset `SIFT_HOST` is now a
  supported configuration. The canary reports the eight VM tools as `SKIP` and
  scores 4/4 instead of misreporting 4/12 DEGRADED.
- CI now runs both test suites, checks the encyclopedia is regenerable, and gates
  against hardcoded home directories and VM addresses returning.

### Fixed
- **96 hardcoded `/home/niel/...` paths** across all six skill docs and `persona.md`
  replaced with `$FORENSICS_HOME`, `$MEMPROCFS_BIN`, and `$HERMES_PROFILE_DIR`.
  These are agent-facing instructions, so a second user's agent was being told to
  read paths that did not exist.
- **`SIFT_HOST` contradiction** — `SETUP.md` documented `192.168.88.14` while every
  script defaulted to `172.16.146.128`. There is now no default: the address lives
  in one config file, and an unset value means host-only rather than a phantom host.
- **`encyclopedia/generate.py` silently destroyed documentation** — it regenerated
  `SKILL.md` from YAML but did not reproduce the two hand-written appendices,
  deleting 105 lines on every run. It also ignored `--help` and wrote immediately.
  The appendices now live in `encyclopedia/appendices/` and are appended by the
  generator; `--check` verifies without writing and unknown arguments are rejected.
- `entries/network-unusual-port.yaml` had drifted from the committed `SKILL.md`
  (`T1571` vs `T1571 (Non-Standard Port)`); MITRE values now carry optional
  annotations, validated against the allowlist by bare ID.
- `forensics-down.sh` referenced `$FORENSICS_HOME` without defining it — under
  `set -u` the script aborted immediately.
- `session-canary.sh` probed `/dev/mapper/forensics-vault` while the vault was
  created as `forensics_crypt`, so the LUKS check could never pass.
- `forensics-up.sh` advised writing your LUKS *password* into the keyfile, which
  does not work — the keyfile is random key material. It now falls back to an
  interactive passphrase prompt and explains how to enrol a keyfile properly.
- `forensics-up.sh`/`forensics-down.sh` matched the VM by the literal string
  `SIFT.vmx`, ignoring `$SIFT_VMX`; both now match the configured path and no
  longer call `vmrun` when it is absent or unconfigured.

## [4.2.1] — 2026-07-12

### Added
- **Correlation pass**: read-only advisory layer (`forensics-verify.py`) that cross-references
  each DRAFT finding against independent sources in the timeline and evidence JSON, proposing
  one of four verdicts: CORROBORATED (HIGH confidence), SINGLE-SOURCE (LOW), CONTRADICTED
  (REVIEW), or UNVERIFIED (honest default). Writes `correlation-proposals.json` and
  `correlation-summary.txt` — never modifies findings, timeline, evidence, or the report.
  Advisory only; the examiner decides.
- Seeded acceptance test (`test_forensics_verify.py`) asserting all four verdicts plus
  read-only invariants (findings.json byte-for-byte unchanged after run).
- Agent-facing correlation skill (`skills/correlation/SKILL.md`) loaded during investigations
  after findings are drafted, before reporting.

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
