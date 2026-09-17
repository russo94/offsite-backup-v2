# Application Backup Strategy

## Overview

Application backups are stored separately from full Proxmox VM/LXC backups.

The purpose is to provide application-level recovery without requiring a complete VM or container restore.

The backup philosophy follows:

- Recoverable before automated
- Simple before clever
- Separate application recovery from infrastructure recovery

---

# Backup Layers

The homelab backup strategy uses multiple recovery layers.

## Layer 1 - Application Backups

Application-native backups are created by each service.

Examples:

- Vaultwarden database and attachments
- Pi-hole configuration exports
- NGINX Proxy Manager database and configuration
- Home Assistant backups
- Mattermost database and application data

Stored locally:

/backup/

---

## Layer 2 - Proxmox Guest Backups

Proxmox creates full VM and LXC backups using vzdump.

Includes:

- LXC containers
- Virtual machines
- Guest configuration

Stored:

/backup/proxmox/vzdump/

Examples:

- vzdump-lxc-100
- vzdump-lxc-101
- vzdump-lxc-102
- vzdump-lxc-105
- vzdump-qemu-103
- vzdump-qemu-104

---

## Layer 3 - Offsite Backup

Offsite Backup V2 protects the complete /backup directory.

The backup destination is an external USB drive.

The system uses:

- Incremental snapshots
- Hard links
- Metadata
- Verification
- Retention policies

---

# Application Backup Locations

## Vaultwarden

Location:

/backup/vaultwarden

Contents:

- Database
- Attachments
- RSA keys
- Configuration

Schedule:

03:00

---

## NGINX Proxy Manager

Location:

/backup/nginxproxymanager

Contents:

- Database
- Configuration
- Proxy settings

Schedule:

03:15

---

## Pi-hole

Location:

/backup/pihole

Contents:

- Teleporter exports
- DNS configuration
- Lists

Schedule:

03:30

---

## Home Assistant

Location:

/backup/homeassistant

Contents:

- Home Assistant OS backup archives

Backup flow:

Home Assistant OS
        |
        |
Samba backup share
        |
        |
Proxmox sync script

Sync script:

/root/application-backups/homeassistant-sync.sh

Schedule:

03:45

Systemd units:

homeassistant-backup-sync.service
homeassistant-backup-sync.timer

---

## Mattermost

Status:

- Implemented on feature branch `feature/mattermost-application-backup`
- Verified in an isolated end-to-end Offsite Backup V2 integration test on 2026-09-18
- Not yet enabled in the production Offsite Backup V2 configuration

Local recovery set:

/backup/mattermost/current

Contents:

- PostgreSQL plain SQL dump
- Mattermost configuration
- Mattermost data
- Server plugins
- Client plugins

Integration flow:

1. Offsite Backup V2 completes normal environment checks.
2. The application backup coordinator runs before snapshot creation.
3. Mattermost backup preflight verifies the LXC, services, bind mount, and required commands.
4. Mattermost is stopped briefly for a consistent application capture.
5. PostgreSQL is dumped and required filesystem data is copied into a temporary candidate recovery set.
6. Mattermost is started again before restore verification continues.
7. The SQL dump is restored into a temporary PostgreSQL database and compared with the live database table count.
8. `config.json` and required filesystem paths are validated.
9. Only a verified candidate is promoted to `/backup/mattermost/current`.
10. The normal Offsite Backup V2 snapshot then captures `/backup`, including the verified Mattermost recovery set.

The Mattermost module does not implement its own snapshot retention. Snapshot creation, incremental hard-link behavior, metadata, retention, health reporting, and notifications remain responsibilities of Offsite Backup V2.

Configuration:

```bash
ENABLE_MATTERMOST_BACKUP=true
MATTERMOST_CTID=111
MATTERMOST_HOST_BACKUP_ROOT="/backup/mattermost"
MATTERMOST_CONTAINER_BACKUP_ROOT="/opt/mattermost/backups"
```

The default example configuration keeps `ENABLE_MATTERMOST_BACKUP=false` until explicitly enabled.

### Verified recovery behavior

Isolated verification performed on 2026-09-18 confirmed:

- Mattermost restarted successfully after application capture.
- Candidate PostgreSQL restore matched the live database at 133 public tables.
- The verified recovery set was included in a real incremental Offsite Backup V2 snapshot.
- PostgreSQL restored successfully from the copy inside the offsite snapshot, again matching 133 public tables.
- Config, data, server plugins, and client plugins restored into an isolated temporary location and matched the offsite snapshot contents.
- A second integrated run used the previous test snapshot as its incremental baseline.
- Retention dry-run identified the older same-day snapshot correctly.
- Real retention deletion removed only the eligible snapshot inside the isolated test snapshot tree.
- A forced Mattermost preflight failure preserved the previously known-good snapshot pointer.
- Production Offsite Backup V2 snapshots were not modified during the isolated integration tests.

These checks prove application-data recovery from the tested offsite snapshot. They do not by themselves prove a complete clean-host Mattermost disaster rebuild.

---

# Recovery Examples

## Application Failure

Restore only the affected application.

Example:

/backup/vaultwarden

---

## Container Failure

Restore the full LXC:

/backup/proxmox/vzdump/

Example:

vzdump-lxc-101

---

## Virtual Machine Failure

Restore the complete VM.

Example:

vzdump-qemu-103

(Home Assistant)

---

## Complete Proxmox Failure

Recovery process:

1. Install Proxmox
2. Restore configuration
3. Connect backup USB storage
4. Restore required guests
5. Restore applications if required

---

# Design Principles

## Multiple Recovery Paths

A single backup method is not sufficient.

The system provides:

- Application recovery
- Guest recovery
- Infrastructure recovery
- Offsite recovery

---

## Automation

All production backup jobs run automatically using systemd timers.

Application-specific preparation can be integrated directly into Offsite Backup V2 when it must occur immediately before the offsite snapshot. Mattermost uses this model on the feature branch so the offsite snapshot captures a freshly verified recovery set.

---

# Current Backup Schedule

03:00  Vaultwarden
03:15  NGINX Proxy Manager
03:30  Pi-hole
03:45  Home Assistant sync
04:00  Proxmox vzdump
04:15  Proxmox configuration backup
05:00  Offsite Backup V2
09:00  Backup health verification
