PREFIX=${CURDIR}/debian/librenms-agent

install: 
	mkdir -p $(PREFIX)/usr/lib/check_mk_agent/plugins
	mkdir -p $(PREFIX)/usr/lib/check_mk_agent/repo
	mkdir -p $(PREFIX)/usr/lib/check_mk_agent/local
	mkdir -p $(PREFIX)/usr/share/librenms-agent/snmp
	cp -rL agent-local/* $(PREFIX)/usr/lib/check_mk_agent/repo/
	cp -rL snmp/* $(PREFIX)/usr/share/librenms-agent/snmp
	rm $(PREFIX)/usr/lib/check_mk_agent/repo/README
	mkdir -p $(PREFIX)/usr/bin
	install -m 0750 check_mk_agent $(PREFIX)/usr/bin/check_mk_agent
	install -m 0750 mk_enplug $(PREFIX)/usr/bin/mk_enplug
	install -m 0750 snmp/distro $(PREFIX)/usr/bin/distro
	mkdir -p $(PREFIX)/etc/xinetd.d
	install -m 0644 check_mk_xinetd $(PREFIX)/etc/xinetd.d/check_mk

clean:
	rm -rf $(CURDIR)/build
