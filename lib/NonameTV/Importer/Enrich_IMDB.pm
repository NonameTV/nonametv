package NonameTV::Importer::Enrich_IMDB;

use strict;
use warnings;

=pod

Module that fetches the data from IMDB
and updates missing information for the programme.

=cut

use DateTime;
use IMDB::Film;

use NonameTV::Log qw/d p progress w error/;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/EnrichIMDB/;
}
our @EXPORT_OK;


sub EnrichIMDB {
  my( $title , $ce ) = @_;

  #$flags->{IMDB_EXACT_TITLE} = 1;

return;

print "EnrichIMDB $title\n";
  my $film = new IMDB::Film( crit => $title );
  if($film->status) {

#    print "\n--------------------------\n";

#    print "Title: ".$film->title()."\n";

#    print "Kind: ".$film->kind()."\n";

#    print "Year: ".$film->year()."\n";

#    print "Connections: ".$film->connections()."\n";

#    print "Companies: ".$film->full_companies()."\n";

#    print "Company: ".$film->company()."\n";

#    foreach my $episode ( @{$film->episodes()} ){
#      print "Episode: $episode->{id} $episode->{title} $episode->{season} $episode->{episode} $episode->{date} $episode->{plot}\n";
#    }

#    foreach my $episodeof ( @{$film->episodeof()} ){
#      print "Episode: $episodeof->{id} $episodeof->{title} $episodeof->{year}\n";
#    }

#    print "Cover: ".$film->cover()."\n";

    foreach my $director ( @{$film->directors()} ){
#      print "Director: $director->{id} $director->{name}\n";
    }

    foreach my $writer ( @{$film->writers()} ){
#      print "Writer: $writer->{id} $writer->{name}\n";
    }

    foreach my $genre ( @{$film->genres()} ){
#      print "Genre: $genre\n";
    }

#    print "Tagline: ".$film->tagline()."\n";

#    print "Plot: ".$film->plot()."\n";

#    print "Storyline: ".$film->storyline()."\n";

#    print "Rating: ".$film->rating()."\n";

    foreach my $actor ( @{$film->cast()} ){
#      print "Actor: $actor->{id} $actor->{name} $actor->{role}\n";
    }

#    print "Duration: ".$film->duration()."\n";

#    print "Country: ".$film->country()."\n";

#    print "Langguage: ".$film->language()."\n";

#    print "Aka: ".$film->also_known_as()."\n";

#    print "Trivia: ".$film->trivia()."\n";

#    print "Goofs: ".$film->goofs()."\n";

#    print "Awards: ".$film->awards()."\n";

#    print "MPAA: ".$film->mpaa_info()."\n";

#    print "Aspect: ".$film->aspect_ratio()."\n";

#    print "Summary: ".$film->summary()."\n";

#    print "Certifications: ".$film->certifications()."\n";

#    print "Full plot: ".$film->full_plot()."\n";

    foreach my $site ( @{$film->official_sites()} ){
#      print "Site: $site->{title} $site->{url}\n";
    }

    foreach my $releasedate ( @{$film->release_dates()} ){
#      print "Country: $releasedate->{country} $releasedate->{date} $releasedate->{info}\n";
    }

    print "--------------------------\n";

    if( ( $film->title() eq $title ) ){
print "OK FOR UPDATE !!!\n";

      $ce->{title} = $title;

      $ce->{description} = $film->full_plot() if( ! $ce->{description} );

      $ce->{rating} = $film->mpaa_info() if( ! $ce->{rating} );
    }
  }

  return;
}

1;
