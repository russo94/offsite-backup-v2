# Phanom Backup

Version: 2.0 (Development)

---

## Overview

Phanom Backup is a modular off-site backup system for Proxmox VE.

It was designed with the following goals:

- Safe before fast
- Simple before clever
- Recoverable before automated
- Fully version controlled

The system creates snapshot-based backups of the Proxmox backup directory onto an external USB drive using incremental hard-linked snapshots.

---

# Current Features

✅ Modular architecture

✅ Git version control

✅ Incremental snapshots (rsync + hard links)

✅ Snapshot metadata

✅ Atomic snapshot creation

✅ UUID verification

✅ Mount verification

✅ Free space verification

✅ Logging

---

# Planned Features

- Snapshot retention
- Restore helper
- Backup verification
- Backup manifests
- Health reports
- Optional notifications

---

# Directory Structure

```
offsite-backup-v2/

├── backup.conf
├── offsite-backup-v2.sh
├── .gitignore
├── docs/
├── lib/
│   ├── logging.sh
│   ├── metadata.sh
│   ├── snapshot.sh
│   └── verify.sh
└── logs/
```

---

# Backup Workflow

1. Load configuration
2. Load modules
3. Acquire lock
4. Verify environment
5. Create snapshot
6. Write metadata
7. Update current symlink
8. Generate summary
9. Exit

---

# Design Philosophy

The project follows several engineering principles.

## Single Responsibility

Each module performs one task.

Example:

- verify.sh → environment validation
- snapshot.sh → snapshot creation
- metadata.sh → snapshot metadata
- logging.sh → terminal and log output

---

## Safety First

The backup should fail instead of risking writing to the wrong device.

Examples:

- UUID verification
- Mount verification
- Lock file
- Atomic snapshots

---

## Version Control

Every feature is committed separately.

This allows:

- rollback
- comparison
- auditing
- experimentation

without risking a working version.

---

# Status

Current Version

2.0 Development

Current State

Stable

Git Branch

main
