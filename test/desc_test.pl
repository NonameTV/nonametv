#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

my $text = "Draga Genevieve 3, dokumentarna serija (5/13)";
 # (episodenum/of_episods)
  	my ( $ep2, $eps2 ) = ($text =~ /\((\d+)\/(\d+)\)/ );
  	my $episode = sprintf( " . %d/%d . ", $ep2-1, $eps2 ) if defined $eps2;
  	$text =~ s/\(.*\)//g;
#    $text = norm($text);
print("$text\n");