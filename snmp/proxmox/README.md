# Proxmox VE Agent

## Quick Install

```bash
curl -s https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/proxmox/install.sh | bash
```

For cron-based refresh instead of systemd:

```bash
curl -s https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/proxmox/install.sh | bash -s -- --cron
```

## Manual Install

Clone the repository and run locally:

```bash
git clone https://github.com/librenms/librenms-agent.git
cd librenms-agent/snmp/proxmox
sudo ./install.sh
```

See [LibreNMS Proxmox documentation](https://docs.librenms.org/Extensions/Applications/Proxmox/) for full installation and usage instructions.
