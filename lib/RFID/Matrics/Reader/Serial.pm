package RFID::Matrics::Reader::Serial;
use RFID::Matrics::Reader; $VERSION=$RFID::Matrics::Reader::VERSION;

# Written by Scott Gifford <gifford@umich.edu>
# Copyright (C) 2004 The Regents of the University of Michigan.
# See the file LICENSE included with the distribution for license
# information.

=head1 NAME

RFID::Matrics::Reader::Serial - Implement L<RFID::Matrics::Reader|RFID::Matrics::Reader> over a serial link

=head1 SYNOPSIS

This class takes a serial port object and implements the Matrics RFID
protocol over it.  The serial port object should be compatible with
L<Win32::SerialPort>; the Unix equivalent is L<Device::SerialPort>.
You are responsible for creating the serial port object.

An example:

    use Win32::Serialport;
    use RFID::Matrics::Reader::Serial;

    $com = Win32::SerialPort->new($opt{c})
	or die "Couldn't open COM port '$opt{c}': $^E\n";

    my $reader = 
      RFID::Matrics::Reader::Serial->new(comport => $com,
				         node => 4,
					 antenna => MATRICS_ANT_1);
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
L<RFID::Matrics::Reader|RFID::Matrics::Reader>, and implements the
underlying setup, reading, and writing functions.

=cut

use RFID::Matrics::Reader qw(:ant);
our @ISA = qw(RFID::Matrics::Reader Exporter);
our @EXPORT_OK = @RFID::Matrics::Reader::EXPORT_OK;
our %EXPORT_TAGS = %RFID::Matrics::Reader::EXPORT_TAGS;

use constant BAUDRATE => 230400;
use constant DATABITS => 8;
use constant STOPBITS => 1;
use constant PARITY => 'none';
use constant HANDSHAKE => 'none';
use constant DEFAULT_TIMEOUT => 2000; #ms

=head2 Constructor

=head3 new

This creates a new L<Matrics::Reader::Serial|Matrics::Reader::Serial>
object.  In addition to the parameters for the
L<RFID::Matrics::Reader> constructor, it takes the following
parameters:

=over 4

=item comport

Required parameter.  A
L<Win32::SerialPort|Win32::SerialPort>-compatible object over which
the serial communication should take place.

=item baudrate

Optional parameter.  The baud rate at which we should communicat over
the serial port.  The default is 230400, which is the default speed of
the RDR-001.

=back

=cut

sub new
{
    my $class = shift;
    my(%p)=@_;
    
    my $self = {};

    $self->{com} = $p{comport}
        or die "Matrics::Reader::new requires argument 'com'\n";

    $self->{com}->databits(DATABITS);
    $self->{com}->stopbits(STOPBITS);
    $self->{com}->parity(PARITY);
    $self->{com}->handshake(HANDSHAKE);

    my $baudrate = $p{baudrate}||BAUDRATE;
    if ($baudrate > 115200 && (ref($self->{com}) eq 'Win32::SerialPort'))
    {
	# This is a hack to work around an annoying bug in Win32::CommPort.
	$self->{com}->baudrate(115200);
	$self->{com}->{_N_BAUD}=$baudrate;
    }
    else
    {
	$self->{com}->baudrate($baudrate);
    }

    $self->{com}->write_settings 
	or die "No settings: $!\n";
    $self->{com}->user_msg(1);
    $self->{com}->error_msg(1);

    bless $self,$class;
    
    $self->_init(%p);
    $self->{timeout} = DEFAULT_TIMEOUT
	unless ($self->{timeout});
    $self;
}

sub _readbytes
{
    my $self = shift;
    my($bytesleft)=@_;
    my $data = "";

    $self->{com}->read_const_time($self->{timeout});
    my $start = time;
    while($bytesleft > 0)
    {
	if ( (time - $start) > $self->{timeout})
	{
	    die "Read timeout.\n";
	}

	my($rb,$moredata)=$self->{com}->read($bytesleft);
	$bytesleft -= $rb;
	$data .= $moredata;
    }
    $data;
}

sub _writebytes
{
    my $self = shift;
    my($data)=@_;

    my $bytesleft = length($data);
    $self->{com}->write_const_time($self->{timeout});
    my $start = time;
    while ($bytesleft > 0)
    {
	if ( (time - $start) > $self->{timeout})
	{
	    die "Read timeout.\n";
	}
	my $wb = $self->{com}->write($data);
	substr($data,0,$wb,"");
	$bytesleft -= $wb;
    }
    1;
}

sub _connected
{
    return $self->{com};
}

=head1 SEE ALSO

L<RFID::Matrics::Reader>, L<RFID::Matrics::Reader::TCP>,
L<Win32::SerialPort>, L<Device::SerialPort>.

=head1 AUTHOR

Scott Gifford <gifford@umich.edu>, <sgifford@suspectclass.com>

Copyright (C) 2004 The Regents of the University of Michigan.

See the file LICENSE included with the distribution for license
information.

=cut

1;
