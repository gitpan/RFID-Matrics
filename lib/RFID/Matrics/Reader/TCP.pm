package RFID::Matrics::Reader::TCP;
use RFID::Matrics::Reader; $VERSION=$RFID::Matrics::Reader::VERSION;

# Written by Scott Gifford <gifford@umich.edu>
# Copyright (C) 2004 The Regents of the University of Michigan.
# See the file LICENSE included with the distribution for license
# information.

=head1 NAME

RFID::Matrics::Reader::TCP - Implement L<RFID::Matrics::Reader|RFID::Matrics::Reader> over a TCP connection

=head1 SYNOPSIS

This class takes a host and port to connect to, connects to it, and
implements the Matrics RFID protocol over that connection.  It is
designed to use a serial-to-Ethernet adapter plugged into the serial
port of the reader; I tested it with the I<NPort Express> from Moxa.

An example:

    use RFID::Matrics::Reader::TCP;

    my $reader = 
      RFID::Matrics::Reader::TCP->new(PeerAddr => 1.2.3.4,
				      PeerPort => 4001,
				      node => 4,
				      antenna => MATRICS_ANT_1,
				      debug => 1,
				      timeout => CMD_TIMEOUT,
				      )
        or die "Couldn't create reader object.\n";

    $reader->changeparam(antenna => MATRICS_ANT_1,
			 environment => 4,
			 power_level => 0xff,
			 combine_antenna_bits => 0);
    my $rff = $reader->readfullfield(antenna => MATRICS_ANT_1);
    foreach my $tag (@{$pp->{utags}})
    {
	print "I see tag $tag->{id}\n";
    }

=head1 DESCRIPTION

This class is built on top of
L<RFID::Matrics::Reader|RFID::Matrics::Reader> and
L<IO::Socket::INET>, and implements the underlying setup, reading, and
writing functions.  It has some special implementation details to deal
with the I<timeout> parameter.

=cut

use RFID::Matrics::Reader qw(:ant);
use IO::Socket::INET;
use IO::Select;

our @ISA = qw(RFID::Matrics::Reader Exporter);
our @EXPORT_OK = @RFID::Matrics::Reader::EXPORT_OK;
our %EXPORT_TAGS = %RFID::Matrics::Reader::EXPORT_TAGS;

=head2 Constructor

=head3 new

This constructor accepts all arguments to the constructors for
L<RFID::Matrics::Reader|RFID::Matrics::Reader> and
L<IO::Socket::INET|IO::Socket::INET>, and passes them along to both
constructors.

=cut

sub new
{
    my $class = shift;
    my(%p)=@_;
    
    my $self = {};

    # For IO::Socket::INET
    if ($p{timeout} && !$p{Timeout})
    {
	$p{Timeout}=$p{timeout};
    }

    $self->{_sock}=IO::Socket::INET->new(%p)
	or die "Couldn't create socket: $!\n";
    $self->{_select}=IO::Select->new($self->{_sock})
	or die "Couldn't create IO::Select: $!\n";
    bless $self,$class;

    $self->_init(%p);

    $self;
}

sub _readbytes
{
    my $self = shift;
    my($bytesleft)=@_;
    my $data = "";

    while($bytesleft > 0)
    {
	my $moredata;
	if ($self->{timeout})
	{
	    $self->{_select}->can_read($self->{timeout})
		or die "Read timed out.\n";
	}
	my $rb = $self->{_sock}->sysread($moredata,$bytesleft)
	    or die "Socket unexpectedly closed!\n";
	$bytesleft -= $rb;
	$data .= $moredata;
    }
    $data;
}

sub _writebytes
{
    my $self = shift;
    if ($self->{timeout})
    {
	$self->{_select}->can_write($self->{timeout})
	    or die "Write timed out.\n";
    }
    $self->{_sock}->syswrite(@_);
}

sub _connected
{
    return $self->{_sock};
}

=head1 SEE ALSO

L<RFID::Matrics::Reader>, L<RFID::Matrics::Reader::Serial>,
L<IO::Socket::INET>.

=head1 AUTHOR

Scott Gifford <gifford@umich.edu>, <sgifford@suspectclass.com>

Copyright (C) 2004 The Regents of the University of Michigan.

See the file LICENSE included with the distribution for license
information.

1;
