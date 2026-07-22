# Retention Guide

## Overview

Offsite Backup V2 uses a retention system to automatically manage old snapshots.

The goal is to keep enough historical backups for recovery while preventing unlimited storage growth.

The retention policy supports:

- Daily snapshots
- Weekly snapshots
- Monthly snapshots

---

# Retention Configuration

Retention is configured in `backup.conf`.

Example:

```bash
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
```

This means:

- Keep the last 7 daily snapshots
- Keep the last 4 weekly snapshots
- Keep the last 6 monthly snapshots

---

# How Retention Works

After a successful backup:

1. New snapshot is created
2. Snapshot metadata is written
3. Retention analysis runs
4. Snapshots outside the policy are removed

The newest snapshot is always protected.

---

# Daily Retention

Daily backups provide short-term recovery.

Example:

```text
2026-07-22
2026-07-21
2026-07-20
```

The most recent daily snapshots are kept according to:

```bash
KEEP_DAILY
```

---

# Weekly Retention

Weekly backups provide longer recovery history.

A snapshot is considered weekly based on its calendar week.

Example:

```text
2026-W30
2026-W29
2026-W28
```

The number of weekly snapshots retained is controlled by:

```bash
KEEP_WEEKLY
```

---

# Monthly Retention

Monthly backups provide long-term recovery points.

Example:

```text
2026-07
2026-06
2026-05
```

The number of monthly snapshots retained is controlled by:

```bash
KEEP_MONTHLY
```

---

# Dry Run Mode

Before allowing automatic deletion, test retention using:

```bash
RETENTION_MODE="dry-run"
```

Dry-run mode:

- Shows which snapshots would be deleted
- Does not remove any data

Example output:

```text
KEEP
2026-07-22_05-00-00

DELETE
2026-06-01_05-00-00
```

After confirming the policy behaves correctly, switch to:

```bash
RETENTION_MODE="delete"
```

---

# Storage Efficiency

Offsite Backup V2 uses rsync hard links.

Although every snapshot appears complete, unchanged files are shared between snapshots.

Example:

```text
Snapshot A
file1
file2
file3

Snapshot B
file1 (shared)
file2 (changed)
file3 (shared)
```

This provides:

- Browseable snapshots
- Efficient storage usage
- Simple restoration

---

# Manual Retention Review

Retention can be reviewed by checking available snapshots:

```bash
ls -lah /mnt/offsite-backup/snapshots
```

The current active snapshot:

```bash
readlink -f /mnt/offsite-backup/current
```

---

# Recovery Considerations

Retention should balance:

- Available storage
- Recovery needs
- Backup frequency

A larger retention window provides more historical recovery points but requires more storage capacity.

For important systems, keeping additional historical backups is recommended.
