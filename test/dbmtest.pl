#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use NonameTV::Config qw/ReadConfig/;
use DateTime;
use Encode;


use WebService::TVRage;

my $tvrage = WebService::TVRage->new();
my $series = $tvrage->showInfo( 15615, "chuck" );

my $series2 = $tvrage->getEpisode( 15615, 1,1 );

1;