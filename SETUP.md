# SIFT Workstation VM Setup

## 1. Create the VM

1. Install VMware Workstation (free for personal use) or KVM/QEMU
2. Download Ubuntu 22.04 Server ISO
3. Create VM: **12GB RAM, 4 CPUs, 80GB disk, Bridged networking**
4. Install with username: `sansforensics`, password: `forensics`
5. Enable OpenSSH server during install

## 2. Install Forensic Tools

After first boot, SSH into the VM and run:

```bash
sudo apt update
sudo apt install -y sleuthkit foremost testdisk dc3dd gddrescue \
  hashdeep tshark ewf-tools afflib-tools regripper python3-pip
pip3 install python-registry
```

Optional — install MemProcFS (Linux x64):
```bash
wget https://github.com/ufrisk/MemProcFS/releases/latest/download/MemProcFS_files_and_binaries_v5.17.8-linux_x64-20260611.tar.gz
tar xzf MemProcFS*.tar.gz
sudo apt install -y libfuse2t64 lz4
```

## 3. Set Up SSH Key Auth

On the **host**, copy your SSH key to the VM:
```bash
ssh-copy-id sansforensics@<VM_IP>
```

Test: `ssh sansforensics@<VM_IP> echo OK`

## 4. Configure SSHFS Evidence Mount

On the **VM**:
```bash
sudo apt install -y sshfs
mkdir -p ~/cases
sshfs <user>@<HOST_IP>:~/forensics/cases ~/cases -o ro
```

Replace `<HOST_IP>` with your host's IP on the bridged network.

## 5. Set Static IP

In VMware, configure the VM's network adapter to **Bridged** mode.
Set a static IP (e.g., `192.168.88.14`) or use DHCP reservation on your router.

The IP is referenced by:
- `scripts/sift-exec.sh` — via `SIFT_HOST` env var (default: `192.168.88.14`)
- `scripts/session-canary.sh` — via `SIFT_HOST` env var

## 6. Docker Images (on Host)

```bash
docker build -t forensics-volatility3:2.7.0 tools/volatility/
docker build -t forensics-plaso:20240512 tools/plaso/
docker build -t forensics-mft-tools:1.2.0.0 tools/mft-tools/
```

## 7. Hermes Profile

Copy the profile config:
```bash
cp -r hermes-forensics.profile/ ~/.hermes/profiles/forensics/
```

Then edit `~/.hermes/profiles/forensics/config.yaml` to set your preferred model.

Start the forensics agent:
```bash
hermes -p forensics
```

## 8. Environment Variables

Set these for portability across different systems:

| Variable | Default | Purpose |
|----------|---------|---------|
| `FORENSICS_HOME` | `$HOME/forensics` | Root of forensics directory |
| `SIFT_HOST` | `192.168.88.14` | SIFT VM IP |
| `SIFT_USER` | `sansforensics` | SIFT VM username |
