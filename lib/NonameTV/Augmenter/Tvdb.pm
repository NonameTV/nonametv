package NonameTV::Augmenter::Tvdb;

use strict;
use warnings;

use Data::Dumper;
use Encode;
use TVDB::API;

use NonameTV qw/norm/;
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

  $resultref->{subtitle} = decode( 'utf-8', $episode->{EpisodeName} );

  if( defined( $episode->{Overview} ) ) {
    $resultref->{description} = decode( 'utf-8', $episode->{Overview} ) . "\nQuelle: Tvdb";
  }

  $resultref->{production_date} = $episode->{FirstAired};

  # FIXME link to the correct language instead of hardcoding german (14)
  $resultref->{url} = sprintf(
    'http://thetvdb.com/?tab=episode&seriesid=%d&seasonid=%d&id=%d&lid=%d',
    $episode->{seriesid}, $episode->{seasonid}, $episodeid, 14
  );

  my @actors = split( '\|', decode( 'utf-8', $series->{Actors} ) );
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

  $resultref->{program_type} = 'series';  
}


sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';

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
            $resultref = undef;
          }
        }
      } else {
        $resultref = undef;
      }
    } else {
      $resultref = undef;
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
      } else {
        $resultref = undef;
      }
    } else {
      $resultref = undef;
    }

  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
  }

  return( $resultref, $result );
}


1;
