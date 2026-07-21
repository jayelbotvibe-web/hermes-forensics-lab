# Installation

There are three ways to use this lab, and they cost very different amounts of
effort. Pick the one that matches what you actually want.

| | What you get | Time | Needs |
|---|---|---|---|
| **1. Reference only** | 33-entry artifact encyclopedia, 7 skill docs, evidence-verification scripts | ~1 min | git, Python 3.8+ |
| **2. Host-only lab** | Above + volatility3, plaso, MFT tools, MemProcFS, reporting | ~20 min | Linux, Docker |
| **3. Full lab** | Above + 8 filesystem-forensics tools, encrypted evidence vault | ~2 h | Above + a hypervisor and an 80 GB VM |

Most people want **2**. Level 3 adds sleuthkit, foremost, photorec, regripper
and friends, which run on a separate Ubuntu VM.

---

## 1. Reference only

```bash
git clone https://github.com/<you>/hermes-forensics-lab.git
cd hermes-forensics-lab
make test        # verifies the analysis scripts work — needs nothing but Python
```

Now read [`skills/forensic-artifacts/SKILL.md`](skills/forensic-artifacts/SKILL.md).
Nothing is installed and nothing is configured.

The two verification scripts are useful on their own, against any case
directory that follows the lab's layout:

```bash
python3 scripts/forensics-verify.py       tests/fixtures/correlation-sample
python3 scripts/forensics-verify-audit.py <case-dir>
```

---

## 2. Host-only lab

```bash
git clone https://github.com/<you>/hermes-forensics-lab.git
cd hermes-forensics-lab
./install.sh --minimal
make doctor
```

`--minimal` skips the VM and the encrypted vault, and answers every prompt with
its default. It installs the Python packages, builds the three Docker images,
installs MemProcFS, and writes your config file.

Prefer to be asked about each decision? Drop the flag:

```bash
./install.sh            # interactive
./install.sh --dry-run  # show what it would do, change nothing
```

**What you can do at this level:** memory forensics (volatility3, MemProcFS),
timeline generation (plaso), MFT parsing, IOC extraction, correlation
verification, and HTML/PDF reporting.

**What you cannot:** the eight SIFT-native filesystem tools. `make canary`
reports those as `SKIP (host-only mode)` rather than counting them against you.

---

## 3. Full lab

Do level 2 first, then add the two heavy components in either order.

### 3a. Encrypted evidence vault

Real casework should keep evidence encrypted at rest. One command:

```bash
bash scripts/create-evidence-vault.sh --size 60G
```

It creates a sparse LUKS2 container, asks you to choose a passphrase, enrols a
random keyfile so daily bring-up is non-interactive, makes an ext4 filesystem,
mounts it at `$FORENSICS_HOME`, and creates the lab skeleton. If any step
fails it rolls everything back rather than leaving a half-built vault.

Sparse means a 60 GB vault consumes only what you write into it.

To skip encryption entirely, set `FORENSICS_VAULT_ENABLED=false` in your
config. Reasonable for CTFs; not for real evidence.

> **Back up `~/.forensics-keyfile`.** It unlocks the vault. Losing both it and
> the passphrase means losing the evidence — there is no recovery path.

### 3b. SIFT Workstation VM

Build the VM by hand once, then provision it with one command.

**Create the VM** in VMware Workstation, VirtualBox, or KVM/QEMU:

- Ubuntu 22.04 Server ISO
- 12 GB RAM, 4 CPUs, 80 GB disk
- **Bridged** networking, so the host and VM can reach each other
- Username `sansforensics` (any username works — pass `--user` later)
- Enable OpenSSH server during installation

Give it a static IP, or a DHCP reservation on your router. Find its address
with `ip -4 addr` inside the VM.

**Provision it** from the host:

```bash
bash scripts/provision-sift.sh 192.168.1.50
```

That installs your SSH key (asking for the VM password once), apt-installs the
eight tools plus their dependencies, sets up the read-only sshfs evidence
mount, saves `SIFT_HOST`/`SIFT_USER` into your config, and verifies all eight
tools respond.

Re-check an existing VM at any time:

```bash
bash scripts/provision-sift.sh --check
```

**Optional — VM auto start/stop.** Set `SIFT_VMX` in your config to your
`.vmx` path and `forensics-up.sh` will start the VM for you and
`forensics-down.sh` will stop it. Leave it empty to manage the VM yourself;
bring-up then just waits for SSH.

### 3c. Hermes agent (optional)

The lab's scripts, skills, and encyclopedia are all usable by hand or by any
LLM agent. To run the packaged [Hermes](https://github.com/NousResearch/hermes)
profile:

```bash
./install.sh --profile-only
$EDITOR ~/.hermes/profiles/forensics/config.yaml   # set your model and API key
hermes -p forensics
```

The shipped config defaults to `deepseek-v4-pro`. Any tool-capable model works.

---

## Configuration

One file drives everything. Resolution order, first match wins:

1. `$FORENSICS_CONF`
2. `~/.config/hermes-forensics/forensics.conf` ← what `install.sh` writes
3. `<repo>/forensics.conf`

Every setting is also an environment variable, and the environment always
beats the file:

```bash
SIFT_HOST=10.0.0.5 make canary       # one-off override
```

See [`forensics.conf.example`](forensics.conf.example) for every option with
its default. The settings you are most likely to change:

| Setting | Default | Meaning |
|---|---|---|
| `FORENSICS_HOME` | `$HOME/forensics` | Evidence root / vault mountpoint |
| `FORENSICS_VAULT_ENABLED` | `true` | Encrypt evidence at rest |
| `SIFT_HOST` | *(empty)* | VM address; empty means host-only |
| `SIFT_VMX` | *(empty)* | `.vmx` path for VM auto start/stop |
| `MEMPROCFS_HOME` | `$HOME/memprocfs` | MemProcFS install location |

Show what is actually in effect:

```bash
make config
```

The config file is parsed, not executed: only plain `KEY=value` lines are
honoured, and anything containing shell metacharacters is refused with a
warning. A config file is data, and yours may end up shared with a colleague.

---

## Daily use

```bash
make up        # mount vault, start VM, run the canary
make canary    # validate the 12 tools without touching anything else
make down      # unmount vault, stop VM
```

---

## When something is wrong

```bash
make doctor
```

Every check reports what is required, whether you have it, and the exact
command that fixes it. Exit codes: `0` ready, `1` degraded but usable,
`2` blocked.

Common cases:

**`docker: permission denied`**
```bash
sudo usermod -aG docker $USER    # then log out and back in
```

**`pip install` refused — externally managed environment.** `install.sh`
handles this automatically. By hand:
```bash
python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt
```

**WeasyPrint imports but PDF generation fails.** Missing native libraries:
```bash
sudo apt install libpango-1.0-0 libpangoft2-1.0-0 libcairo2 libgdk-pixbuf-2.0-0
```

**Vault will not mount.** Check the container exists and the keyfile is `0600`:
```bash
ls -l ~/forensics.img ~/.forensics-keyfile
sudo cryptsetup status forensics_crypt
```
`forensics-up.sh` falls back to a passphrase prompt when the keyfile fails.

**SIFT VM unreachable.** Confirm it is running and the address is right —
a DHCP lease may have moved it:
```bash
ping <vm-ip>
bash scripts/provision-sift.sh --check
```
Then update `SIFT_HOST`, or re-run `provision-sift.sh <new-ip>` to save it.

**A tool reports DEGRADED.** That is deliberate: the lab never installs tools
mid-case, because changing the toolchain during an investigation undermines
the evidence. Finish or suspend the case, fix the tool, re-run `make canary`.

---

## Uninstalling

```bash
docker rmi forensics-volatility3:2.7.0 forensics-plaso:20240512 forensics-mft-tools:1.2.0.0
rm -rf ~/memprocfs ~/.config/hermes-forensics ~/.hermes/profiles/forensics
```

The evidence vault is left alone on purpose. To remove it — **this destroys
every case it holds**:

```bash
bash scripts/forensics-down.sh      # unmount first
rm ~/forensics.img ~/.forensics-keyfile
```
