package RFID::Matrics::Reader;
our $VERSION = '0.001';

# Written by Scott Gifford <gifford@umich.edu>
# Copyright (C) 2004 The Regents of the University of Michigan.
# See the file LICENSE included with the distribution for license
# information.

=head1 NAME

RFID::Matrics::Reader - Abstract base class for a Matrics RFID reader

=head1 SYNOPSIS

This abstract base class provides most of the methods required for
interfacing Perl with a Matrics RFID reader.  To actually create an
object, use L<RFID::Matrics::Reader::Serial> or
L<RFID::Matrics::Reader::TCP>.

    use RFID::Matrics::Reader::Serial;
    my $reader = 
      RFID::Matrics::Reader::Serial->new(comport => $com,
				         node => 4,
					 antenna => MATRICS_ANT_1);
    $reader->changeparam(antenna => MATRICS_ANT_1,
			 environment => 4,
			 power_level => 0xff,
			 combine_antenna_bits => 0);
    my $rff = $reader->readfullfield_unique(antenna => MATRICS_ANT_1);
    foreach my $tag (@{$pp->{utags}})
    {
	print "I see tag $tag->{id}\n";
    }

=head1 DESCRIPTION

This abstract base class implements the commands for communicating
with a Matrics reader.  It is written according to the specifications
in Matrics' I<Stationary Reader / Host Protocol (RS-485)
Specification>, using version 2.8 from October 19th 2003.  It was
tested with an RDR-001 model reader.

To actually create a reader object, use
L<RFID::Matrics::Reader::Serial> or L<RFID::Matrics::Reader::TCP>.
Those classes inherit from this one.

=cut

use Exporter;
use Carp qw(cluck croak carp);
use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter);
@EXPORT_OK = qw(MATRICS_ANT_1 MATRICS_ANT_2 MATRICS_ANT_3 MATRICS_ANT_4 hexdump);
%EXPORT_TAGS = (ant => [ qw(MATRICS_ANT_1 MATRICS_ANT_2 MATRICS_ANT_3 MATRICS_ANT_4)]);

use RFID::Matrics::CRC qw(crc);
use RFID::Matrics::Tag qw(:tagtypes tagcmp);

=head2 CONSTANTS

=over 4

=item MATRICS_ANT_I<n>

Specific antennas on the reader.  The constants I<MATRICS_ANT_1>,
I<MATRICS_ANT_2>, I<MATRICS_ANT_3>, I<MATRICS_ANT_4> are provided.

=cut

use constant MATRICS_ANT_1 => 0xa0;
use constant MATRICS_ANT_2 => 0xb0;
use constant MATRICS_ANT_3 => 0xc0;
use constant MATRICS_ANT_4 => 0xd0;

=back

=head2 METHODS

=cut

our %_errmsgs = (
		0xF0 => "READER - Invalid command parameter(s)",
		0xF1 => "READER - Insufficient data",
		0xF2 => "READER - Command not supported",
		0xF3 => "READER - Antenna Fault (not present or shorted)",
		0xF4 => "READER - DSP Timeout",
		0xF5 => "READER - DSP Error",
		0xF6 => "READER - DSP Idle",
		0xF7 => "READER - Zero Power",
		0xFF => "READER - Undefined error",
		);

# Prototype
sub uniq(&@);

# Initializer used by derived objects
sub _init
{
    my $self = shift;
    my(%p)=@_;

    $self->{default_node} = $p{node};
    $self->{default_antenna} = $p{antenna};
    $self->{debug} = $p{debug};
    $self->{timeout} = $p{timeout}||$p{Timeout};

    $self->stop_constant_read(node => $self->{default_node})
	if ($self->{default_node} and (!$p{noinit}));
}

sub _setdefaults
{
    my $self = shift;
    my($p)=@_;
    $p->{node} = $self->{default_node}
      unless defined($p->{node});
    $p->{antenna} = $self->{default_antenna}
      unless defined($p->{antenna});
    $p;
}

sub _makepacket
{
    my $self = shift;
    my(%p)=@_;
    $self->_setdefaults(\%p);

    $p{data}||="";
    my $packet = pack("CCCa*",$p{node},length($p{data})+5,$p{cmd},$p{data});
    return pack("Ca*v",1,$packet,crc($packet));
}

sub _parsepacket
{
    my $self = shift;
    my($packet)=@_;
    my %dat;
    my $sof;
    
    my $dl = length($packet)-7;
    ($sof,@dat{qw(node len cmd status data crc)}) = unpack("CCCCCa${dl}v",$packet);
    unless ($sof==1)
    {
	return $self->error("No start of frame byte in packet!");
    }
    unless (crc(substr($packet,1,-2)) == $dat{crc})
    {
	return $self->error("Bad CRC in packet!\n");
    }
    if ( ($dat{status} & 0x80)==0x80 or ($dat{status} & 0xC0)==0xC0)
    {
	my $ec = unpack("C",$dat{data});
	return $self->error($_errmsgs{$ec},$ec);
    }
    return \%dat;
}

sub _getpacket
{
    my($self)=@_;
    $data = $self->_readbytes(3)
	or die "Couldn't read COM port: $!\n";
    length($data) == 3
	or die "COM port short read!\n";
    my($sof,$addr,$len)=unpack("CCC",$data);
    
    my $moredata = $self->_readbytes($len-2)
	or die "Couldn't read COM port: $!\n";
    length($moredata) == ($len-2)
	or die "COM port short read!\n";
    
    warn time()," RECV: ",hexdump($data.$moredata),"\n"
	if ($self->{debug});
    return $data.$moredata;
}

sub _sendpacket
{
    my $self = shift;
    my($data)=@_;

    warn time()," SEND: ",hexdump($data),"\n"
	if ($self->{debug});
    $self->_writebytes($data)
	or die "Couldn't write to COM port: $^E";
}

sub _do_something
{
    my $self = shift;
    my($cmd_sub,$resp_sub,%p)=@_;
    my @ret ;

    my $cmd = $cmd_sub->($self,%p)
	or return undef;
    $self->_sendpacket($cmd)
	or die "Couldn't write command: $!\n";

    while(1)
    {
	my $resp = $self->_getpacket()
	    or die "Couldn't read response: $!\n";
	my $pr = $resp_sub->($self,$resp)
	    or return undef;
	push(@ret,$pr);
	last unless ($pr->{status} & 0x01);
    }
    return wantarray?@ret:$ret[0];
}


=head3 getparamblock

Gets the configuration for a particular antenna on a particular
reader.  Takes a hash as an argument, which can have the following
parameters:

=over 4

=item node

Node to be queried.

=item antenna

Antenna whose configuration you want

=back

Returns a hash reference with the following attributes:

=over 4

=item power_level

The amount of power this antenna should use when doing a read, between
0 and 255.  255 is full-power; the scale of this setting is
logarithmic, so 0xC0 is about 50% power, and 0x80 is about 25% power.

=item environment

How long the reader should try to read tags during a C<readfullfield>
command, between 0 and 4.  0 will read for a very short time, and is
appropriate for environments where tags come and go very quickly, and
it's OK if you miss a tag somtimes.  4 will read for longer, and is
appropriate where tags stay relatively static and you want the reader
to try its best to find all of them.

=back

The parameters for combined antennas and filters are not yet fully
implemented.

=cut

sub getparamblock
{
    my $self = shift;
    $self->_setdefaults(\%p);
    $self->_do_something(\&_cmd_getparamblock,\&_resp_getparamblock,@_);
}


sub _cmd_getparamblock
{
    my $self = shift;
    my(%p)=@_;
    $self->_setdefaults(\%p);
    $self->_makepacket(%p,
		       cmd => 0x24,
		       data => pack("C",$p{antenna}),
		       );
}

sub _resp_getparamblock
{
    my $self = shift;
    my $pp = $self->_parsepacket(@_)
	or return undef;
    (@$pp{qw(power_level environment combine_antenna_bits protocol_speed filter_len tagtype reserved_bits filter_bits reserved_bits)}) =
	unpack("CCa1CCCa2a8a*",$pp->{data});
    $pp->{combine_antenna}=[];
    my $ca = ord $pp->{combine_antenna_bits};
    foreach my $i (0..3)
    {
	my @antarr = (MATRICS_ANT_1, MATRICS_ANT_2, MATRICS_ANT_3, MATRICS_ANT_4);
	if ($ca & (1 << $i))
	{
	    push(@{$pp{combine_antenna}},$antarr[$i]);
	}
    }
    $pp;
}

=head3 setparamblock

Sets parameters for a specific reader and antenna.  It can set all of
the parameters which can be read by I<getparamblock>.

=cut

sub setparamblock
{
    my $self = shift;
    $self->_setdefaults(\%p);

    $self->_do_something(\&_cmd_setparamblock,\&_resp_setparamblock,@_);
}

sub _cmd_setparamblock
{
    my $self = shift;
    my(%p)=@_;

    $self->_makepacket(%p,
		       cmd => 0x23,
		       data => pack("CCCCCCCCCCx2a8x16",
				    $self->_make_confwhich_ant(\%p), # Returns 4 bytes
				    $p{power_level}||0xff,
				    $p{environment}||0x00,
				    $self->_make_combine_antenna_bits(\%p),
				    $p{protocol_speed}||0,
				    $p{filter_len}||0,
				    $p{tagtype}||0,
				    $p{filter_bits}||"\0"x8,
				    )
		       );
}

sub _resp_setparamblock
{
    my $self = shift;
    my $pp = $self->_parsepacket(@_)
	or return undef;
}

=head3 changeparamblock

Reads the current parameters from the reader, changes any which are
specified in the arguments, then writes them back out.  This is
impelemented in terms of I<getparamblock> and I<setparamblock>, and
recognizes the same parameters as they do.  Returns a hash reference
with the following attributes:


=cut

sub changeparamblock
{
    my $self = shift;
    my(%p)=@_;
    $self->_setdefaults(\%p);

    croak "changeparamblock: The required parameter 'antenna' is missing.\n"
	unless ($p{antenna});
    my $curparam = $self->getparamblock(@_)
	or return undef;
    if ($p{combine_antennas})
    {
	delete $curparam->{combine_antenna_bits};
    }
    return $self->setparamblock(%$curparam, @_);
}

=head3 readfullfield

Read all tags in the field of the specified antenna.  Takes parameters
I<node> and I<antenna> to specify what field should be read, and
returns a reference to a hash containing the following attributes:

=over 4

=item numtags

The total number of tags read.  Note that this number can contain
duplicates; use I<readfullfield_unique> to filter out duplicates.

=item tags

An array reference containing zero or more
L<RFID::Matrics::Tag|RFID::Matrics::Tag> objects representing the tags
that were read.

=back

=cut

sub readfullfield
{
    my $self = shift;
    my @resp = $self->_do_something(\&_cmd_readfullfield,\&_resp_readfullfield,@_)
	or return undef;
    my $ret = shift(@resp);
    foreach my $r (@resp)
    {
	$ret->{numtags} += $r->{numtags};
    }
    $ret;
}

sub _cmd_readfullfield
{
    my $self = shift;
    my(%p)=@_;
    $self->_setdefaults(\%p);
    
    $self->_makepacket(%p,
		       cmd => 0x22,
		       data => pack("C",$p{antenna}),
		       );
}

sub _resp_readfullfield
{
    my $self = shift;
    my $pp =$self->_parsepacket(@_)
	or return undef;
    my $dc = $pp->{data};
    (@$pp{qw(antenna numtags)}) = unpack("CC",substr($dc,0,2,""));
    $pp->{tags} = [$self->_parsetags($pp->{numtags},$dc)];
    $pp;
}


=head3 readfullfield_unique

Performs a I<readfullfield>, then adds the following attributes to the
hash reference:

=over 4

=item unumtags

The number of unique tags found.

=item utags

An array reference containing zero or more
L<RFID::Matrics::Tag|RFID::Matrics::Tag> objects representing the
unique tags that were read.

=back

=cut

sub readfullfield_unique
{
    my $self = shift;
    my $pp = $self->readfullfield(@_);

    @{$pp->{utags}} = uniq { tagcmp($a,$b) }
                       sort { tagcmp($a,$b) } 
                        @{$pp->{tags}};
    $pp->{unumtags}=scalar(@{$pp->{utags}});
    $pp;
}


=head3 start_constant_read

Start a constant read until a I<stop_constant_read> command.  After
calling this method, repeatedly call I<constant_read> to get tags that
the reader sees.  The parameter to this method is a hash that can
specify the I<node> and I<antenna> that should do the reading, and
also:

=over 4

=item antenna1, antenna2, antenna3, antenna4

Which antennas should be read in each time slot.  Leave a parameter
undefined to skip that timeslot.  If I<antenna1> isn't given,
I<antenna> is used.

=item antenna1_power, antenna2_power, antenna3_power, antenna4_power

The power level for the antenna in each of the time slots.

=item dwell_time

The number of milliseconds to scan for, between 6 and 150.

=item channel

The frequency channel to use, from 0 to 16.

=back

=cut

sub start_constant_read
{
    my $self = shift;
    my(%p)=@_;
    $self->_setdefaults(\%p);

    my $cmd = $self->_cmd_start_constant_read(%p);
    $self->_sendpacket($cmd)
	or die "Couldn't read command: $!\n";
    $self->{_constant_read}{$p{node}}=1;
}

sub _cmd_start_constant_read
{
    my $self = shift;
    my(%p)=@_;

    $self->_setdefaults(\%p);
    $antflag{$_}=1
	foreach grep { defined } ($p{antenna1}||$p{antenna}||MATRICS_ANT_1,
				  @$p{qw(antenna2 antenna3 antenna4)});
    $self->_makepacket(%p,
		       cmd => 0x25,
		       data => pack("CCCCCCCCCCCCa8",
				    $p{antenna1}||$p{antenna}||0,
				    $p{antenna2}||0,
				    $p{antenna3}||0,
				    $p{antenna4}||0,
				    $p{antenna1_power}||0xff,
				    $p{antenna2_power}||$p{antenna2}?0xff:0,
				    $p{antenna3_power}||$p{antenna3}?0xff:0,
				    $p{antenna4_power}||$p{antenna4}?0xff:0,
				    $p{dwell_time}||150,
				    $p{channel}||8,
				    $p{maskbits}||0,$p{masktype}||0,
				    $p{mask}||"\0\0\0\0\0\0\0\0",
				    ),
		       );
}

sub _epc_parsetags
{
    my $self = shift;
    my($count,$dc)=@_;
    my @tags;

    foreach my $i (1..$count)
    {
	my $type = unpack("C",substr($dc,0,1,""));
	my $len = ($type == 0x0C) ? 8 : 12;
	my $id_bits = unpack("a*",substr($dc,0,$len,""));
	my $tag = RFID::Matrics::Tag->new(type => $type, id_bits => $id_bits)
	    or die "Couldn't create new RFID::Matrics::Tag object: $!\n";
	push(@tags,$tag);
    }
    @tags;
}


=head3 constant_read

Returns tags from an ongoing constant read operation.  You call
I<start_constant_read> to start reading, and I<stop_constant_read>
when you're finished.

Each time this method is called, it returns a hashref with the
following attributes:

=over 4

=item numtags

The number of tags found

=item tags

An array reference containing zero or more
L<RFID::Matrics::Tag|RFID::Matrics::Tag> objects representing the tags
that were read.

=back

=cut

sub constant_read
{
    my $self = shift;
    my(%p)=@_;
    
    $self->_setdefaults(\%p);

    croak "Please call start_constant_read before constant_read\n"
	unless ($self->{_constant_read}{$p{node}});

    my $resp = $self->_getpacket()
	or die "Couldn't read response: $!\n";
    my $pr = $self->_resp_constant_read($resp);
    return $pr;
}

sub _resp_constant_read
{
    my $self = shift;

    my $pp = $self->_parsepacket(@_);
    if (!$pp)
    {
	return { numtags => 0,
		 tags => [],
		 error => $self->{error},
		 errcode => $self->{errcode},
	     };

    }
    
    if ($pp->{error})
    {
	$pp->{numtags} = 0;
	$pp->{tags} = [];
	return $pp;
    }
    my $dc = $pp->{data};
    @$pp{qw(antenna numtags)} = unpack("CC",substr($dc,0,2,""));
    $pp->{tags} = [$self->_parsetags($pp->{numtags},$dc)];
    return $pp;
}

sub _parsetags
{
    my $self = shift;
    my($count,$dc)=@_;
    my @tags;

    foreach my $i (1..$count)
    {
	my $type_len_bits = unpack("C",substr($dc,0,1,""));
	my $len = ($type_len_bits & 0x04) ? 12 : 8;
	my $type = ($type_len_bits & 0x03);
	my $id_bits = unpack("a*",substr($dc,0,$len,""));
	my $tag = RFID::Matrics::Tag->new(type => $type, id_bits => $id_bits)
	    or die "Couldn't create new RFID::Matrics::Tag object: $!\n";
	push(@tags,$tag);
    }
    @tags;
}


=head3 stop_constant_read

Take the reader out of constant read mode.

=cut

sub stop_constant_read
{
    my $self = shift;
    my(%p)=@_;

    $self->_setdefaults(\%p);
    delete $self->{_constant_read}{$p{node}};
    $self->_do_something(\&_cmd_stop_constant_read,\&_resp_stop_constant_read,@_);
}


sub _cmd_stop_constant_read
{
    my $self = shift;
    my(%p)=@_;
    
    $self->_makepacket(%p,
		       cmd => 0x26,
		       data => "",
		       );
}

sub _resp_stop_constant_read
{
    my $self = shift;
    my $pp = $self->_parsepacket(@_)
	or return undef;
    return $pp;
}


=head3 stop_all_constant_read

Stop all ongoing constant read operations, returning the reader to its
default mode.

=cut

sub stop_all_constant_read
{
    my $self = shift;
    
    if ($self->{_constant_read} && $self->_connected)
    {
	foreach my $node (keys %{$self->{_constant_read}})
	{
	    $self->stop_constant_read(node => $node);
	}
    }
    1;
}

sub _make_confwhich_ant
{
    my $self = shift;
    my($p)=@_;
    my %antflag;

    foreach my $a (grep { defined } 
		   ($p->{antenna1}||$p->{antenna}||MATRICS_ANT_1,
		    @$p{qw(antenna2 antenna3 antenna4)}))
    {
	$antflag{$a}=1;
    }
    
    return ($antflag{MATRICS_ANT_1()}?1:0,
	    $antflag{MATRICS_ANT_2()}?1:0,
	    $antflag{MATRICS_ANT_3()}?1:0,
	    $antflag{MATRICS_ANT_4()}?1:0,
	    );
}

sub _make_combine_antenna_bits
{
    my $self = shift;
    my($p)=@_;
    my %antbit = (
		  MATRICS_ANT_1() => 1,
		  MATRICS_ANT_2() => 2,
		  MATRICS_ANT_3() => 4,
		  MATRICS_ANT_4() => 8,
		  );

    if (!$p->{combine_antenna_bits})
    {
	my $cab = 0;
	if ($p->{combine_antennas})
	{
	    $cab |= $antbit{$_}
   	        foreach (@{$p->{combine_antennas}});
	}
	$p->{combine_antenna_bits}=chr($cab);
    }
    return ord($p->{combine_antenna_bits});
}


=head3 epc_readfullfield

Reads all tags in the field of the specified antenna.  Parameters and
return values are identical to I<readfullfield>.

=cut

sub epc_readfullfield
{
    my $self = shift;
    my @resp = $self->_do_something(\&_cmd_epc_readfullfield,
				    \&_resp_epc_readfullfield,
				    @_)
	or return undef;

    my $ret = shift(@resp);
    foreach my $r (@resp)
    {
	$ret->{numtags} += $r->{numtags};
	push(@{$ret->{tags}},@{$r->{tags}});
    }
    $ret;
}

sub _cmd_epc_readfullfield
{
    my $self = shift;
    my(%p)=@_;
    
    $self->_makepacket(%p,
		       cmd => 0x10,
		       data => pack("C",$p{antenna}),
		       );
}

sub _resp_epc_readfullfield
{
    my $self = shift;
    my $pp = $self->_parsepacket(@_)
	or return undef;
    my $dc = $pp->{data};
    (@$pp{qw(antenna numtags)}) = unpack("CC",substr($dc,0,2,""));
    $pp->{tags} = [$self->_epc_parsetags($pp->{numtags},$dc)];
    $pp;
}


=head3 epc_readfullfield_unique

Performs an I<epc_readfullfield>, then adds attributes to the hash
reference representing the I<unique> tags.  Pretty much the same as
I<readfullfield_unique>.

=cut

sub epc_readfullfield_unique
{
    my $self = shift;
    my $ret = $self->epc_readfullfield;

    @{$ret->{utags}} = uniq { tagcmp($a,$b) }
                       sort { tagcmp($a,$b) } 
                        @{$ret->{tags}};
    $ret->{unumtags}=scalar(@{$ret->{utags}});

    $ret;
}


=head3 epc_getparamblock

Get parameters for a particular reader and antenna using the EPC
style.  The only difference seems to be the way filters are returned,
and since filters are not yet implemented, this method is currently
functionally identical to I<getparamblock>, although it sends a
different command.  The parameters are identical.

=cut

sub epc_getparamblock
{
    my $self = shift;
    $self->_do_something(\&_cmd_getparamblock,\&_resp_getparamblock,@_);
}

sub _cmd_epc_getparamblock
{
    my $self = shift;
    my(%p)=@_;
    
    $self->_makepacket(%p,
		       cmd => 0x16,
		       data => pack("C",$p{antenna}),
		       );
}

sub _resp_epc_getparamblock
{
    my $self = shift;
    my $pp = $self->_parsepacket(@_)
	or return undef;
    
    @$pp{qw(power_level environment combine_antenna_bits protocol_speed filter_type reserved_bits filter_bits reserved_bits)} =
	unpack("CCCCCa2a8a*",$pp->{data});
    $pp;
}


=head3 epc_setparamblock

Set parameters for a particular reader and antenna using the EPC
style.  The only difference between this command and I<setparamblock>
seems to be the way filters are defined, and since filters are not yet
implemented, this method is currently functionally identical to
I<setparamblock>, although it sends a different command.  The
parameters are identical.

=cut

sub epc_setparamblock
{
    my $self = shift;
    $self->_do_something(\&_cmd_setparamblock,\&_resp_setparamblock,@_);
}

sub _cmd_epc_setparamblock
{
    my $self = shift;
    my(%p)=@_;

    $self->_makepacket(%p,
		       cmd => 0x15,
		       data => pack("CCCCCCCCCx3a8x16",
				    $self->_make_confwhich_ant(\%p),
				    $p{power_level}||0xff,
				    $p{environment}||0x00,
				    $self->_make_combine_antenna_bits(\%p),
				    $p{filter_type}||0x00,
				    $p{filter_bits}||"\0"x8,
				    )
		       );
}

sub _resp_epc_setparamblock
{
    my $self;
    my $pp = $self->_parsepacket(@_)
	or return undef;
}


=head3 epc_changeparamblock

Modifies parameters for a particular reader and antenna using the EPC
style.  This command is implemented in terms of I<epc_getparamblock>
and I<epc_setparamblock>.  The only difference between this command
and I<changeparamblock> seems to be the way filters are defined, and
since filters are not yet implemented, this method is currently
functionally identical to I<setparamblock>, although it sends
different commands.  The parameters are identical.

=cut

sub epc_changeparamblock
{
    my $self = shift;
    my(%p)=@_;

    croak "changeparam: The required parameter 'antenna' is missing.\n"
	unless ($p{antenna});
    my $curparam = $self->epc_getparamblock(@_)
	or return undef;
    return $self->epc_setparamblock(%$curparam, @_);
}

=head3 setnodeaddress

Sets the node number for the reader with the given serial number.
Takes a hash that can contain the following parameters:

=over 4

=item serialnum

The serial number of the reader unit, as a hexadecimal string.  For
example:

  serialnum => "00000000000003AF"

=item newnode

The new node number.  If not given, I<node> is used.

=item oldnode

The old node number that the message should be addressed to.  If not
given, the broadcast address C<0xFF> is used.

=back

=cut

sub setnodeaddress
{
    my $self = shift;
    my(%p)=@_;
    
    my $node = $p{oldnode}||0xFF;
    if ($p{oldnode}==0xFF or !$p{oldnode})
    {
	# No response to broadcast commands, just send it.
	my $cmd = _cmd_setnodeaddress($self, @_)
	    or return undef;
	$self->_sendpacket($cmd)
	    or die "Couldn't write command: $!\n";
	return { noresponse => 1 };
    }
    else
    {
	$self->_do_something(\&_cmd_setnodeaddress,\&_resp_setnodeaddress,@_);
    }
}

sub _cmd_setnodeaddress
{
    my $self = shift;
    my(%p)=@_;
    $self->_setdefaults(\%p);
    
    if (!$p{serialnum_bits})
    {
	defined($p{serialnum}) or return $self->error("Missing required parameter serialnum or serialnum_bits");
	$p{serialnum_bits} = hex2bin($p{serialnum});
    }
    $p{newnode} or $p{node} or return $self->error("Missing required parameter newnode or node");

    $self->_makepacket(%p,
		       node => $p{oldnode}||0xFF,
		       cmd => 0x12,
		       data => pack("Ca8",
				    $p{newnode}||$p{node},
				    $p{serialnum_bits},
				    ),
		       );
}

sub _resp_setnodeaddress
{
    my $self = shift;
    my $pp = $self->_parsepacket(@_)
	or return undef;
}


=head3 getreaderstatus

Gets the status of a reader, including firmware version.  Takes as
parameters a hash that can have the node and address.  Returns a hash
reference with the following attributes:

=over 4

=item serialnum

The serial number of the reader.

=item version

The firmware version number.

=back

Other attributes are not yet implemented.

=cut

sub getreaderstatus
{
    my $self = shift;
    $self->_do_something(\&_cmd_getreaderstatus,\&_resp_getreaderstatus,@_);
}

sub _cmd_getreaderstatus
{
    my $self = shift;
    my(%p)=@_;

    $self->_makepacket(%p,
		       cmd => 0x14,
		       );
}

sub _resp_getreaderstatus
{
    my $self = shift;
    my $pp = $self->_parsepacket(@_)
	or return undef;
    
    @$pp{qw(serialnum_bits version_major version_minor version_eng 
	    reset_flag combine_antenna_bits antenna_status_bits
	    last_error reserved)} =
		unpack("a8CCCCa4a4Ca11",$pp->{data});
    $pp->{version}=join(".",@$pp{qw(version_major version_minor version_eng)});
    $pp->{serialnum} = bin2hex($pp->{serialnum_bits});
    $pp;
}


=head3 getnodeaddress

Gets the node address of the reader with the given serial number.
Takes a hash containing the following parameters:

=over 4

=item serialnum

A hex string of the serial number of the router.

=back

Returns a hash reference with a I<node> parameter giving the node
number.

=cut

sub getnodeaddress
{
    my $self = shift;
    $self->_do_something(\&_cmd_getnodeaddress,\&_resp_getnodeaddress,@_);
}


sub _cmd_getnodeaddress
{
    my $self = shift;
    my(%p)=@_;

    if (!$p{serialnum_bits})
    {
	defined($p{serialnum}) or return $self->error("Missing required parameter serialnum or serialnum_bits");
	$p{serialnum_bits} = hex2bin($p{serialnum});
    }
    $self->_makepacket(%p,
		      node => 0xff,
		      cmd => 0x19,
		       data => pack("a8",
				    $p{serialnum_bits},
				    ),
		       );
}

sub _resp_getnodeaddress
{
    my $self = shift;
    my $pp = $self->_parsepacket(@_)
	or return undef;
}

# NOT FINISHED
our %baudnum = (
		230400 => 0,
		115200 => 1,
		57600 => 2,
		38400 => 3,
		19200 => 4,
		9600 => 5,
		);
		 

sub _cmd_setbaudrate
{
    my $self = shift;
    my(%p)=@_;
    
    if (!$p{baudrate_bits})
    {
	defined($p{baudrate}) or return $self->error("Missing required parameter baudrate");
	defined($p{baudrate_bits}=$baudnum{$p{baudrate}})
	    or return $self->error("Invalid baud rate.");
    }
    $self->_makepacket(%p,
		       cmd => 0x1D,
		       data => pack("C",$p{baudrate_bits}),
		       );
		      
}

sub _resp_setbaudrate
{
    my $self = shift;
    my $pp = $self->_parsepacket(@_)
	or return undef;
}

sub setbaudrate
{
    my $self = shift;

    $self->_do_something(\&_cmd_setbaudrate,\&_resp_setbaudrate,@_);
}


=head3 finish

Perform any cleanup tasks for the reader.  In particular, shut off any
constant reads that are currently running.

=cut

sub finish
{
    my $self = shift;
    $self->stop_all_constant_read()
	or warn "Couldn't stop all constant readers: $!\n";
}

# Utility Functions

sub sortcmp
{
    my $sub = shift;
    local($a,$b)=@_;
    $sub->();
}

sub hexdump
{
    my @a = split(//,$_[0]);
    sprintf "%02x " x scalar(@a),map { ord } @a;
}

sub uniq(&@)
{
    my($cmpsub, @list)=@_;
    my $last = shift @list
	or return ();
    my @ret =($last);
    foreach (@list)
    {
	push(@ret,$_)
	    unless sortcmp($cmpsub,$_,$last)==0;
	$last = $_;
    }
    @ret;
}

sub error
{
    my $self = shift;
    my($em,$ec)=@_;

    $self->{error}=$em;
    $self->{errcode}=defined($ec)?$ec:1;
    warn "Error: $em\n"
	if ($self->{debug});
    return undef;
}

# Convert a hex string to binary, LSB first
sub hex2bin
{
    my $hex = $_[0];
    $hex =~ tr/0-9a-fA-F//cd;
    pack("C*",map { hex } reverse unpack("a2"x(length($hex)/2),$hex));
}

sub bin2hex
{
    my @a = split(//,$_[0]);
    sprintf "%02x" x scalar(@a), reverse map {ord} @a;
}

=head1 SEE ALSO

L<RFID::Matrics::Reader::Serial>, L<RFID::Matrics::Reader::TCP>, L<RFID::Matrics::Tag>.

=head1 AUTHOR

Scott Gifford <gifford@umich.edu>, <sgifford@suspectclass.com>

Copyright (C) 2004 The Regents of the University of Michigan.

See the file LICENSE included with the distribution for license
information.

=cut

1;
