# osupdates

## Installation

1. Copy shell scripts into /usr/local/bin/
2. Make them executable
3. Copy timer and service unit into /etc/systemd/system/
4. Activate timer (`systemctl enable --now librenms-osupdates-generate.timer`)
5. Set `extend osupdate /usr/local/bin/osupdates-unpriv-gather.sh` in `/etc/snmp/snmpd.conf`
