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

All backups run automatically using systemd timers.

Manual intervention is only required during recovery.

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
