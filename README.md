# Offsite Backup V2

A modular snapshot-based backup system for a Proxmox host.

This project creates incremental backup snapshots to a dedicated USB drive using rsync hard links. It includes environment validation, structured logging, metadata generation, and configurable retention.

## Project Goal

The purpose of this backup system is to provide an independent offsite backup copy of important Proxmox data.

The design goals are:

- Simple recovery
- Safe operation
- Minimal storage duplication
- Easy troubleshooting
- Clear documentation
- Protection against accidental deletion

## Current Status

The backup system is operational and has been tested end-to-end.

Implemented features:

- Backup destination verification
- USB UUID verification
- Source directory verification
- Free-space verification
- Snapshot creation
- Incremental snapshots
- Snapshot metadata
- Structured logging
- Retention management
- Safe automatic deletion

## Project Structure

The project is organized into separate modules to keep the backup system easy to understand and maintain.

offsite-backup-v2/
├── backup.conf
├── offsite-backup-v2.sh
├── README.md
├── docs/
└── lib/
├── logging.sh
├── metadata.sh
├── retention.sh
├── snapshot.sh
├── util.sh
└── verify.sh


## Main Components

### offsite-backup-v2.sh

The main backup orchestrator.

Responsibilities:

- Load configuration
- Load modules
- Lock execution
- Run environment checks
- Create snapshots
- Write metadata
- Execute retention
- Report results

### backup.conf

Central configuration file.

Contains:

- Backup source
- Backup destination
- USB UUID verification
- Snapshot location
- Log location
- Retention policy
- Backup version

### lib/

Contains the individual backup modules.

Each module has a specific responsibility:

- `verify.sh`  
  Validates the backup environment.

- `snapshot.sh`  
  Creates backup snapshots.

- `metadata.sh`  
  Records snapshot information.

- `retention.sh`  
  Controls snapshot lifecycle and cleanup.

- `logging.sh`  
  Provides structured logging.

- `util.sh`  
  Contains shared helper functions.

## Configuration

The backup system is controlled through:

Edit configuration:

backup.conf


Edit configuration:

bash
nano backup.conf

Important configuration values:

Backup source

Example:

SOURCE="/backup"

This is the directory that will be copied.

Backup destination

Example:

DESTINATION="/mnt/offsite-backup"

This is the mounted USB backup location.

USB protection

The system verifies the USB drive UUID before writing.

Example:

EXPECTED_UUID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

This prevents accidentally writing to the wrong disk.

Retention policy

Example:

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6

Meaning:

Keep the last 7 daily snapshots
Keep the last 4 weekly snapshots
Keep the last 6 monthly snapshots
Retention mode

Testing mode:

RETENTION_MODE="dry-run"

Shows what would be deleted without removing anything.

Production mode:

RETENTION_MODE="delete"

Automatically removes snapshots outside the retention policy.

Backup Workflow

A normal backup run follows this sequence:

Start
 |
 |-- Load configuration
 |
 |-- Load modules
 |
 |-- Acquire backup lock
 |
 |-- Verify environment
 |
 |-- Create snapshot
 |
 |-- Write metadata
 |
 |-- Apply retention policy
 |
 |-- Complete backup

Run a backup manually:

cd /root/offsite-backup-v2
./offsite-backup-v2.sh

A successful run ends with:

Backup Completed



## Snapshot System

The backup system uses rsync-based snapshots.

Snapshots are stored in:

`text
/mnt/offsite-backup/snapshots


Example:

snapshots/
├── 2026-07-20_23-37-14/
├── 2026-07-21_00-19-44/
└── current -> 2026-07-21_00-19-44

Each snapshot appears as a complete backup directory.

The current symbolic link always points to the newest successful snapshot.

Snapshot Types
Full snapshot

A full snapshot is created when no previous snapshot exists.

This copies all required data into a new snapshot directory.

Incremental snapshot

After the first snapshot, new backups use:

rsync --link-dest

Files that have not changed are hard-linked from the previous snapshot.

Benefits:

Saves disk space
Keeps every snapshot independently browsable
Makes restore simple
Retention System

The retention engine automatically manages old snapshots.

Current policy:

Daily   : 7
Weekly  : 4
Monthly : 6

The retention process:

Find snapshots
      |
      v
Select snapshots to keep
      |
      v
Build deletion list
      |
      v
Delete expired snapshots

A snapshot can satisfy multiple rules.

Example:

2026-07-21_00-19-44

Latest
Daily (2026-07-21)
Weekly (2026-W30)
Monthly (2026-07)

Snapshots not matching any retention rule are removed when:

RETENTION_MODE="delete"

is enabled.

Retention Safety

Before deleting snapshots, the system checks:

Snapshot name format
Valid snapshot path
Real resolved path
Snapshot location remains inside the backup directory

This prevents accidental deletion outside the backup area.


## Restore Procedure

A backup is only useful if it can be restored.

The recommended restore process is to first restore into a temporary location and verify the files.

Example:

Create a test restore directory:

``bash
mkdir -p /root/restore-test

Restore the latest snapshot:

rsync -aHAX \
    /mnt/offsite-backup/snapshots/current/ \
    /root/restore-test/

Verify the restored files:

ls -la /root/restore-test

After verification, the required data can be copied back to its original location.

Logs and Troubleshooting

Logs are stored in:

/mnt/offsite-backup/logs

List recent logs:

ls -1t /mnt/offsite-backup/logs | head

View a log:

less /mnt/offsite-backup/logs/<log-file>
Common Issues
Backup destination is not mounted

Error:

Backup destination is not mounted.

Check:

mount | grep offsite-backup

Verify the USB drive is mounted correctly.

USB UUID mismatch

Error:

USB UUID mismatch!

Check the connected disk UUID:

blkid

Update:

EXPECTED_UUID=

in:

backup.conf
Backup stops during execution

Check the exit code:

echo $?

Check the latest log file for details.

Testing retention changes

Always test retention changes first using:

RETENTION_MODE="dry-run"

This shows which snapshots would be deleted without removing data.

Validation Commands

Check script syntax:

bash -n offsite-backup-v2.sh

Check library syntax:

for file in lib/*.sh; do
    bash -n "$file" || exit 1
done

A successful syntax check produces no output.

Future Improvements

Possible future additions:

Automated restore verification
Backup notifications
USB drive health checks
SMART monitoring
Scheduled backups
Remote/cloud copy
Backup integrity checks
Encryption support


## Restore Verification

A restore test was successfully performed on:

`text
2026-07-21

Test procedure:

Selected the latest snapshot using the current symlink.
Restored the snapshot to a temporary directory.
Verified restored files and permissions.

Restore command tested:

rsync -aHAX \
/mnt/offsite-backup/snapshots/current/ \
/root/restore-test/

Verification results:

Snapshot size : 2.5G
Restore size  : 2.5G

Snapshot files: 20
Restored files: 20

Result:

SUCCESS - Backup restore verified
