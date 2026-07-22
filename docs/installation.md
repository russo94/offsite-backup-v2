# Installation Guide

## Overview

Offsite Backup V2 is a modular Bash-based backup solution designed for Proxmox VE environments.

This guide covers the initial installation and setup process.

---

## Requirements

Before installing Offsite Backup V2, ensure the system has:

- Proxmox VE host
- Linux environment with Bash support
- `rsync`
- `util-linux` (for UUID checks)
- `curl` (for Discord notifications)
- `git`

Install required packages:

```bash
apt update

apt install -y rsync curl git
```

---

## Clone Repository

Clone the repository:

```bash
git clone https://github.com/russo94/offsite-backup-v2.git

cd offsite-backup-v2
```

---

## Configuration

Create the configuration file:

```bash
cp backup.conf.example backup.conf
```

Edit the configuration:

```bash
nano backup.conf
```

At minimum configure:

- Backup source location
- Backup destination
- Expected USB UUID

---

## Validate Installation

Before running the backup, check Bash syntax:

```bash
bash -n offsite-backup-v2.sh

for file in lib/*.sh; do
    bash -n "$file" || exit 1
done
```

---

## First Backup Run

Run the backup manually:

```bash
./offsite-backup-v2.sh
```

A successful run will:

1. Validate the environment
2. Create a snapshot
3. Write metadata
4. Apply retention rules
5. Generate logs
6. Send notifications if enabled

---

## Enable Automatic Backups

Enable the systemd timer:

```bash
systemctl enable offsite-backup-v2.timer

systemctl start offsite-backup-v2.timer
```

Verify:

```bash
systemctl list-timers | grep offsite
```

---

## Logs

Backup logs are stored in the configured log directory.

Systemd logs can be viewed with:

```bash
journalctl -u offsite-backup-v2.service
```

---

## Next Steps

After installation:

- Review `configuration.md`
- Understand the architecture in `architecture.md`
- Test restore procedures using `restore.md`
