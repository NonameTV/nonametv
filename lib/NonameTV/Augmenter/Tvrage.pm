package NonameTV::Augmenter::Tvrage;

use strict;
use warnings;

use Data::Dumper;
use WebService::TVRage::EpisodeListRequest;
use WebService::TVRage::ShowSearchRequest;
use utf8;

use NonameTV qw/norm normUtf8 AddCategory/;
use NonameTV::Augmenter::Base;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w d/;

use base 'NonameTV::Augmenter::Base';


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    #my %opt = (quiet => 0, debug => 4, verbose => 3);
    #Debug::Simple::debuglevels(\%opt);

    return $self;
}

sub FillHash( $$$$ ) {
  my( $self, $resultref, $series, $episode )=@_;
  
  print Dumper( $series, $episode );
  $resultref->{subtitle} = $episode->getTitle();
  $resultref->{production_date} = $episode->getAirDate();
  $resultref->{url} = $episode->getWebLink();
  print Dumper( $resultref );
}

sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;
  
  print Dumper( $ceref );
  print Dumper( $ruleref );
  
  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';
  
  if( $ruleref->{matchby} eq 'episodeseason' ) {
    # match by episode and season
        
        if( defined $ceref->{episode} ){
      my( $season, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
      if( (defined $episode) and (defined $season) ){
        $episode += 1;
        $season += 1;
        
        print Dumper( $episode );

        my $series;
        my $episodes;
        #if( defined( $ruleref->{remoteref} ) ) {
          #my $searchResults = $self->{tvrage}->search($ceref->{title});
          #$series = $searchResults->getShow($ceref->{title});
          $episodes = WebService::TVRage::EpisodeListRequest->new( 'episodeID' => $ruleref->{remoteref} );
          my $episodeList = $episodes->getEpisodeList();
        #} else {
        #  my $tvrage = WebService::TVRage::ShowSearchRequest->new();
        #  my $searchResults = $tvrage->search( $ceref->{title} );
        #  $series = $searchResults->getShow( $ceref->{title} );
        #  $episodes = WebService::TVRage::EpisodeListRequest->new( 'episodeID' => $series->getShowID() );
        #  my $episodeList = $episodes->getEpisodeList();
        #  print Dumper( $series, $episodeList );
        #}
        
        #if( (defined $series)){
            # Set the title right, even if no season nor episode is found.
            # This does so there is not any diffrences in title between
            # a series with episode of 100+ when there's only 20 episodes of
            # the season, like Simpsons. Simpsons becomes The Simpsons if seriesname
            # is found.
            #$resultref->{title} = normUtf8( norm( $series->{SeriesName} ) );
            
            # Find season and episode
            if(($season ne "") and ($episode ne "")) {
                my $episode2 = $episodeList->getEpisode($season,$episode);

            if( defined( $episode2 ) ) {
                $self->FillHash( $resultref, $series, $episode2 );
            } else {
                w( "no episode " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
            }
          }
        #}
      }
    }
  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
  }
  return( $resultref, $result );
}

1;
