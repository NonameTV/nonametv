package NonameTV::Augmenter::Tvdb;

use strict;
use warnings;

use TVDB::API;

use NonameTV qw/norm AddCategory/;
use NonameTV::Augmenter::Base;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w/;

use base 'NonameTV::Augmenter::Base';


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{ApiKey} )   or die "You must specify ApiKey";
    defined( $self->{Language} ) or die "You must specify Language";

    # need config for main content cache path
    my $conf = ReadConfig( );

    my $cachefile = $conf->{ContentCachePath} . '/' . $self->{Type} . '/tvdb.db';
    my $bannerdir = $conf->{ContentCachePath} . '/' . $self->{Type} . '/banner';

    $self->{tvdb} = TVDB::API::new({ apikey    => $self->{ApiKey},
                                     lang      => $self->{Language},
                                     cache     => $cachefile,
                                     banner    => $bannerdir,
                                  });
    if( defined $self->{tvdb}->{cache}->{Update} ) {
      $self->{tvdb}->getUpdates( 'guess' );
    }

    my $langhash = $self->{tvdb}->getAvailableLanguages( );
    $self->{LanguageNo} = $langhash->{$self->{Language}}->{id};

    # only consider Ratings with 10 or more votes by default
    if( !defined( $self->{MinRatingCount} ) ){
      $self->{MinRatingCount} = 10;
    }

    my $opt = { quiet => 1 };
    Debug::Simple::debuglevels($opt);

    return $self;
}


sub FillHash( $$$$ ) {
  my( $self, $resultref, $series, $episode )=@_;

  return if( !defined $episode );

  my $episodeid = $series->{Seasons}[$episode->{SeasonNumber}][$episode->{EpisodeNumber}];

  $resultref->{title} = $series->{SeriesName};

  $resultref->{episode} = ($episode->{SeasonNumber} - 1) . ' . ' . ($episode->{EpisodeNumber} - 1) . ' .';

  $resultref->{subtitle} = $episode->{EpisodeName};

# TODO skip the Overview for now, it falls back to english in a way we can not detect
#  if( defined( $episode->{Overview} ) ) {
#    $resultref->{description} = $episode->{Overview} . "\nQuelle: Tvdb";
#  }

  if( $episode->{FirstAired} ) {
    $resultref->{production_date} = $episode->{FirstAired};
  }

  $resultref->{url} = sprintf(
    'http://thetvdb.com/?tab=episode&seriesid=%d&seasonid=%d&id=%d&lid=%d',
    $episode->{seriesid}, $episode->{seasonid}, $episodeid, $self->{LanguageNo}
  );

  my @actors = ();
  # TODO only add series actors if its not a special
  if( $series->{Actors} ) {
    push( @actors, split( '\|', $series->{Actors} ) );
  }
  if( $episode->{GuestStars} ) {
    push( @actors, split( '\|', $episode->{GuestStars} ) );
  }
  foreach( @actors ){
    $_ = norm( $_ );
    if( $_ eq '' ){
      $_ = undef;
    }
  }
  @actors = grep{ defined } @actors;
  if( @actors ) {
    # replace programme's actors
    $resultref->{actors} = join( ', ', @actors );
  } else {
    # remove existing actors from programme
    $resultref->{actors} = undef;
  }

  #more fields on episodes are, Director, Writer

  $resultref->{program_type} = 'series';  

  # Genre
  if( $series->{Genre} ){
    # notice, Genre is ordered by some internal order, not by importance!
    my @genres = split( '\|', $series->{Genre} );
    foreach( @genres ){
      $_ = norm( $_ );
      if( $_ eq '' ){
        $_ = undef;
      }
    }
    @genres = grep{ defined } @genres;
    foreach my $genre ( @genres ){
      my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "Tvdb", $genre );
      # set category, unless category is already set!
      AddCategory( $resultref, undef, $categ );
    }
  }

  # Use episode rating if there are more then MinRatingCount ratings for the episode. If the
  # episode does not have enough ratings consider using the series rating instead (if that has enough ratings)
  # if not rating qualifies leave it away.
  # the Rating at Tvdb is 1-10, turn that into 0-9 as xmltv ratings always must start at 0
  if( $episode->{RatingCount} >= $self->{MinRatingCount} ){
    $resultref->{'star_rating'} = $episode->{Rating}-1 . ' / 9';
  } elsif( $series->{RatingCount} >= $self->{MinRatingCount} ){
    $resultref->{'star_rating'} = $series->{Rating}-1 . ' / 9';
  }
}


sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';

  if( $ceref->{title} eq 'SOKO Leipzig' ){
    # broken dataset on Tvdb
    return( undef, 'known bad data for SOKO Leipzig, skipping' );
  }

  if( $ruleref->{matchby} eq 'episodeabs' ) {
    # match by absolute episode number from program hash

    if( defined $ceref->{episode} ){
      my( $episodeabs )=( $ceref->{episode} =~ m|^\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
      if( defined $episodeabs ){
        $episodeabs += 1;

        my $series;
        if( defined( $ruleref->{remoteref} ) ) {
          my $seriesname = $self->{tvdb}->getSeriesName( $ruleref->{remoteref} );
          $series = $self->{tvdb}->getSeries( $seriesname );
        } else {
          $series = $self->{tvdb}->getSeries( $ceref->{title} );
        }
        if( defined $series ){
          my $episode = $self->{tvdb}->getEpisodeAbs( $series->{SeriesName}, $episodeabs );

          if( defined( $episode ) ) {
            $self->FillHash( $resultref, $series, $episode );
          } else {
            w( "no absolute episode " . $episodeabs . " found for '" . $ceref->{title} . "'" );
          }
        }
      }
    }
  }elsif( $ruleref->{matchby} eq 'episodetitle' ) {
    # match by episode title from program hash

    if( defined( $ceref->{subtitle} ) ) {
      my $series;
      if( defined( $ruleref->{remoteref} ) ) {
        my $seriesname = $self->{tvdb}->getSeriesName( $ruleref->{remoteref} );
        $series = $self->{tvdb}->getSeries( $seriesname );
      } else {
        $series = $self->{tvdb}->getSeries( $ceref->{title} );
      }

      my $episodetitle = $ceref->{subtitle};
      $episodetitle =~ s|,\s+Teil\s+(\d+)$| ($1)|;
      $episodetitle =~ s|\s+-\s+Teil\s+(\d+)$| ($1)|;
      $episodetitle =~ s|\s+\(Teil\s+(\d+)\)$| ($1)|;
      $episodetitle =~ s|\s+-\s+(\d+)\.\s+Teil$| ($1)|;

      my $episode = $self->{tvdb}->getEpisodeByName( $series->{SeriesName}, $episodetitle );
      if( defined( $episode ) ) {
        $self->FillHash( $resultref, $series, $episode );
      }
    }

  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
  }

  if( !scalar keys %{$resultref} ){
    $resultref = undef;
  } else {
  }

  return( $resultref, $result );
}


1;
