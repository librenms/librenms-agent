#!/usr/bin/env perl

use warnings;
use strict;

=head1 NAME

wireguard - LinbreNMS JSON extend for wireguard.

=head1 VERSION

0.0.3

=cut

our $VERSION = '0.0.3';

=head1 SYNOPSIS

wireguard [B<-B>] [B<-c> <config file>] [B<-p><0|1>] [B<-r> <resolvers string>] [B<-s><0|1>]

wireguard [B<-v>|B<--version>]

wireguard [B<-h>|B<--help>]

=head1 SWITCHES

=head2 -c <config>

Config file to use.

Default: /usr/local/etc/wireguard_extend.json

=head2 -p <0|1>

Include the public key.

Overrides the config item .include_pubey .

=head2 -r <resolvers string>

A string of resolvers to use.

Overrides the config item .pubkey_resolvers .

=head2 -s <0|1>

Use short hostnames

Overrides the config item .use_short_hostname .

=head2 -B

Do not the return output via GZip+Base64.

=head2 -h|--help

Print help info.

=head2 -v|--version

Print version info.

=head1 INSTALL

Install the depends.

    # FreeBSD
    pkg install p5-JSON p5-File-Slurp p5-MIME-Base64
    # Debian
    apt-get install libjson-perl libmime-base64-perl libfile-slurp-perl

Then set it up in SNMPD.

    # if running it via cron
    extend wireguard /usr/local/etc/snmp/wireguard

=head1 CONFIG

The default config is /usr/local/etc/wireguard_extend.json .

The keys for it are as below.

    - include_pubkey :: Include the pubkey with the return.
        values :: 0|1
        default :: 0

    - use_short_hostname :: If the hostname should be shortname to just the first bit.
        values :: 0|1
        default :: 1

    - public_key_to_arbitrary_name :: An array of pubkys to name mappings.
        default :: {}

    - pubkey_resolvers :: A list of resolvers to use to convert pubkeys to names. The
            value is a comma seperated string.
        default :: config,endpoint_if_first_allowed_is_subnet_use_hosts,endpoint_if_first_allowed_is_subnet_use_ip,first_allowed_use_hosts,first_allowed_use_ip

=head2 PUBKEY RESOLVERS

=head3 config

Use the mappings from .public_key_to_arbitrary_name .

The names are unaffected by .use_short_names .

=head3 endpoint_if_first_allowed_is_subnet_use_hosts

If the first allowed IP is a subnet, see if a matching IP can
be found in hosts for the endpoint.

=head3 endpoint_if_first_allowed_is_subnet_use_getent

If the first allowed IP is a subnet, see if a hit can be
found for the endpoint IP via getent hosts.

This will possible use reverse DNS.

=head3 endpoint_if_first_allowed_is_subnet_use_ip

If the first allowed IP is a subnet, use the endpoint
IP for the name.

=head3 first_allowed_use_hosts

See if a match can be found in hosts for the first allowed IP.

=head3 first_allowed_use_getent

Use getent hosts to see try to fetch a match for the first
allowed IP.

This will possible use reverse DNS.

=head3 first_allowed_use_ip

Use the first allowed IP as the name.

=cut

use JSON;
use Getopt::Std;
use MIME::Base64;
use IO::Compress::Gzip qw(gzip $GzipError);
use File::Slurp;
use Pod::Usage;

$Getopt::Std::STANDARD_HELP_VERSION = 1;

sub main::VERSION_MESSAGE {
	print 'wireguard LibreNMS extend v. ' . $VERSION . "\n";
}

sub main::HELP_MESSAGE {
	pod2usage( -exitval => 255, -verbose => 2, -output => \*STDOUT, );
}

sub return_the_data {
	my $to_return       = $_[0];
	my $do_not_compress = $_[1];

	my $to_return_string = encode_json($to_return);

	if ($do_not_compress) {
		print $to_return_string . "\n";
		return;
	}

	my $toReturnCompressed;
	gzip \$to_return_string => \$toReturnCompressed;
	my $compressed = encode_base64($toReturnCompressed);
	$compressed =~ s/\n//g;
	$compressed = $compressed . "\n";
	print $compressed;
} ## end sub return_the_data

# arg[0]: string
# return[0]: host
# return[1]: port
sub host_port_split {
	my $string = $_[0];
	if ( !defined($string) || $string =~ /\([Nn][Oo][Nn][Ee]\)/ ) {
		return undef, undef;
	}

	my $host = $string;
	my $port = $string;
	if ( $string =~ /^\[/ ) {
		$host =~ s/^\[//;
		$host =~ s/\]\:.*$//;
		$port =~ s/^.*\]\://;
	} else {
		$host =~ s/\:.*$//;
		$port =~ s/^.*\://;
	}

	return $host, $port;
} ## end sub host_port_split

my $return_json = {
	error       => 0,
	errorString => '',
	version     => 2,
	data        => {},
};

#gets the options
my %opts = ();
getopts( 'Bhvc:r:s:p:', \%opts );

if ( !defined( $opts{c} ) ) {
	$opts{c} = '/usr/local/etc/wireguard_extend.json';
}

if ( $opts{v} ) {
	&main::VERSION_MESSAGE;
	exit 1;
}

if ( $opts{h} ) {
	&main::HELP_MESSAGE;
	exit 1;
}

##
##
## real in the config
##
##
our $config = {
	include_pubkey   => 0,
	pubkey_resolvers =>
		'config,endpoint_if_first_allowed_is_subnet_use_hosts,endpoint_if_first_allowed_is_subnet_use_ip,first_allowed_use_hosts,first_allowed_use_ip',
	use_short_hostname           => 1,
	public_key_to_arbitrary_name => {},
};
if ( -f $opts{c} ) {
	eval {
		my $raw_config    = read_file( $opts{c} );
		my $parsed_config = decode_json($raw_config);
		if ( defined( $parsed_config->{public_key_to_arbitrary_name} )
			&& ref( $parsed_config->{public_key_to_arbitrary_name} ) eq 'HASH' )
		{
			$config->{public_key_to_arbitrary_name} = $parsed_config->{public_key_to_arbitrary_name};
		}
		if ( defined( $parsed_config->{include_pubkey} ) && ref( $parsed_config->{include_pubkey} ) eq '' ) {
			$config->{include_pubkey} = $parsed_config->{include_pubkey};
		}
		if ( defined( $parsed_config->{pubkey_resolvers} ) && ref( $parsed_config->{pubkey_resolvers} ) eq '' ) {
			$config->{pubkey_resolvers} = $parsed_config->{pubkey_resolvers};
			$config->{pubkey_resolvers} =~ s/\ //g;
		}
		if ( defined( $parsed_config->{pubkey_resolver_cache_file} )
			&& ref( $parsed_config->{pubkey_resolver_cache_file} ) eq '' )
		{
			$config->{pubkey_resolver_cache_file} = $parsed_config->{pubkey_resolver_cache_file};
		}
		if ( defined( $parsed_config->{use_short_hostname} ) && ref( $parsed_config->{use_short_hostname} ) eq '' )
		{
			$config->{use_short_hostname} = $parsed_config->{use_short_hostname};
		}
	};
	if ($@) {
		$return_json->{error}       = 1;
		$return_json->{errorString} = $@;
		return_the_data( $return_json, $opts{B} );
		exit 0;
	}
} ## end if ( -f $opts{c} )

if ( defined( $opts{p} ) ) {
	$config->{include_pubkey} = $opts{p};
}

if ( defined( $opts{s} ) ) {
	$config->{use_short_hostname} = $opts{s};
}

if ( defined( $opts{r} ) ) {
	$config->{pubkey_resolvers} = $opts{r};
	$config->{pubkey_resolvers} =~ s/\ //g;
}

# ensure that $ENV{PATH} has has it
$ENV{PATH} = $ENV{PATH} . ':/usr/bin:/usr/sbin:/usr/local/sbin:/usr/local/bin';

##
##
## get all the information
##
##
my %wg_info;

# get endpoint info
my $command_raw = `wg show all endpoints 2> /dev/null`;
if ( $? == 0 ) {
	my @command_split = split( /\n/, $command_raw );
	my $interface;
	foreach my $line (@command_split) {
		my $pubkey;
		my $host;
		my $port;

		my @line_split = split( /[\t\ ]+/, $line );
		if ( defined( $line_split[2] ) ) {
			$interface = $line_split[0];
			$pubkey    = $line_split[1];
			( $host, $port ) = host_port_split( $line_split[2] );
		} else {
			$pubkey = $line_split[0];
			if ( $line_split[1] =~ /^[\[\]0-9\.A-Fa-f]+\:[0-9]+$/ ) {
				( $host, $port ) = host_port_split( $line_split[1] );
			}
		}

		if ( !defined( $wg_info{$interface} ) ) {
			$wg_info{$interface} = {};
		}

		$wg_info{$interface}{$pubkey} = {
			endpoint_host => $host,
			endpoint_port => $port,
			allowed_ips   => [],
		};
	} ## end foreach my $line (@command_split)
} ## end if ( $? == 0 )

# get the transfer info
$command_raw = `wg show all transfer 2> /dev/null`;
if ( $? == 0 ) {
	my @command_split = split( /\n/, $command_raw );
	foreach my $line (@command_split) {
		my ( $interface, $pubkey, $recv, $sent ) = split( /[\t\ ]+/, $line );
		if ( defined($sent) ) {
			$wg_info{$interface}{$pubkey}{bytes_rcvd} = $recv;
			$wg_info{$interface}{$pubkey}{bytes_sent} = $sent;
		}
	}
} ## end if ( $? == 0 )

# get the handshake	info
$command_raw = `wg show all latest-handshakes 2> /dev/null`;
my $current_time = time;
if ( $? == 0 ) {
	my @command_split = split( /\n/, $command_raw );
	foreach my $line (@command_split) {
		my ( $interface, $pubkey, $when ) = split( /[\t\ ]+/, $line );
		if ( $when == 0 ) {
			$wg_info{$interface}{$pubkey}{minutes_since_last_handshake} = undef;
		} else {
			$wg_info{$interface}{$pubkey}{minutes_since_last_handshake} = ( $current_time - $when ) / 60;
		}
	}
} ## end if ( $? == 0 )

# get allowed subnets
$command_raw = `wg show all allowed-ips 2> /dev/null`;
if ( $? == 0 ) {
	my @command_split = split( /\n/, $command_raw );
	foreach my $line (@command_split) {
		my @line_split = split( /[\t\ ]+/, $line );
		my $int        = 2;
		while ( defined( $line_split[$int] ) ) {
			if ( $line_split[$int] =~ /^[0-9\.]+\/32$/ ) {
				$line_split[$int] =~ s/\/32//;
			} elsif ( $line_split[$int] =~ /^[A-Fa-f0-9\:]+\/128$/ ) {
				$line_split[$int] =~ s/\/128//;
			}
			push( @{ $wg_info{ $line_split[0] }{ $line_split[1] }{allowed_ips} }, $line_split[$int] );
			$int++;
		}
	} ## end foreach my $line (@command_split)
} ## end if ( $? == 0 )

##
##
## try to translate pubkeys to a name
##
##
sub getent_hosts {
	my $ip = $_[0];
	if ( !defined($ip) ) {
		return undef;
	}
	# a bit of sanity checking, but this should never hit... wg should only return IPs for what this is used for
	if ( $ip !~ /^[a-fA-F\:\.0-9]+$/ ) {
		return undef;
	}
	my $command_raw = `getent hosts $ip 2> /dev/null`;
	if ( $? != 0 ) {
		return undef;
	}
	my @command_split = split( /\n/, $command_raw );
	if ( defined( $command_split[0] ) ) {
		my @line_split = split( /[\t\ ]+/, $command_split[0] );
		if ( defined( $line_split[1] ) ) {
			$line_split[1] =~ s/^\.//;
			return $line_split[1];
		}
	}
	return undef;
} ## end sub getent_hosts

our $hosts_read = 0;
our $hosts      = {};

sub hosts {
	my $ip = $_[0];
	if ( !defined($ip) ) {
		return undef;
	}
	if ( !$hosts_read ) {
		$hosts_read = 1;
		eval {
			my $hosts_raw   = read_file('/etc/hosts');
			my @hosts_split = grep( !/^[\t\ ]*$/, grep( !/^[\ \t]*\#/, split( /\n/, $hosts_raw ) ) );
			foreach my $line (@hosts_split) {
				my @line_split = split( /[\t\ ]+/, $line );
				if ( defined( $line_split[0] ) && defined( $line_split[1] ) ) {
					$line_split[1] =~ s/^\.//;
					$hosts->{ $line_split[0] } = $line_split[1];
				}
			}
		};
	} ## end if ( !$hosts_read )
	if ( defined( $hosts->{$ip} ) ) {
		return $hosts->{$ip};
	}
	return undef;
} ## end sub hosts

my @interfaces = keys(%wg_info);
my @resolvers  = split( /\,+/, $config->{pubkey_resolvers} );
foreach my $interface (@interfaces) {
	my @pubkeys = keys( %{ $wg_info{$interface} } );
	foreach my $pubkey (@pubkeys) {
		my $matched       = 0;
		my $resolvers_int = 0;
		while ( !$matched && defined( $resolvers[$resolvers_int] ) ) {
			my $resolver = $resolvers[$resolvers_int];
			if ( !$matched && $resolver eq 'config' ) {
				if ( defined( $config->{public_key_to_arbitrary_name}{$pubkey} ) ) {
					$wg_info{$interface}{$pubkey}{name}     = $config->{public_key_to_arbitrary_name}{$pubkey};
					$wg_info{$interface}{$pubkey}{hostname} = undef;
					$matched                                = 1;
				}
			} elsif ( !$matched && $resolver eq 'endpoint_if_first_allowed_is_subnet_use_getent' ) {
				if (   defined( $wg_info{$interface}{$pubkey}{allowed_ips}[0] )
					&& $wg_info{$interface}{$pubkey}{allowed_ips}[0] =~ /\//
					&& defined( $wg_info{$interface}{$pubkey}{endpoint_host} ) )
				{
					my $name = getent_hosts( $wg_info{$interface}{$pubkey}{endpoint_host} );
					if ( defined($name) ) {
						$wg_info{$interface}{$pubkey}{hostname} = $name;
						$matched = 1;
					}
				} ## end if ( defined( $wg_info{$interface}{$pubkey...}))
			} elsif ( !$matched && $resolver eq 'endpoint_if_first_allowed_is_subnet_use_hosts' ) {
				if (   defined( $wg_info{$interface}{$pubkey}{allowed_ips}[0] )
					&& $wg_info{$interface}{$pubkey}{allowed_ips}[0] =~ /\//
					&& defined( $wg_info{$interface}{$pubkey}{endpoint_host} ) )
				{
					my $name = hosts( $wg_info{$interface}{$pubkey}{endpoint_host} );
					if ( defined($name) ) {
						$wg_info{$interface}{$pubkey}{hostname} = $name;
						$matched = 1;
					}
				} ## end if ( defined( $wg_info{$interface}{$pubkey...}))
			} elsif ( !$matched && $resolver eq 'endpoint_if_first_allowed_is_subnet_use_ip' ) {
				if (   defined( $wg_info{$interface}{$pubkey}{allowed_ips}[0] )
					&& $wg_info{$interface}{$pubkey}{allowed_ips}[0] =~ /\//
					&& defined( $wg_info{$interface}{$pubkey}{endpoint_host} ) )
				{
					$wg_info{$interface}{$pubkey}{hostname} = $wg_info{$interface}{$pubkey}{endpoint_host};
					$matched = 1;
				}
			} elsif ( !$matched && $resolver eq 'first_allowed_use_getent' ) {
				if ( defined( $wg_info{$interface}{$pubkey}{allowed_ips}[0] ) ) {
					my $host = $wg_info{$interface}{$pubkey}{allowed_ips}[0];
					my $name = getent_hosts($host);
					if ( defined($name) ) {
						$wg_info{$interface}{$pubkey}{hostname} = $name;
						$matched = 1;
					}
				}
			} elsif ( !$matched && $resolver eq 'first_allowed_use_hosts' ) {
				if ( defined( $wg_info{$interface}{$pubkey}{allowed_ips}[0] ) ) {
					my $host = $wg_info{$interface}{$pubkey}{allowed_ips}[0];
					my $name = hosts($host);
					if ( defined($name) ) {
						$wg_info{$interface}{$pubkey}{hostname} = $name;
						$matched = 1;
					}
				}
			} elsif ( !$matched && $resolver eq 'first_allowed_use_ip' ) {
				$wg_info{$interface}{$pubkey}{hostname} = $wg_info{$interface}{$pubkey}{allowed_ips}[0];
				$matched = 1;
			}
			$resolvers_int++;
		} ## end while ( !$matched && defined( $resolvers[$resolvers_int...]))
	} ## end foreach my $pubkey (@pubkeys)
} ## end foreach my $interface (@interfaces)

##
##
## translate found information to output info
##
##

foreach my $interface (@interfaces) {
	my @pubkeys = keys( %{ $wg_info{$interface} } );
	foreach my $pubkey (@pubkeys) {
		if ( defined( $wg_info{$interface}{$pubkey}{name} ) || $wg_info{$interface}{$pubkey}{hostname} ) {
			if ( !defined( $return_json->{data}{$interface} ) ) {
				$return_json->{data}{$interface} = {};
			}
			my $name;
			if ( defined( $wg_info{$interface}{$pubkey}{name} ) ) {
				$name = $wg_info{$interface}{$pubkey}{name};
				delete( $wg_info{$interface}{$pubkey}{name} );
			} else {
				$name = $wg_info{$interface}{$pubkey}{hostname};
				if ( $config->{use_short_hostname} && $name !~ /^[0-9\.]+$/) {
					$name =~ s/\..*$//;
				}
			}
			$return_json->{data}{$interface}{$name} = $wg_info{$interface}{$pubkey};
			if ( $config->{include_pubkey} ) {
				$return_json->{data}{$interface}{$name}{pubkey} = $pubkey;
			} else {
				$return_json->{data}{$interface}{$name}{pubkey} = undef;
			}
		} ## end if ( defined( $wg_info{$interface}{$pubkey...}))
	} ## end foreach my $pubkey (@pubkeys)
} ## end foreach my $interface (@interfaces)

return_the_data( $return_json, $opts{B} );
