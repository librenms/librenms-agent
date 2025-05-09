# systemd

## Installation

1. Copy systemd.py into /usr/bin/
2. Copy timer and service unit into /etc/systemd/system/
3. Reload systemd configuration with `systemctl daemon-reload`
4. Create file with `touch /var/lib/net-snmp/systemd.txt`
5. Set selinux whatever with `restorecon -Rv /var/lib/net-snmp`
4. Activate timer (`systemctl enable --now librenms-systemd-generate.timer`)
5. Set `extend osupdate /usr/bin/cat /var/lib/net-snmp/systemd.txt` in `/etc/snmp/snmpd.conf`
