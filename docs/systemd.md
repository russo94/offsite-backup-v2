# Systemd Scheduling

The backup system is executed automatically using a systemd timer.

## Installed Files

System-wide files:

```text
/etc/systemd/system/offsite-backup-v2.service
/etc/systemd/system/offsite-backup-v2.timer
```

---

## Service

The service executes:

```text
/root/offsite-backup-v2/offsite-backup-v2.sh
```

Configuration:

- Type: oneshot
- Working directory: `/root/offsite-backup-v2`
- Output: systemd journal

The service runs the backup process and records execution results through systemd logging.

---

## Timer

The backup schedule is controlled by:

```text
offsite-backup-v2.timer
```

Current schedule:

```ini
OnCalendar=*-*-* 05:00:00
Persistent=true
```

`Persistent=true` allows the backup to run after the system returns online if it missed the scheduled time.

---

## Management Commands

Reload systemd:

```bash
systemctl daemon-reload
```

Enable timer:

```bash
systemctl enable offsite-backup-v2.timer
```

Start timer:

```bash
systemctl start offsite-backup-v2.timer
```

Check timer:

```bash
systemctl status offsite-backup-v2.timer

systemctl list-timers | grep offsite
```

Run backup manually:

```bash
systemctl start offsite-backup-v2.service
```

View logs:

```bash
journalctl -u offsite-backup-v2.service
```

---

## Verification

Automatic scheduling verified:

- Daily execution enabled
- Schedule: 05:00 CEST
- Successful manual execution tested
- Discord notifications verified
