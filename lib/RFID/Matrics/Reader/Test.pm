package RFID::Matrics::Reader::Test;
use RFID::Matrics::Reader; $VERSION=$RFID::Matrics::Reader::VERSION;

# Written by Scott Gifford <gifford@umich.edu>
# Copyright (C) 2004 The Regents of the University of Michigan.
# See the file LICENSE included with the distribution for license
# information.

=head1 NAME

RFID::Matrics::Reader::Test - A fake implementation of L<RFID::Matrics::Reader|RFID::Matrics::Reader> for testing

=head1 SYNOPSIS

Provides fake backend methods to test out
L<RFID::Matrics::Reader|RFID::Matrics::Reader> without having access
to a real reader.

=cut

use RFID::Matrics::Reader qw(hexdump);
our @ISA = qw(RFID::Matrics::Reader Exporter);

use constant {
    STATE_INITIAL => 0,
    STATE_GOTSOF => 1,
    STATE_GOTADDR => 2,
    STATE_GETTINGDATA => 3,
    STATE_GOTDATA => 4,
    STATE_RESPONDING => 5,
};

our %TESTRESPONSE = 
    (
     # Start constant read

     # Stop constant read
     hex2bin('01 04 05 26 0a 45') 
       => hex2bin('01 04 06 25 00 6b 9a'),
     
     # Get parameter block
     hex2bin('01 04 06 24 a0 b9 26') 
       => hex2bin('01 04 26 24 00 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 8a f6'),

     # Set parameter block
     hex2bin('01 04 29 23 01 00 00 00 ff 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 bf 9e')
       => hex2bin('01 04 06 23 00 bb ce'),

     # Get node address
     hex2bin('01 ff 0d 19 af 03 00 00 00 00 00 00 af 8f')
       => hex2bin('01 04 06 19 00 69 85'),
     
     # Get node status
     hex2bin('01 04 05 14 9b 57')
       => hex2bin('01 04 26 14 00 af 03 00 00 00 00 00 00 02 01 02 00 00 00 00 00 01 01 00 00 00 00 00 00 00 00 00 00 00 00 e7 0f e4 6f'),

     # Read tags
     hex2bin('01 04 06 22 a0 69 72')
       => hex2bin('01 04 35 22 01 a0 05 00 de 09 96 00 a8 07 05 c8 02 02 c4 76 01 00 00 00 00 02 02 c0 76 01 00 00 00 00 02 02 bc 76 01 00 00 00 00 02 02 bc 76 01 00 00 00 00 5a 0b')
        . hex2bin('01 04 0c 22 00 05 00 23 00 00 00 81 e9'),
     );

sub new
{
    my $class = shift;
    my(%p)=@_;
    my $self = {};
    bless $self,$class;
    
    $self->_initstate();
    $self->_init(%p);

    $self;
}

sub _initstate
{
    my $self = shift;
    
    $self->{_state} = STATE_INITIAL;
    $self->{_readbuf}='';
    $self->{_writebuf}='';
    $self->{_bytesleft}=0;
}

sub _writebytes
{
    my $self = shift;
    eval {
	foreach my $b (split(//,$_[0]))
	{
	    if ($self->{_state} == STATE_INITIAL)
	    {
		if (ord($b) == 0x01)
		{
		    $self->{_state} = STATE_GOTSOF;
		}
	    }
	    elsif ($self->{_state} == STATE_GOTSOF)
	    {
		$self->{_state} = STATE_GOTADDR;
	    }
	    elsif ($self->{_state} == STATE_GOTADDR)
	    {
		$self->{_bytesleft} = ord($b) - 2;
		$self->{_state} = STATE_GETTINGDATA;
	    }
	    elsif ($self->{_state} == STATE_GETTINGDATA)
	    {
		if (!(--$self->{_bytesleft}))
		{
		    $self->{_state} = STATE_GOTDATA;
		}
	    }
	    elsif ($self->{_state} == STATE_GOTDATA)
	    {
		die "Tried to write more data before response was read!";
	    }
	    else
	    {
		die "Unexpected state in _writebytes: $self->{_state}";
	    }
	    $self->{_readbuf} .= $b;
	}
    };
    return $self->error($@)
	if $@;
    1;
}

sub _readbytes
{
    my $self = shift;
    my($wantbytes)=@_;

    if ($self->{_state} == STATE_GOTDATA)
    {
	$self->{_writebuf} = $TESTRESPONSE{$self->{_readbuf}}
  	  or die "Unexpected input: ",hexdump($self->{_readbuf}),"\n";
	$self->{_state} = STATE_RESPONDING;
    }
    
    # Fall through from above
    if ($self->{_state} == STATE_RESPONDING)
    {
	if ($wantbytes > length($self->{_writebuf}))
	{
	    die "Tried to read too many bytes";
	}
	my $ret = substr($self->{_writebuf},0,$wantbytes,'');
	
	if ($self->{_writebuf} eq '')
	{
	    $self->_initstate;
	}
	return $ret;
    }
    else
    {
	die "Unexpected state in _readbytes: $self->{_state}!";
    }
}

sub stop_constant_read
{
    my $self = shift;

    # State needs to be reset; this is a quick hack, but that's OK
    # since this is just a test module.
    $self->_initstate;

    $self->SUPER::stop_constant_read();
}

sub hex2bin
{
    my $hex = $_[0];
    $hex =~ tr/0-9a-fA-F//cd;
    pack("C*",map { hex } unpack("a2"x(length($hex)/2),$hex));
}
    
1;

=head1 SEE ALSO

L<RFID::Matrics::Reader>, L<RFID::Matrics::Reader::Serial>,
L<RFID::Matrics::Reader::TCP>.

=head1 AUTHOR

Scott Gifford <gifford@umich.edu>, <sgifford@suspectclass.com>

Copyright (C) 2004 The Regents of the University of Michigan.

See the file LICENSE included with the distribution for license
information.

=cut

1;
