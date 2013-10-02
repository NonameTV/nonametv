#!/usr/bin/perl

use strict;
use utf8;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;
#use DateTime;
#use Encode;

use NonameTV::Factory qw/CreateAugmenter CreateDataStore/;

my $ds = CreateDataStore( );

my $augmenter = CreateAugmenter( 'Tmdb3', $ds, 'de' );

#my $ce = {
#	'title' => 'Blues Brothers',
#	'production_date' => '1980-01-01',
#	'directors' => 'John Landis',
#};

my $ce = {
	'title' => 'Mala',
	'production_date' => '2013-01-01',
	'directors' => 'Israel Adrián Caetano', # <- this is an alternate name of the director
};

my $rule = {
	'augmenter' => 'Tmdb3',
	'matchby' => 'title',
};

my ( $newprogram, $result ) = $augmenter->AugmentProgram( $ce, $rule );

print Dumper( \$result, \$newprogram );
