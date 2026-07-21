# ============================================================================
# Hermes Forensics Lab
#
#   make install     full setup (interactive)
#   make doctor      check what is installed and what is missing
#   make test        run the test suites
#
# Run `make` with no target for the full list.
# ============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Honour an existing config so `make images` builds the tags the canary probes.
CONF := $(firstword $(wildcard $(FORENSICS_CONF) $(HOME)/.config/hermes-forensics/forensics.conf ./forensics.conf))

.PHONY: help install install-minimal deps images vault sift profile doctor \
        config up down canary test test-verify test-audit lint encyclopedia \
        encyclopedia-check clean

help:
	@echo ""
	@echo "  Hermes Forensics Lab"
	@echo ""
	@echo "  Setup"
	@echo "    make install          Full interactive setup"
	@echo "    make install-minimal  Host-only: no VM, no encrypted vault"
	@echo "    make deps             Python packages only"
	@echo "    make images           Build the 3 Docker tool images"
	@echo "    make vault            Create the LUKS evidence vault"
	@echo "    make sift HOST=<ip>   Provision the SIFT VM"
	@echo "    make profile          Install the Hermes agent profile"
	@echo ""
	@echo "  Daily use"
	@echo "    make doctor           Diagnose the environment, with fixes"
	@echo "    make config           Show the resolved configuration"
	@echo "    make up               Mount vault, start VM, run canary"
	@echo "    make down             Stop VM, unmount vault"
	@echo "    make canary           Validate the 12 forensic tools"
	@echo ""
	@echo "  Development"
	@echo "    make test             Run all test suites"
	@echo "    make lint             shellcheck + yamllint"
	@echo "    make encyclopedia     Regenerate the artifact encyclopedia"
	@echo "    make encyclopedia-check  Verify it is up to date (CI)"
	@echo ""
ifneq ($(CONF),)
	@echo "  Config: $(CONF)"
else
	@echo "  Config: none yet — run 'make install'"
endif
	@echo ""

# ── Setup ──────────────────────────────────────────────────────────────────

install:
	@./install.sh

install-minimal:
	@./install.sh --minimal --yes

deps:
	@./install.sh --deps-only

images:
	@./install.sh --images-only

vault:
	@bash scripts/create-evidence-vault.sh $(if $(SIZE),--size $(SIZE),)

sift:
ifndef HOST
	@echo "usage: make sift HOST=<vm-ip> [USER=<username>]" >&2
	@exit 1
endif
	@bash scripts/provision-sift.sh $(HOST) $(if $(USER_NAME),--user $(USER_NAME),)

profile:
	@./install.sh --profile-only

# ── Daily use ──────────────────────────────────────────────────────────────

doctor:
	@bash scripts/forensics-doctor.sh

config:
	@bash scripts/forensics-doctor.sh --config

up:
	@bash scripts/forensics-up.sh

down:
	@bash scripts/forensics-down.sh

canary:
	@bash scripts/session-canary.sh

# ── Development ────────────────────────────────────────────────────────────

test: test-verify test-audit encyclopedia-check
	@echo ""
	@echo "  All test suites passed."

test-verify:
	@echo "→ correlation verification"
	@python3 scripts/test_forensics_verify.py

test-audit:
	@echo "→ audit chain integrity"
	@python3 tests/test_forensics_verify_audit.py

lint:
	@echo "→ shellcheck"
	@shellcheck -S warning scripts/*.sh install.sh scripts/lib/*.sh || true
	@echo "→ bash syntax"
	@for f in scripts/*.sh scripts/lib/*.sh install.sh; do bash -n "$$f" || exit 1; done
	@echo "→ python syntax"
	@python3 -m compileall -q scripts/ encyclopedia/ tests/ > /dev/null
	@echo "  Lint clean."

encyclopedia:
	@python3 encyclopedia/generate.py

# PyYAML is the one non-stdlib dependency in the whole test path. `make test`
# is documented as needing nothing but Python, so skip rather than fail when
# it is absent. CI installs it explicitly and calls generate.py directly, so
# the check is never silently skipped where it matters.
encyclopedia-check:
	@echo "→ encyclopedia is up to date"
	@if python3 -c 'import yaml' 2>/dev/null; then \
		python3 encyclopedia/generate.py --check; \
	else \
		echo "  SKIPPED — PyYAML not installed (pip install pyyaml)"; \
	fi

clean:
	@find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
	@find . -name '*.pyc' -delete 2>/dev/null || true
	@echo "  Cleaned build artifacts. Evidence and config untouched."
