#!/usr/bin/perl -w

# Written by Scott Gifford <gifford@umich.edu>
# Copyright (C) 2004 The Regents of the University of Michigan.
# See the file LICENSE included with the distribution for license
# information.

use strict;

use Getopt::Std;

use RFID::Matrics::Reader qw(:ant);

use constant TAG_TIMEOUT => 10;
use constant CMD_TIMEOUT => 15;
use constant POLL_TIME => 2;
use constant DEFAULT_NODE => 4;

our($debug, $node, @ant);
our %opt;
getopts("h:c:n:a:d",\%opt)
    or die "Usage: $0 [-cd]\n";
$debug=$opt{d}||$ENV{MATRICS_DEBUG};
$node=$opt{n}||DEFAULT_NODE;
if ($opt{a})
{
    my @antsel = (MATRICS_ANT_1,
		  MATRICS_ANT_2,
		  MATRICS_ANT_3,
		  MATRICS_ANT_4,
		  );
    foreach my $a (split(/,/,$opt{a}))
    {
	if (!$antsel[$a-1])
	{
	    die "Unrecognized antenna $a\n";
	}
	push(@ant,$antsel[$a-1])
    }
}
else
{
    @ant = (MATRICS_ANT_1);
}
$| = 1;

our($com,$reader);

END {
    if ($com)
    {
	$com->purge_all();
    }
    if ($reader)
    {
	$reader->finish()
	    or warn "Couldn't stop constant read: $!\n";
    }
    if ($com)
    {
	$com->close()
	    or warn "Couldn't close COM port: $!\n";
    }
}

# Uncaught signals don't call END blocks.
for my $sig (grep { exists $SIG{$_} } qw(INT TERM BREAK HUP))
{
    $SIG{$sig} = sub { exit(1); };
}

if ($opt{c})
{
    eval '
      use Win32::Serialport;
      use RFID::Matrics::Reader::Serial;
    ';
    $@ and die $@;

    $com = Win32::SerialPort->new($opt{c})
	or die "Couldn't open COM port '$opt{c}': $^E\n";
    $reader = RFID::Matrics::Reader::Serial->new(comport => $com,
						 node => $node,
						 antenna => $ant[0],
						 debug => $debug,
						 Timeout => CMD_TIMEOUT,
						 )
	or die "Couldn't create RFID reader object: $!\n";
}
elsif ($opt{h})
{
    eval '
      use RFID::Matrics::Reader::TCP;
    ';
    $@ and die $@;

    my($addr,$port);
    if ($opt{h} =~ /^([\w.-]+):(\d+)$/)
    {
	($addr,$port)=($1,$2);
    }
    else
    {
	$addr = $opt{h};
	$port = 4001;
    }
    
    $reader = RFID::Matrics::Reader::TCP->new(PeerAddr => $addr,
					      PeerPort => $port,
					      node => $node,
					      antenna => $ant[0],
					      debug => $debug,
					      Timeout => CMD_TIMEOUT,
					      )
	or die "Couldn't create RFID reader object: $!\n";
}
else
{
    die "Must specify -c comport or -h hostname:port\n";
}

our $pb = $reader->getreaderstatus()
    or die "Couldn't getreaderstatus: $reader->{error}\n";
print "DEBUG $0 found firmware $pb->{version}\n";

# Set up antennas
foreach my $ant (@ant)
{
    my $setresp = $reader->setparamblock(antenna => $ant,
					 power_level => 0xff,
					 environment => 4,
					 combine_antenna_bits => 0,
					 )
	or warn "Couldn't setparamblock for antenna $ant: $reader->{error}\n";
}

# Now start polling
while(1)
{
    foreach my $ant (@ant)
    {
	my $pp = $reader->readfullfield_unique(antenna => $ant)
	    or die "Error in readfullfield: $reader->{error}\n";
	foreach my $tag (@{$pp->{utags}})
	{
	    print "ISEE matrics.$tag->{id} FROM matrics.$pp->{node}.$pp->{antenna} AT ",time()," TIMEOUT ",TAG_TIMEOUT,"\n";
	}
    }
    sleep(POLL_TIME);
}

# Nothing below here is ever reached (exits on signal)


