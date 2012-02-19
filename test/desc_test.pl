#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

my $desc = "1962, 160 Mins, B/W, Dir: Stanley Kubrick, Act: James Mason,Shelley Winters,Peter Sellers,Sue Lyon, Sub: ARB, DAN, DUT, ENG, GRE, HEB, NOR, SWE";
if( $desc =~ /Dir:/ ) {
	print("MATCH\n");
	my ( $dir, $actor ) = ( $desc =~ /Dir:\s+([A-Z].+?),\s+Act:\s+([A-Z].+?),\s+Sub/ );
	my @directors = split( /\s*,\s*/, $dir );
  my $dire = join( ", ", grep( /\S/, @directors ) );
	my @actors = split( /\s*,\s*/, $actor );
  my $acte = join( ", ", grep( /\S/, @actors ) );
	print Dumper($desc, $dir, $dire, @directors, $actor, $acte, @actors);
}