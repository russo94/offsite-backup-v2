# Configuration Guide

## Overview

Offsite Backup V2 uses a central configuration file:

```bash
backup.conf
```

This file controls backup sources, destinations, retention policies, notifications, and safety checks.

The example configuration is provided as:

```bash
backup.conf.example
```

Copy it before editing:

```bash
cp backup.conf.example backup.conf
```

---

# Backup Paths

## Source Directory

Defines the data that will be backed up.

Example:

```bash
SOURCE="/backup"
```

This directory should contain the application exports and configuration files that need protection.

---

## Backup Destination

Defines where snapshots are stored.

Example:

```bash
DESTINATION="/mnt/offsite-backup"
```

The destination should be a dedicated backup device.

Recommended:

- External USB drive
- Separate filesystem
- Independently mountable storage

---

# USB Safety Checks

## Expected UUID

Offsite Backup V2 verifies that the correct backup device is mounted before writing data.

Example:

```bash
EXPECTED_UUID="xxxx-xxxx"
```

Find the UUID using:

```bash
blkid
```

This prevents accidentally writing backups to the wrong disk.

---

# Retention Policy

Offsite Backup V2 supports daily, weekly, and monthly retention.

Example:

```bash
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
```

Meaning:

- Keep the last 7 daily backups
- Keep the last 4 weekly backups
- Keep the last 6 monthly backups

---

## Retention Mode

Before enabling deletion, test the policy:

```bash
RETENTION_MODE="dry-run"
```

Dry-run mode shows which snapshots would be removed without deleting anything.

Production mode:

```bash
RETENTION_MODE="delete"
```

---

# Storage Protection

## Minimum Free Space

The backup system checks available storage before creating snapshots.

Example:

```bash
MIN_FREE_SPACE_GB=10
```

If available space drops below this value, the backup stops.

---

# Notifications

## Enable Notifications

Discord notifications can be enabled:

```bash
NOTIFY_ENABLED=true
```

Disable:

```bash
NOTIFY_ENABLED=false
```

---

## Notification Method

Currently supported:

```bash
NOTIFY_METHOD="discord"
```

---

## Discord Webhook

Set the Discord webhook URL:

```bash
DISCORD_WEBHOOK_URL="your-webhook-url"
```

Notifications are sent for:

- Successful backups
- Failed backups
- Health reports

---

# Backup Locking

Offsite Backup V2 prevents multiple backups running simultaneously.

The lock file location can be configured:

```bash
LOCK_FILE="/var/run/offsite-backup-v2.lock"
```

---

# Logging

Logs are stored automatically.

Example:

```bash
LOG_DIR="/mnt/offsite-backup/logs"
```

Each backup creates a timestamped log file.

Example:

```text
backup-2026-07-22_05-00-00.log
```

---

# Configuration Validation

After editing `backup.conf`, verify the script:

```bash
bash -n offsite-backup-v2.sh

for file in lib/*.sh; do
    bash -n "$file" || exit 1
done
```

A clean result means the configuration syntax is valid.
