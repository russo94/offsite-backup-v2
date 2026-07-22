# Restore Guide

## Overview

Offsite Backup V2 is designed around the principle that backups must be recoverable.

Snapshots are stored as normal directories and can be restored using standard Linux tools.

No proprietary restore software is required.

---

# Restore Verification

Before retention cleanup, Offsite Backup V2 verifies that the latest snapshot can be accessed.

The purpose of restore verification is to confirm:

- Snapshot exists
- Files are readable
- Backup structure is valid

A backup that cannot be restored is not considered reliable.

---

# Viewing Available Snapshots

List available snapshots:

```bash
ls -lah /mnt/offsite-backup/snapshots
```

Example:

```text
snapshots/
├── 2026-07-20_23-37-14
├── 2026-07-21_12-28-57
└── 2026-07-22_05-00-00
```

The latest successful snapshot is available through:

```bash
readlink -f /mnt/offsite-backup/current
```

---

# Restoring Data

Snapshots can be restored using `rsync`.

Example:

```bash
rsync -aHAX --numeric-ids \
    /mnt/offsite-backup/current/ \
    /restore/location/
```

Options:

- `-a` preserves permissions and timestamps
- `-H` preserves hard links
- `-A` preserves ACLs
- `-X` preserves extended attributes
- `--numeric-ids` preserves user and group IDs

---

# Restoring Individual Services

Offsite Backup V2 stores application backups separately.

Example:

```text
current/
├── pihole/
├── nginxproxymanager/
├── vaultwarden/
└── proxmox/
```

Individual service backups can be restored without restoring the entire snapshot.

---

# Disaster Recovery Procedure

## Scenario

The Proxmox host has failed and needs replacement.

---

## Steps

### 1. Install Proxmox VE

Install Proxmox on replacement hardware.

Update the system:

```bash
apt update
apt upgrade
```

---

### 2. Connect Backup Storage

Connect the backup drive.

Verify the filesystem:

```bash
lsblk
```

Mount the backup destination.

---

### 3. Verify Backup Availability

Check snapshots:

```bash
ls /mnt/offsite-backup/snapshots
```

Check the latest backup:

```bash
readlink -f /mnt/offsite-backup/current
```

---

### 4. Restore Required Data

Restore required services:

```bash
rsync -aHAX --numeric-ids \
    /mnt/offsite-backup/current/ \
    /restore/location/
```

---

### 5. Validate Recovery

After restoring:

- Start services
- Verify network access
- Check application functionality
- Confirm data integrity

---

# Restore Testing

Regular restore tests are recommended.

A backup should periodically be restored to a temporary location:

```bash
mkdir -p /tmp/restore-test

rsync -aHAX --numeric-ids \
    /mnt/offsite-backup/current/ \
    /tmp/restore-test/
```

Verify:

```bash
find /tmp/restore-test -maxdepth 2 -type f
```

---

# Recovery Philosophy

Offsite Backup V2 intentionally avoids hiding data inside proprietary archives.

Each snapshot remains:

- Browseable
- Portable
- Verifiable
- Restorable

The objective is simple:

A recovery should still be possible even if the original system or backup software is unavailable.
