# LibreNMS mdadm SNMP Extension

This directory contains a LibreNMS SNMP agent for Linux software RAID. The
`mdadm` script is a self-contained net-snmp **`pass_persist`** agent: `snmpd`
launches it, keeps it resident, and queries it on demand. It collects array and
device status directly from sysfs and `mdadm(8)` and serves every object in
`MDADM-MIB` (enterprise OID `1.3.6.1.4.1.60652.101`).

Because it runs under `pass_persist`, there is **no cache file, cron job, or
systemd timer**. Data is refreshed in-process at most once per `ttl` seconds
(default 60).

## Install

Run the installer as root:

```bash
sudo ./mdadm_install.sh
```

For non-interactive installs, set `AUTO_YES=1`:

```bash
sudo AUTO_YES=1 ./mdadm_install.sh
```

The installer downloads the agent, writes a default config, installs the
sudoers rule, and adds the `pass_persist` line to the `snmpd` include snippet.

## Installed Files

- Agent script: `/usr/local/lib/snmpd/mdadm`
- Configuration: `/etc/snmp/extension/mdadm.yaml`
- Sudoers rule: `/etc/sudoers.d/mdadm`
- SNMP snippet: `/etc/snmp/snmpd.conf.d/librenms.conf`

The snippet contains a single line:

```text
pass_persist .1.3.6.1.4.1.60652.101 /usr/local/lib/snmpd/mdadm
```

## Sudoers

`snmpd` typically runs as an unprivileged user (`Debian-snmp` or `snmp`). The
agent reads most data from sysfs, but `mdadm --detail` and `mdadm -E` need
root for device counts, array UUID, and event counters. The installed
`sudoers.d-mdadm` rule grants exactly those two read-only commands without a
password. Without it, the agent still works but reports reduced detail.

## Configuration

See `mdadm.yaml.example` for the full, commented template. The default config
discovers all md arrays:

```yaml
---
log_level: WARNING
ttl: 60
devices: []
```

To limit polling to specific arrays, edit `/etc/snmp/extension/mdadm.yaml`:

```yaml
devices:
  - name: md0
    description: Root filesystem
  - name: md1
    description: Data volume
```

Recognised keys:

- `log_level` - `DEBUG`, `VERBOSE`, `INFO`, `NOTICE`, `WARNING`, `ERROR`.
- `log_file` - log path (defaults to `mdadm.log` beside the script).
- `ttl` - in-process refresh interval in seconds (default 60).
- `devices` - list of arrays to poll; empty auto-discovers all md arrays.

CLI flags (`--config`, `--ttl`, `--log-level`, `--log-file`) override the
config file.

## Verification

Run the agent by hand and speak the `pass_persist` protocol on stdin:

```bash
printf 'PING\ngetnext\n.1.3.6.1.4.1.60652.101\n' \
  | /usr/local/lib/snmpd/mdadm --config /etc/snmp/extension/mdadm.yaml
```

You should see `PONG` followed by the first OID, type, and value.

Once `snmpd` has reloaded the snippet, walk the MIB:

```bash
snmpwalk -v2c -c public localhost .1.3.6.1.4.1.60652.101
```

Load `MDADM-MIB.mib` to get symbolic names:

```bash
snmpwalk -v2c -c public -m +MDADM-MIB localhost mdadmMIB
```

Restart `snmpd` after installation if your system does not automatically reload
the include directory.

## Error reporting

The agent is a resident `pass_persist` process, so it does not communicate
failures through a process exit code (snmpd would simply respawn it). Instead the
most recent collection result is published in-band as two scalars:

- `mdadmError` (`.1.1.3`) - numeric code, `0` on success.
- `mdadmErrorString` (`.1.1.4`) - human-readable description, empty on success.

| Code | Meaning | Behaviour |
|------|---------|-----------|
| 0 | All arrays collected cleanly | Normal data served |
| 1 | `mdadm` binary not in `$PATH` | Cleanup - empty tables, sensors removed |
| 2 | Auto-discovery found no arrays | Cleanup - empty tables, sensors removed |
| 3 | `/sys/block` unreadable | Skip - last good data preserved |
| 5 | Configured device entry missing `name` | Skip - last good data preserved |
| 6 | Some arrays had read errors, or `sudo mdadm` access is missing (data still served from sysfs) | Normal data served, error flagged |
| 7 | Configured devices listed but none exist in sysfs | Cleanup - empty tables, sensors removed |

"Cleanup" codes serve empty tables so LibreNMS prunes stale sensors; "Skip"
codes are transient and keep the last good data so sensors are not lost on a
momentary failure. (Code 4, output-write failure, does not apply - there is no
output file in `pass_persist` mode.)

If the sudoers rule is not installed, `sudo mdadm --detail` / `sudo mdadm -E`
are refused and the agent reports code 6 with an actionable message: arrays are
still discovered from sysfs, but per-array and per-device enrichment (UUIDs,
event counts, exact device-role counts) is skipped. Install `sudoers.d-mdadm`
to clear it. The agent calls sudo with `-n` (non-interactive) so a missing rule
fails fast instead of blocking on a password prompt.
