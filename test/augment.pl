#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use DateTime;
use Encode;

use NonameTV::Augmenter;
use NonameTV::Factory qw/CreateDataStore/;

my $ds = CreateDataStore( );

my $dt = DateTime->now( time_zone => 'UTC' );
#$dt->add( days => 0 );
$dt->subtract( days => 1);

#my $batchid = 'kanal9.se_' . $dt->year .'-'.$dt->week;
my $batchid = "discoverychannel.se_all";
printf( "augmenting %s...\n", $batchid );

my $augmenter = NonameTV::Augmenter->new( $ds );

$augmenter->AugmentBatch( $batchid );
