package RFID::Matrics::Tag;
use RFID::Matrics::Reader; $VERSION=$RFID::Matrics::Reader::VERSION;

# Written by Scott Gifford <gifford@umich.edu>
# Copyright (C) 2004 The Regents of the University of Michigan.
# See the file LICENSE included with the distribution for license
# information.

=head1 NAME

RFID::Matrics::Tag - Object representing a single tag read by a Matrics reader.

=head1 SYNOPSIS

These objects are usually returned by an L<RFID::Matrics::Reader>
object:

    use RFID::Matrics::Tag qw(tag2txt);

    my $rff = RFID::Matrics::Reader->new->readfullfield(antenna => MATRICS_ANT_1);
    foreach my $tag (@{$pp->{utags}})
    {
	print "I see tag $tag->{id}\n";
    }

But you can create your own if you want:

    my $tag = RFID::Matrics::Tag->new(type => MATRICS_TAGTYPE_EPC,
				      id = "c80507a8009609de");
    print "Tag is $tag->{id}\n";

=head1 DESCRIPTION

=cut

use strict;

use Exporter;
use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS);
@ISA=qw(Exporter);
@EXPORT_OK=qw(tagcmp tag2txt);
%EXPORT_TAGS=(tagtypes => [ qw(MATRICS_TAGTYPE_EPC MATRICS_TAGTYPE_MATRICS MATRICS_TAGTYPE_OLDMATRICS)]);
Exporter::export_ok_tags('tagtypes');

=head2 Constants

=head3 Tag Type Constants

The constants C<MATRICS_TAGTYPE_EPC>, C<MATRICS_TAGTYPE_MATRICS>, and
C<MATRICS_TAGTYPE_OLDMATRICS> are recognized tag types.  They can be
imported into your namespace with the C<:tagtypes> tag.

=cut

use constant MATRICS_TAGTYPE_EPC => 0;
use constant MATRICS_TAGTYPE_MATRICS => 1;
use constant MATRICS_TAGTYPE_OLDMATRICS => 2;

sub tagcmp($$);

=head2 Constructor

=head3 new

Creates a new I<RFID::Matrics::Tag> object.  Takes a hash containing
various settings as its parameters:

=over 4

=item id_bits

A binary string containing the tag's ID.  This is the representation
used natively by the reader; it will be automatically generated if it
is not given but I<id> is.

=item id

A hex string containing the tag's ID.  This is the human-readable
representation; it will be automatically generated if it is not given
but I<id_bits> is.

=item type

The type of tag this is.  See the I<Constants> section of this page
for recognized tag types.

=back

=cut

sub new
{
    my $class = shift;
    my(%p)=@_;
    my $self = {};

    $self->{id_bits} = $p{id_bits};
    $self->{id} = $p{id};
    if ($self->{id_bits} && $self->{id})
    {
	# Do nothing.
    }
    elsif ($self->{id_bits})
    {
	$self->{id} = tag2txt($self->{id_bits});
    }
    elsif ($self->{id})
    {
	$self->{id_bits} = txt2tag($self->{id});
    }
    
    $self->{len}=length($self->{id_bits});
    $self->{type} = $p{type};

    bless $self,$class;
}

=head2 Utility Functions

=head3 tagcmp

A comparison function for C<sort>.  Compares the ID numbers of two
tags, and returns -1 if the first ID is lower, 0 if they are the same,
or 1 if the first ID is higher.

=cut

sub tagcmp($$)
{
    return $_[0]->{id} cmp $_[1]->{id};
}

sub tag2txt
{
    my @a = split(//,$_[0]);
    sprintf "%02x" x scalar(@a), reverse map {ord} @a;
}

sub txt2tag
{
    my $hex = $_[0];
    $hex =~ tr/0-9a-fA-F//cd;
    pack("C*",map { hex } reverse unpack("a2"x(length($hex)/2),$hex));
}

=head1 SEE ALSO

L<RFID::Matrics::Reader>.

=head1 AUTHOR

Scott Gifford <gifford@umich.edu>, <sgifford@suspectclass.com>

Copyright (C) 2004 The Regents of the University of Michigan.

See the file LICENSE included with the distribution for license
information.

=cut

1;

