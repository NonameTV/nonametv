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
  my( $self, $resultref, $series, $episode, $ceref )=@_;
  
  #print Dumper( $series, $episode );
  
  # Genre
  my @genres = ();
  foreach my $genre ( $series->{genres}->{genre} ){
      if(ref($genre) eq 'DBM::Deep::Array'){
          foreach my $genre2 ( @$genre ){
              # Genre add (if array)
              my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "Tvrage", $genre2 );
              push @genres, $categ if defined $categ;
          }
      } else {
          # Genre add (if not array)
          my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "Tvrage", $genre );
          push @genres, $categ if defined $categ;
      }
  }

  if( scalar( @genres ) > 0 ) {
    my $cat = join "/", @genres;
    AddCategory( $resultref, undef, $cat );
  }
  
  # Standard info (episode)
  $resultref->{subtitle} = normUtf8( norm( $episode->{title} ) );
  $resultref->{production_date} = normUtf8( norm( $episode->{airdate} ) );
  $resultref->{url} = normUtf8( norm( $episode->{link} ) );

  $resultref->{extra_id} = $series->{showid};
  $resultref->{extra_id_type} = "tvrage";
  
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

            # Find season and episode
            if(($season ne "") and ($episode ne "")) {
                my $episode2 = $tvrage->getEpisode( $ruleref->{remoteref}, $season, $episode );

            if( defined( $episode2 ) ) {
                $self->FillHash( $resultref, $series, $episode2, $ceref );
            } else {
                w( "no episode " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
            }
          }
      }
    }
  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
  }
  return( $resultref, $result );
}

1;
