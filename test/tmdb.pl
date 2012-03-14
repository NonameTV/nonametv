#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use NonameTV::Config qw/ReadConfig/;
use DateTime;
use Encode;

use TMDB;

my $tmdb = TMDB->new( { api_key => '281fdc1b73eb2366f60f1b2b33992899' } );

# Search for a movie
my @results = $tmdb->search->movie('Snatch');
foreach my $result (@results) {
	print Dumper($result);
	print Dumper($result->{id});
}

# Movie Object
#my $movie = $tmdb->movie(73723);

# Movie Data (as returned by the API)
    use Data::Dumper qw(Dumper);
    #print Dumper($movie);
    #print Dumper $movie->{_info}{rating};
    #print Dumper $movie->cast;
    #print Dumper $movie->crew;
    #print Dumper $movie->images;


1;