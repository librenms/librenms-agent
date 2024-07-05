#!/usr/bin/env perl

=head1 NAME

redis - LinbreNMS JSON extend for redis.

=head1 SYNOPSIS

redis [B<-B>] [B<-c> <config file>]

redis [B<-v>|B<--version>]

redis [B<-h>|B<--help>]

=head1 SWITCHES

=head2 -c

Config file to use.

Default: /usr/local/etc/redis_extend.json

=head2 -B

Do not the return output via GZip+Base64.

=head2 -h|--help

Print help info.

=head2 -v|--version

Print version info.

=head1 SETUP

Install the depends.

    # FreeBSD
    pkg install p5-JSON p5-TOML p5-MIME-Base64
    # Debian
    apt-get install libjson-perl libmime-base64-perl

Create the cache dir, by default "/var/cache/".

Then set it up in SNMPD.

    # if running it via cron
    extend redis /usr/local/etc/snmp/redis.pl

If for multiple instances or the default of 'redis-cli info'
won't work, a config file will be needed. The config format
is JSON.

The config entries are as below.

      - command :: If single instance, the command to use.
          Type :: String
          Default :: redis-cli

      - instances :: A hash where the keys are the instances names
                and the values for each key are the command to use.

The default config would be like below, which will be what is used
if no config file is specified/found.

    {
        "command": "redis-cli info"
    }

For something with two instances, "foo" on port 6379 and "bar" on port 6380
it would be like below.

    {
        "instances": {
            "foo": "redis-cli -p 6379",
            "bar": "redis-cli -p 6380"
        }
    }

=cut

use warnings;
use strict;
use JSON;
use Getopt::Std;
use MIME::Base64;
use IO::Compress::Gzip qw(gzip $GzipError);
use File::Slurp;
use Pod::Usage;

$Getopt::Std::STANDARD_HELP_VERSION = 1;

sub main::VERSION_MESSAGE {
	print "LibreNMS redis extend 0.0.1\n";
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

my $return_json = {
	error       => 0,
	errorString => '',
	version     => 2,
	data        => { 'extend_errors' => [] },
};

#gets the options
my %opts = ();
getopts( 'Bhvc:', \%opts );

if ( !defined( $opts{c} ) ) {
	$opts{c} = '/usr/local/etc/redis_extend.json';
}

if ( $opts{v} ) {
	main::VERSION_MESSAGE;
	exit 256;
}

if ( $opts{h} ) {
	main::VERSION_MESSAGE;
	pod2usage( -exitval => 255, -verbose => 2, -output => \*STDOUT, );
	exit 256;
}

my $single = 1;
my $config = { command => 'redis-cli info' };
if ( -f $opts{c} ) {
	eval {
		my $raw_config = read_file( $opts{c} );
		$config = decode_json($raw_config);
		if ( !defined( $config->{instances} ) ) {
			if ( !defined( $config->{command} ) ) {
				$config->{command} = 'redis-cli info';
			}
		} elsif ( ref( $config->{instances} ) ne 'HASH' ) {
			die( '.instances is defined and is not a hash but ref type ' . ref( $config->{instances} ) );
		} else {
			$single = 0;
		}
	};
	if ($@) {
		push( @{ $return_json->{data}{extend_errors} }, $@ );
		return_the_data( $return_json, $opts{B} );
		exit 0;
	}
} ## end if ( -f $opts{c} )

# ensure that $ENV{PATH} has has it
$ENV{PATH} = $ENV{PATH} . ':/usr/bin:/usr/sbin:/usr/local/sbin:/usr/local/bin';

if ($single) {
	my $command    = $config->{command};
	my $output_raw = `$command 2> /dev/null`;
	if ( $? != 0 ) {
		push(
			@{ $return_json->{data}{extend_errors} },
			'"' . $command . '" exited non-zero for with... ' . $output_raw
		);
	} else {
		$output_raw =~ s/\r//g;
		my $section;
		foreach my $line ( split( /\n/, $output_raw ) ) {
			if ( $line ne '' && $line =~ /^# / ) {
				$line =~ s/^# //;
				$section = $line;
				$return_json->{data}{$section} = {};
			} elsif ( $line ne '' && defined($section) ) {
				my ( $key, $value ) = split( /\:/, $line );
				if ( defined($key) && defined($value) ) {
					$return_json->{data}{$section}{$key} = $value;
				}
			}
		} ## end foreach my $line ( split( /\n/, $output_raw ) )
	} ## end else [ if ( $? != 0 ) ]
} else {
	my @instances = keys( %{ $config->{instances} } );
	$return_json->{data}{instances} = {};
	foreach my $instance (@instances) {
		if ( ref( $config->{instances}{$instance} ) ne '' ) {
			push(
				@{ $return_json->{data}{extend_errors} },
				'instance "' . $instance . '" is ref type ' . ref( $config->{instances}{$instance} )
			);
		} elsif ( $instance =~ /^[\-\_]/ ) {
			push( @{ $return_json->{data}{extend_errors} }, 'instance "' . $instance . '" matches /^[\-\_]/' );
		} elsif ( $instance =~ /[\-\_\n\s\"\']$/ ) {
			push( @{ $return_json->{data}{extend_errors} },
				'instance "' . $instance . '" matches /[\-\_\n\s\'\\\"]$/' );
		} else {
			my $command    = $config->{instances}{$instance};
			my $output_raw = `$command 2> /dev/null`;
			if ( $? != 0 ) {
				push(
					@{ $return_json->{data}{extend_errors} },
					'"' . $command . '" exited non-zero for instance "' . $instance . '" with... ' . $output_raw
				);
			} else {
				$output_raw =~ s/\r//g;
				my $section;
				$return_json->{data}{instances}{$instance} = {};
				foreach my $line ( split( /\n/, $output_raw ) ) {
					if ( $line ne '' && $line =~ /^# / ) {
						$line =~ s/^# //;
						$section = $line;
						$return_json->{data}{instances}{$instance}{$section} = {};
					} elsif ( $line ne '' && defined($section) ) {
						my ( $key, $value ) = split( /\:/, $line );
						if ( defined($key) && defined($value) ) {
							$return_json->{data}{instances}{$instance}{$section}{$key} = $value;
						}
					}
				} ## end foreach my $line ( split( /\n/, $output_raw ) )
			} ## end else [ if ( $? != 0 ) ]
		} ## end else [ if ( ref( $config->{instances}{$instance} ...))]
	} ## end foreach my $instance (@instances)
} ## end else [ if ($single) ]

return_the_data( $return_json, $opts{B} );
exit 0;
