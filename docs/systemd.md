# Systemd Scheduling

The backup system is executed automatically using a systemd timer.

## Installed Files

System-wide files:
/etc/systemd/system/offsite-backup-v2.service
/etc/systemd/system/offsite-backup-v2.timer


## Service

The service executes:
/root/offsite-backup-v2/offsite-backup-v2.sh


Configuration:

- Type: oneshot
- Working directory: `/root/offsite-backup-v2`
- Output: systemd journal

## Timer

Schedule:
Daily at 03:00

Configuration:


OnCalendar=--* 03:00:00
Persistent=true


`Persistent=true` allows the backup to run after the system returns online if it missed the scheduled time.

## Management Commands

Reload systemd:

`bash
systemctl daemon-reload

Enable timer:

systemctl enable offsite-backup-v2.timer

Start timer:

systemctl start offsite-backup-v2.timer

Check timer:

systemctl status offsite-backup-v2.timer
systemctl list-timers | grep offsite

Run backup manually:

systemctl start offsite-backup-v2.service

View logs:

journalctl -u offsite-backup-v2.service
Verification

Automatic scheduling verified:

Daily execution enabled
Next run: 03:00 CEST
