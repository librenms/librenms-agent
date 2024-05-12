#!/usr/bin/env perl

=head1 NAME

logsize - LinbreNMS JSON extend for redis.

=head1 SYNOPSIS

logsize [B<-B>]

=head1 SWITCHES

=head2 -B

Do not the return output via GZip+Base64.

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

=cut

use warnings;
use strict;
use JSON;
use Getopt::Std;
use MIME::Base64;
use IO::Compress::Gzip qw(gzip $GzipError);
use File::Slurp;

$Getopt::Std::STANDARD_HELP_VERSION = 1;

sub main::VERSION_MESSAGE {
	print "LibreNMS redis extend 0.0.1\n";
}

sub main::HELP_MESSAGE {
	print '

-B               Do not use Gzip+Base64 for the output.
';
}

my $return_json = {
	error       => 0,
	errorString => '',
	version     => 1,
	data        => {
	},
};

#gets the options
my %opts = ();
getopts( 'B', \%opts );

# ensure that $ENV{PATH} has has it
$ENV{PATH}=$ENV{PATH}.':/usr/bin:/usr/sbin:/usr/local/sbin:/usr/local/bin';

my $output_raw=`redis-cli info 2> /dev/null`;
if ($? != 0) {
	$return_json->{error}=1;
	$return_json->{error}='redis-cli info exited non-zero';
	print encode_json($return_json)."\n";
}

$output_raw=~s/\r//g;
my $section;
foreach my $line (split(/\n/, $output_raw)) {
	if ($line ne '' && $line =~ /^# /) {
		$line =~ s/^# //;
		$section= $line;
		$return_json->{data}{$section}={};
	}elsif ($line ne '' && defined($section)) {
		my ($key, $value)=split(/\:/, $line);
		if (defined($key) && defined($value)) {
			$return_json->{data}{$section}{$key}=$value;
		}
	}
}

my $return_json_raw=encode_json($return_json);
if ($opts{B}) {
	print $return_json_raw."\n";
	exit 0;
}

my $toReturnCompressed;
gzip \$return_json_raw => \$toReturnCompressed;
my $compressed = encode_base64($toReturnCompressed);
$compressed =~ s/\n//g;
$compressed = $compressed . "\n";
print $compressed;
