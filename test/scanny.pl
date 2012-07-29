#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use DateTime;
use Encode;

my $test = "Trapped: Hurricane Hospital";
if( $test =~ /^.*\: .*$/ ) {
	print("HEJ\n");
}