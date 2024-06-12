#!/usr/bin/perl
#=======================================================================
# * conntrack.pl
# * v0.4 (2014.01.04)
# * by red_neon (red_neon [at] dcpp [dot] ru)
# * Uploaded to LibreNMS repository with approval from original author. 
# * Original source: https://forums.cacti.net/viewtopic.php?f=12&t=36629
# * Netfilter Conntrack Status [ tcp / udp / icmp / igmp / other ]
#
# * Shows all current connections on the linux gateway\server
# * it uses the netfilter conntrack module:
# * http://www.frozentux.net/iptables-tutorial/iptables-tutorial.html#THECONNTRACKENTRIES
#
# * Linux kernel version must be >= 2.6.18
#=======================================================================
# INSTALLATION
#
#
# [REMOTE-SERVER SIDE]
#
#	[1] conntrack script
#		Copy conntrack.pl to: /etc/snmpd/ 
#		set rights for execute:
#		$ chmod +x /etc/snmp/conntrack.pl
#
#	[2] iptables (Linux kernel version must be >= 2.6.18)
#		$ modprobe nf_conntrack
#		$ modprobe nf_conntrack_ipv4
#	if you use ipv6:
#		$ modprobe nf_conntrack_ipv6
#
#	Load modules on boot:
#		$ echo "nf_conntrack" >> /etc/modules
#		$ echo "nf_conntrack_ipv4" >> /etc/modules
#	if you use ipv6:
#		$ echo "nf_conntrack_ipv6" >> /etc/modules
#
#	[3] note
#	On highload gateways reading of /proc/net/nf_conntrack
#	takes a lot of time and possibly can cause freeze.
#	To solve this problem - install conntrack-tools
#	(http://conntrack-tools.netfilter.org/)
#	To see how much connections now (safely):
#		$ cat /proc/sys/net/netfilter/nf_conntrack_count
#
#	[3a] stats via conntrack-tools
#	On Debian-based system:
#		$ apt-get install conntrack
#	RPM:
#		$ yum install conntrack-tools
#
#	Check, that "$_mode = 1" in this script below.
#	Ok. Go to pat.[4]
#
#	[3b] stats via /proc/net/nf_conntrack (NOT RECOMMENDED)
#	Use this method on server with < 10k connections at the same time.
#	Set "$_mode = 0" in this script below.
#
#	[4] first run
#	checking:
#		$ /usr/bin/perl /etc/snmp/conntrack.pl
#	if is all ok - you will see stats.
#		$ cat /tmp/conntrack.stat
#
#	[5] snmpd
#	Put into snmpd.conf string with extend:
#	$ nano /etc/snmp/snmpd.conf
#		extend conntrack "/bin/cat /tmp/conntrack.stat"
#
#	restart snmpd:
#		$ /etc/init.d/snmpd restart
#
#	[6] cron
#	$ nano /etc/crontab
#		*/5 * * * * root /bin/sleep 290; /usr/bin/perl /etc/snmp/conntrack.pl cron >/dev/null 2>&1
#
#	Script will get connections status every 5 mins, then it will get data and save them into temporary file in /tmp/ directory.
#	You can change directory and name of temporary file in script-settings below ($_tempfile),
#	do not forget to change string with exec the snmpd.conf
#
#
#=======================================================================
use strict;
#=======================================================================
# SETTINGS START

# Filter localhost connections (ignore src|st=127.0.0.1|::1) (1 = yes, 0 = no)
# default: 0;
my $_localhost = 0;

# Path to temporary file where will stored stats:
my $_tempfile = '/tmp/conntrack.stat';

# What to use for get the connection status?: 1 = conntrack-tools; 0 = nf_conntrack-file.
# Warning, on highload gateways using of nf_conntrack-file method can freeze your server.
# default: 1
my $_mode = 1;

# Conntrack-tools, path to conntrack
my $_conntrack = "/usr/sbin/conntrack";

# SETTINGS END
#=======================================================================
# protocols: tcp / udp / icmp / igmp / other
# tcp flags: SYN_SENT, SYN_RECV, ESTABLISHED, FIN_WAIT, CLOSE_WAIT, LAST_ACK, TIME_WAIT, CLOSE
# status: ASSURED (уверенное состояние), UNREPLIED (без ответа),
# третье состояние без флагов (после ответа на UNREPLIED - считается естаблишед (но без флагов)
# и через несколько ответных пакетов становится уже ASSURED)  
#
# /proc/net/ip_conntrack shows only ipv4 (if nf_conntrack_ipv4 loaded)
# /proc/net/nf_conntrack shows all proto (if nf_conntrack_ipv4 and nf_conntrack_ipv6 loaded)
#=======================================================================
# _u	UNREPLIED
# _ha	HALF-ASSURED (after UNREPLIED but not ASSURED)
# _a	ASSURED
# _tot	total (u+ha+a)
#
# TCP flags:
# _tcp_n 	NONE:			initial state
# _tcp_ss	SYN_SENT:		SYN-only packet seen
# _tcp_ss2	SYN_SENT2:		SYN-only packet seen from reply dir, simultaneous open
# _tcp_sr	SYN_RECV:		SYN-ACK packet seen
# _tcp_e	ESTABLISHED:	ACK packet seen
# _tcp_fw	FIN_WAIT:		FIN packet seen
# _tcp_cw 	CLOSE_WAIT:		ACK seen (after FIN)
# _tcp_la 	LAST_ACK:		FIN seen (after FIN)
# _tcp_tw	TIME_WAIT:		last ACK seen
# _tcp_c 	CLOSE:			closed connection (RST)
#
# _tcp_unk 	connections that not entered in previous
#
# Note:
# Unused LISTEN state is replaced by a new state (SYN_SENT2), which was added in Linux kernel >= 2.6.31
#=======================================================================
# [ TCP ]
my ($_tcp_ss, $_tcp_ss2, $_tcp_sr, $_tcp_e, $_tcp_fw, $_tcp_cw, $_tcp_la,
	$_tcp_tw, $_tcp_c, $_tcp_n, $_tcp_unk) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
my ($_tcp_u, $_tcp_ha, $_tcp_a, $_tcp_tot) = (0, 0, 0, 0);
# [ UDP ]
my ($_udp_u, $_udp_ha, $_udp_a, $_udp_tot) = (0, 0, 0, 0);
# [ ICMP ]
my ($_icmp_u, $_icmp_ha, $_icmp_tot) = (0, 0, 0);
# [ IGMP ]
my ($_igmp_u, $_igmp_ha, $_igmp_tot) = (0, 0, 0);
# [ Other ]
my ($_other_u, $_other_ha, $_other_a, $_other_tot) = (0, 0, 0, 0);
# [ Total ]
my ($_tot_u, $_tot_ha, $_tot_a, $_tot) = (0, 0, 0, 0);
# [ localhost ]
my $_tot_lh = 0;
#=======================================================================
my ($_output, $_runmode, $_info);
my $_options = "";
#=======================================================================
# Realtime-mode
#=======================================================================
if (exists($ARGV[0])) {
	$_options = " 2>/dev/null ";
	if ($ARGV[0] =~ /^cron$/) {
		$_runmode = 1;
	} elsif ($ARGV[0] =~ /^realtime$/) {
		$_runmode = 2;
	}
}
#=======================================================================
if ($_mode) {
	# conntrack-tools can't shows ipv4+ipv6 both..
	if (open($_output, "$_conntrack -L -f ipv4 -o extended $_options|")) {
		$_info = "Method: Conntrack-tools\n";
		&get_stats($_output);
		if (open($_output, "$_conntrack -L -f ipv6 -o extended $_options|")) { &get_stats($_output) }
		else { die("Can't read data from [ conntrack ] tools, error: $!"); }
	} else { die("Can't read data from [ conntrack ] tools, error: $!"); }
} else {
	if ($_runmode == 2) {
		die("Show realtime statistics is not permitted in this mode, use conntrack-tools mode for this option.\n");
	} else {
		if (open($_output, '<', '/proc/net/nf_conntrack')) { $_info = "Method: nf_conntrack file\n"; }
		else { die("Can't open [ /proc/net/nf_conntrack ], error: $!"); }
	}
}

sub get_stats
{
	my $handler = $_[0];
	while (<$handler>)
	{
		#print ;  #print all connections
		if (/\s(src|dst)=(127\.0\.0\.1|::1|0000:0000:0000:0000:0000:0000:0000:0001)\s/) { $_tot_lh++; if ($_localhost) { next; } }

		if (/\stcp\s/) {
			if (/ESTABLISHED/) { $_tcp_e++; }
			elsif (/TIME_WAIT/) { $_tcp_tw++; }
			elsif (/FIN_WAIT/) { $_tcp_fw++; }
			elsif (/SYN_SENT\s/) { $_tcp_ss++; }
			elsif (/CLOSE\s/) { $_tcp_c++; }
			elsif (/CLOSE_WAIT/) { $_tcp_cw++; }
			elsif (/SYN_RECV/) { $_tcp_sr++; }
			elsif (/LAST_ACK/) { $_tcp_la++; }
			elsif (/(SYN_SENT2|LISTEN)/) { $_tcp_ss2++; }
			elsif (/NONE/) { $_tcp_n++; }
			else { $_tcp_unk++ }

			if (/ASSURED/) { $_tcp_a++; }
			elsif (/UNREPLIED/) { $_tcp_u++; }
			else { $_tcp_ha++; }
			$_tcp_tot++;
		} elsif (/\sudp\s/) {
			if (/ASSURED/) { $_udp_a++; }
			elsif (/UNREPLIED/) { $_udp_u++; }
			else { $_udp_ha++ }
			$_udp_tot++;
		} elsif (/\s(icmp|icmpv6)\s/) {
			# ASSURED is not possible here.. but.. =)
			if (/ASSURED/) { $_other_a++;$_other_tot++; } 
			elsif (/UNREPLIED/) { $_icmp_u++;$_icmp_tot++; }
			else { $_icmp_ha++;$_icmp_tot++; }
		} else {
			# IGMP
			if (/^ipv(4|6)\s+\d+\s+\S+\s+2\s+.+$/) {
				# ASSURED is not possible here.. but.. =)
				if (/ASSURED/) { $_other_a++;$_other_tot++; } 
				elsif (/UNREPLIED/) { $_igmp_u++;$_igmp_tot++; }
				else { $_igmp_ha++;$_igmp_tot++; }
			# Other
			} else {
				if (/ASSURED/) { $_other_a++; }
				elsif (/UNREPLIED/) { $_other_u++; }
				else { $_other_ha++; }
				$_other_tot++;
			}
		}
		if (/ASSURED/) { $_tot_a++; }
		elsif (/UNREPLIED/) { $_tot_u++; }
		else { $_tot_ha++; }
		$_tot++;
	}

	close($handler) or die("$!");
}
#=======================================================================
my $_stat = "tcp_ss:$_tcp_ss tcp_sr:$_tcp_sr tcp_e:$_tcp_e tcp_fw:$_tcp_fw "
			."tcp_cw:$_tcp_cw tcp_la:$_tcp_la tcp_tw:$_tcp_tw tcp_c:$_tcp_c "
			."tcp_ss2:$_tcp_ss2 tcp_n:$_tcp_n tcp_unk:$_tcp_unk "
			."tcp_a:$_tcp_a tcp_u:$_tcp_u tcp_ha:$_tcp_ha tcp_tot:$_tcp_tot "
			."udp_a:$_udp_a udp_u:$_udp_u udp_ha:$_udp_ha udp_tot:$_udp_tot "
			."icmp_u:$_icmp_u icmp_ha:$_icmp_ha icmp_tot:$_icmp_tot "
			."igmp_u:$_igmp_u igmp_ha:$_igmp_ha igmp_tot:$_igmp_tot "
			."other_a:$_other_a other_u:$_other_u other_ha:$_other_ha other_tot:$_other_tot "
			."tot_a:$_tot_a tot_u:$_tot_u tot_ha:$_tot_ha tot:$_tot ";

if ($_runmode == 2) { print($_stat); exit 0; }
#=======================================================================
my $_save;
open($_save, '>', $_tempfile) or die("Can't write data to file: \"$_tempfile\", error: $!");
print($_save $_stat);
close($_save) or warn("Error closing file: \"$_tempfile\", error: $!");

if ($_runmode == 1) { exit 0; }
#=======================================================================
$_info = $_info.
"###################
[TCP]
unreplied:\t$_tcp_u
half-assured:\t$_tcp_ha
assured:\t$_tcp_a
total:\t\t$_tcp_tot

[FLAGS]
established:\t$_tcp_e
timewait:\t$_tcp_tw
finwait:\t$_tcp_fw
synsent:\t$_tcp_ss
synsent2:\t$_tcp_ss2
synrecv:\t$_tcp_sr
closewait:\t$_tcp_cw
close:\t\t$_tcp_c
lastack:\t$_tcp_la
none:\t\t$_tcp_n
unknown:\t$_tcp_unk
###################
[UDP]
unreplied:\t$_udp_u
half-assured:\t$_udp_ha
assured:\t$_udp_a
total:\t\t$_udp_tot
###################
[ICMP]
unreplied:\t$_icmp_u
half-assured:\t$_icmp_ha
total:\t\t$_icmp_tot
###################
[IGMP]
unreplied:\t$_igmp_u
half-assured:\t$_igmp_ha
total:\t\t$_igmp_tot
###################
[Other]
unreplied:\t$_other_u
half-assured:\t$_other_ha
assured:\t$_other_a
total:\t\t$_other_tot
###################
[NF total]
unreplied:\t$_tot_u
half-assured:\t$_tot_ha
assured:\t$_tot_a
total:\t\t$_tot
###################
localhost:\t$_tot_lh
###################
";
if ($_localhost) { $_info =~ s/(localhost)/$1(IGNORED)/; }
print($_info);
#=======================================================================

