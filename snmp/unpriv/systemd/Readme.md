# systemd

## Installation

1. Copy systemd.py into /usr/bin/
2. Copy timer and service unit into /etc/systemd/system/
3. Activate timer (`systemctl enable --now librenms-osupdates-generate.timer`)
4. Set `extend osupdate /usr/bin/cat /var/net-snmp/systemd.txt` in `/etc/snmp/snmpd.conf`
