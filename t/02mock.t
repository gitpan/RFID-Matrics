#!/usr/bin/perl -w

use strict;

use Test::More tests => 24;
use RFID::Matrics::Reader::Test;
use RFID::Matrics::Reader qw(:ant);
use RFID::Matrics::Tag qw(tagcmp);

my $obj = RFID::Matrics::Reader::Test->new(node => 4,
					   antenna => MATRICS_ANT_1,
					   );
isa_ok($obj,'RFID::Matrics::Reader::Test');
isa_ok($obj,'RFID::Matrics::Reader');
    
# Basic tests
my $t;
ok($t = $obj->getparamblock);
ok($t->{power_level}==0xff);
ok($t->{environment}==0x00);
is($t->{combine_antenna_bits},"\0");

ok($obj->setparamblock(power_level => 0xff,
		       environment => 0x04,
		       ));

ok($t = $obj->getnodeaddress(serialnum => "00000000000003AF"));
ok($t->{node} == 4);

ok($t = $obj->getreaderstatus());
is($t->{version},'2.1.2');

# A more complicated test
ok($obj->changeparamblock(power_level => 0xff,
			  environment => 0x04,
			  ));
# Generate some tags
my @tags = map { RFID::Matrics::Tag->new(id => $_) } 
               qw(c80507a8009609de
		  000000000176c402
		  000000000176c002
		  000000000176bc02
		  000000000176bc02);

isa_ok($_,'RFID::Matrics::Tag','Tag isa')
    foreach @tags;

# Tests with reading mock tags
ok($t = $obj->readfullfield);
ok($t->{numtags} == 5);

ok(tagcmp($tags[$_],$t->{tags}[$_])==0,'Tag compare')
    foreach (0..$#tags);
