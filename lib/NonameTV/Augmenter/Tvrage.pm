package NonameTV::Augmenter::Tvrage;

use strict;
use warnings;

use Data::Dumper;
use TVRage::API;
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
  
  #print Dumper( $series, $episode );
  
  # Series info
  #my @genres = ();
  #foreach my $genre ( $series->getGenres() ){
  #   my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "Tvrage", $genre );
  #   # set category, unless category is already set!
  #   AddCategory( $resultref, undef, $categ );
  #}
  
  # Standard info (episode)
  $resultref->{subtitle} = normUtf8( norm( $episode->{title} ) );
  $resultref->{production_date} = normUtf8( norm( $episode->{airdate} ) );
  $resultref->{url} = normUtf8( norm( $episode->{link} ) );
  
  $resultref->{program_type} = 'series';
  
  #print Dumper( $resultref );
}

sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;
  
  #print Dumper( $ceref );
  #print Dumper( $ruleref );
  
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
        
        #print Dumper( $episode );

        my $series;
        my $episodes;
        my $episodeList;
        my $tvrage;
        my $searchResults;
        if( defined( $ruleref->{remoteref} ) and ( $ruleref->{remoteref} ne "" ) ) {
          
          # Get moar info via ShowInfo (genres and name)
          $tvrage = TVRage::API->new();
          $series = $tvrage->showInfo( $ruleref->{remoteref} );
          #print Dumper( $series );
        } else {
          die("You need to input series id into remoteref, until this is fixed.");
        }
        
        #if( (defined $series)){
            # Set the title right, even if no season nor episode is found.
            # This does so there is not any diffrences in title between
            # a series with episode of 100+ when there's only 20 episodes of
            # the season, like Simpsons. Simpsons becomes The Simpsons if seriesname
            # is found.
            $resultref->{title} = normUtf8( norm( $series->{showname} ) );
            
            # Find season and episode
            if(($season ne "") and ($episode ne "")) {
                my $episode2 = $tvrage->getEpisode( $ruleref->{remoteref}, $season, $episode );

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
