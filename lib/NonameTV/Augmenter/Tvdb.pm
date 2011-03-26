package NonameTV::Augmenter::Tvdb;

use strict;

use Data::Dumper;
use TVDB::API;

use NonameTV::Augmenter::Base;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w/;

use base 'NonameTV::Augmenter::Base';


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

#    print Dumper( $self );

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
#    print Dumper( $self->{tvdb}->{cache}->{Update} ); #->{lastupdated};
#    $self->{tvdb}->getUpdates( 'all' );
    $self->{tvdb}->getUpdates( 'guess' );

    return $self;
}


sub FillHash( $$$$ ) {
  my( $self, $resultref, $series, $episode )=@_;

  return if( !defined $episode );

  my $episodeid = $series->{Seasons}[$episode->{SeasonNumber}][$episode->{EpisodeNumber}];

#  print Dumper( $series, $episodeid, $episode );

  $resultref->{title} = $series->{SeriesName};

  $resultref->{episode} = ($episode->{SeasonNumber} - 1) . ' . ' . ($episode->{EpisodeNumber} - 1) . ' .';

  $resultref->{subtitle} = $episode->{EpisodeName};

  if( defined( $episode->{Overview} ) ) {
    $resultref->{description} = $episode->{Overview} . "\nQuelle: Tvdb";
  }

  $resultref->{production_date} = $episode->{FirstAired};

  # FIXME link to the correct language instead of hardcoding german (14)
  $resultref->{url} = sprintf(
    'http://thetvdb.com/?tab=episode&seriesid=%d&seasonid=%d&id=%d&lid=%d',
    $episode->{seriesid}, $episode->{seasonid}, $episodeid, 14
  );

  # FIXME split can strip the leading empties, but I don't know how
  my @actors = split( '\|', $series->{Actors} );
  shift( @actors );
  $resultref->{actors} = join( ', ', @actors );

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
    my $series;
    if( defined( $ruleref->{remoteref} ) ) {
      my $seriesname = $self->{tvdb}->getSeriesName( $ruleref->{remoteref} );
      $series = $self->{tvdb}->getSeries( $seriesname );
    } else {
      $series = $self->{tvdb}->getSeries( $ceref->{title} );
    }
    my( $episodeabs )=( $ceref->{episode} =~ m|\.\s*(\d+)/*\d*\s*\.| );
    $episodeabs += 1;
    my $episode = $self->{tvdb}->getEpisodeAbs( $series->{SeriesName}, $episodeabs );

    $self->FillHash( $resultref, $series, $episode );

  }elsif( $ruleref->{matchby} eq 'episodetitle' ) {
    # match by episode title from program hash
    my $series;
    if( defined( $ruleref->{remoteref} ) ) {
      my $seriesname = $self->{tvdb}->getSeriesName( $ruleref->{remoteref} );
      $series = $self->{tvdb}->getSeries( $seriesname );
    } else {
      $series = $self->{tvdb}->getSeries( $ceref->{title} );
#      print "getSeries: " . Dumper( $ceref->{title}, $series );
    }
    my $episode = $self->{tvdb}->getEpisodeByName( $series->{SeriesName}, $ceref->{subtitle} );
    if( defined( $episode ) ) {
      $self->FillHash( $resultref, $series, $episode );
    } else {
      $resultref = undef;
    }

  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
  }

  return( $resultref, $result );
}


1;
