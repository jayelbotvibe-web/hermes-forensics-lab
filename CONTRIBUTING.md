# Contributing to Hermes Forensics Lab

Thanks for your interest in contributing! This project is part of a multi-repo ecosystem including:

- [hermes-pentest-lab](https://github.com/jayelbotvibe-web/hermes-pentest-lab) — Offensive security companion
- [hermes-lab-manager](https://github.com/jayelbotvibe-web/hermes-lab-manager) — Multi-profile lab orchestration

## How to Contribute

### Reporting Issues

Found a bug, inconsistency, or have a feature request? Open an issue on GitHub with:
- What you expected to happen
- What actually happened
- Steps to reproduce (if applicable)

### Pull Requests

1. **Keep it focused** — one logical change per PR
2. **Update project-metadata.yaml** if your change affects tool counts, version numbers, or other centralized values
3. **Verify consistency** — run `grep -rn "<your-value>" README.md index.html docs/` and make sure it matches project-metadata.yaml
4. **Don't edit sample reports by hand** — they're generated. Fix the generation script (`scripts/forensics-report.sh`) instead
5. **Test before submitting** — run `bash scripts/session-canary.sh` to validate toolchain if your change touches tool infrastructure

### Code Style

- Shell scripts: `set -uo pipefail`, no `set -e` in bring-up/shutdown scripts
- Python: stdlib only unless a dependency is listed in `requirements.txt`
- Documentation: single source of truth in `project-metadata.yaml` — no hardcoded numbers in multiple files

### Documentation

The project uses two documentation surfaces:
- **README.md** — Landing page for the repo (what it is, how to start)
- **GitHub Pages (index.html)** — Interactive architecture reference with diagrams
- **docs/** — Deep-dive reference docs (AUTOMATION.md), INSTALL.md

When updating documentation, check all three surfaces for consistency.

### Security

- **Never commit credentials** — sample reports use `<REDACTED_...>` placeholders
- **Scan for secrets** before submitting: `grep -rE '[0-9]{8,10}:[A-Za-z0-9_-]{30,}|AKIA[0-9A-Z]{16}' .`
- **Evidence and case data** must use sanitized/fixture data only

### Questions?

Open an issue or start a discussion. This project is actively maintained and questions are welcome.
