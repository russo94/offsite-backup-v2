# Architecture Guide

## Overview

Offsite Backup V2 is designed as a modular Bash application.

The project is intentionally divided into small components, with each module responsible for a specific task.

The main goals are:

- Simplicity
- Transparency
- Recoverability
- Easy maintenance

---

# High-Level Workflow

A backup run follows this sequence:

```text
Start Backup
      |
      v
Load Configuration
      |
      v
Environment Checks
      |
      +--> Verify Source
      |
      +--> Verify Destination
      |
      +--> Verify USB UUID
      |
      +--> Check Free Space
      |
      v
Create Snapshot
      |
      v
Write Metadata
      |
      v
Apply Retention
      |
      v
Generate Reports
      |
      v
Send Notifications
      |
      v
Backup Complete
```

---

# Project Components

## Main Orchestrator

File:

```text
offsite-backup-v2.sh
```

Responsibilities:

- Loads configuration
- Loads modules
- Controls backup execution flow
- Handles failures
- Sends completion notifications

The orchestrator intentionally contains minimal backup logic. Actual functionality is separated into modules.

---

# Library Modules

## snapshot.sh

Responsible for creating backups.

Functions include:

- Full snapshot creation
- Incremental snapshots
- Hard-link based deduplication
- Updating the `current` symbolic link

Snapshots use:

```bash
rsync --link-dest
```

This allows every snapshot to appear as a complete backup while sharing unchanged files between snapshots.

---

## metadata.sh

Creates metadata for each snapshot.

Every snapshot contains:

```text
.snapshot-info
```

Example information:

- Backup version
- Hostname
- Creation timestamp
- Snapshot type
- Source location
- Destination
- Kernel version
- Proxmox version

This provides useful information during recovery.

---

## retention.sh

Manages snapshot lifecycle.

The retention system supports:

- Daily backups
- Weekly backups
- Monthly backups

Example:

```text
7 daily
4 weekly
6 monthly
```

Retention can be tested using dry-run mode before deleting snapshots.

---

## verify.sh

Performs safety checks before backup execution.

Checks include:

- Destination mounted
- Correct USB device connected
- Source available
- Minimum free space available

The goal is preventing common backup mistakes.

---

## restore_verify.sh

Validates that backups can be accessed and restored.

A backup should not only exist; it should be usable.

Restore verification helps detect:

- Missing files
- Corrupted snapshots
- Invalid backup paths

---

## health.sh

Provides system health information.

Checks include:

- Latest backup status
- Storage availability
- Snapshot count
- Backup freshness
- Restore readiness

---

## notify.sh

Handles external notifications.

Currently supports:

- Discord webhooks

Notifications are sent for:

- Successful backups
- Failed backups
- Health reports

---

# Snapshot Design

Snapshots are stored as normal directories.

Example:

```text
snapshots/
├── 2026-07-22_05-00-00/
├── 2026-07-23_05-00-00/
└── current -> 2026-07-23_05-00-00
```

Each snapshot can be browsed independently.

No proprietary archive format is used.

---

# Failure Handling

The backup process uses:

```bash
set -Eeuo pipefail
```

This provides safer Bash execution.

When a failure occurs:

1. Current stage is recorded
2. Error details are collected
3. Discord notification is sent
4. Backup exits safely

---

# Design Philosophy

Offsite Backup V2 follows a few principles:

## Keep data accessible

Backups should remain understandable without special software.

## Fail safely

A failed backup should be obvious and visible.

## Prefer reliability over complexity

Simple tools such as:

- Bash
- rsync
- Linux filesystem features

are easier to trust and maintain.

## Recovery is the goal

The purpose of backups is not creating copies.

The purpose is restoring when something goes wrong.
