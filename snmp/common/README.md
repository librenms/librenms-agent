# LibreNMS SNMP Extension Common Units

This directory contains shared systemd units for LibreNMS SNMP extensions that refresh cached output on a schedule.

## Files

- `librenms-snmp-extension@.service`: common oneshot service template.
- `librenms-snmp-extension@.timer`: common timer template that runs an extension every five minutes.

## Defaults

The common service runs extension instances by name:

```ini
ExecStart=/usr/local/lib/snmpd/%i --config /etc/snmp/extension/%i.yaml --output /run/snmp/extension/%i.json
```

For an extension named `example`, this resolves to:

- Script: `/usr/local/lib/snmpd/example`
- Config: `/etc/snmp/extension/example.yaml`
- Output: `/run/snmp/extension/example.json`

Extensions that need different arguments should install a systemd drop-in override for their specific instance.

The units include `Documentation=` metadata for the shared common units and the extension-specific directory. The service also sets `SyslogIdentifier=librenms-snmp-extension-%i` so logs can be filtered per extension instance.

## Enable An Extension

Install the shared units to `/etc/systemd/system/`, then enable the timer for the extension instance:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now librenms-snmp-extension@example.timer
```

Check timer status:

```bash
systemctl status librenms-snmp-extension@example.timer
```

Run a refresh manually:

```bash
sudo systemctl start librenms-snmp-extension@example.service
```
