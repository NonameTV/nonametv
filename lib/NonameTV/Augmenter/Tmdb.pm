package NonameTV::Augmenter::Tmdb;

use strict;
use warnings;

use Data::Dumper;
use Encode;
use utf8;
use WWW::TheMovieDB::Search;

use NonameTV qw/norm ParseXml/;
use NonameTV::Augmenter::Base;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w d/;

use base 'NonameTV::Augmenter::Base';


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

#    print Dumper( $self );

    defined( $self->{ApiKey} )   or die "You must specify ApiKey";
    defined( $self->{Language} ) or die "You must specify Language";

    # only consider Ratings with 10 or more votes by default
    if( !defined( $self->{MinRatingCount} ) ){
      $self->{MinRatingCount} = 10;
    }

    # only copy the synopsis if you trust their rights clearance enough!
    if( !defined( $self->{OnlyAugmentFacts} ) ){
      $self->{OnlyAugmentFacts} = 0;
    }

    # need config for main content cache path
    my $conf = ReadConfig( );

#    my $cachefile = $conf->{ContentCachePath} . '/' . $self->{Type} . '/tvdb.db';
#    my $bannerdir = $conf->{ContentCachePath} . '/' . $self->{Type} . '/banner';

    $self->{themoviedb} = new WWW::TheMovieDB::Search;
    $self->{themoviedb}->key( $self->{ApiKey} );
    $self->{themoviedb}->lang( $self->{Language} );

    return $self;
}


sub FillCredits( $$$$$ ) {
  my( $self, $resultref, $credit, $doc, $job )=@_;

  my @nodes = $doc->findnodes( '/OpenSearchDescription/movies/movie/cast/person[@job=\'' . $job . '\']' );
  my @credits = ( );
  foreach my $node ( @nodes ) {
    my $name = $node->findvalue( './@name' );
    if( $job eq 'Actor' ) {
      my $role = $node->findvalue( './@character' );
      if( $role ) {
        # skip roles like '-', but allow roles like G, M, Q (The Guru, James Bond)
        if( ( length( $role ) > 1 )||( $role =~ m|^[A-Z]$| ) ){
          $name .= ' (' . $role . ')';
        } else {
          w( 'Unlikely role \'' . $role . '\' for actor. Fix it at ' . $resultref->{url} . '/cast/edit_cast' );
        }
      }
    }
    push( @credits, $name );
  }
  if( @credits ) {
    $resultref->{$credit} = join( ', ', @credits );
  }
}


sub FillHash( $$$ ) {
  my( $self, $resultref, $movieId, $ceref )=@_;

  my $apiresult = $self->{themoviedb}->Movie_getInfo( $movieId );
  my $doc = ParseXml( \$apiresult );

  if (not defined ($doc)) {
    w( $self->{Type} . ' failed to parse result.' );
    return;
  }

  # FIXME shall we use the alternative name if that's what was in the guide???
  # on one hand the augmenters are here to unify various styles on the other
  # hand matching the other guides means less surprise for the users
  $resultref->{title} = norm( $doc->findvalue( '/OpenSearchDescription/movies/movie/name' ) );

  # TODO shall we add the tagline as subtitle?
  $resultref->{subtitle} = undef;

  # is it a movie? (makes sense once we match by other attributes then program_type=movie :)
  my $type = $doc->findvalue( '/OpenSearchDescription/movies/movie/type' );
  if( $type eq 'movie' ) {
    $resultref->{program_type} = 'movie';
  }

  my $votes = $doc->findvalue( '/OpenSearchDescription/movies/movie/votes' );
  if( $votes >= $self->{MinRatingCount} ){
    # ratings range from 0 to 10
    $resultref->{'star_rating'} = $doc->findvalue( '/OpenSearchDescription/movies/movie/rating' ) . ' / 10';
  }
  
  # MPAA - G, PG, PG-13, R, NC-17 - No rating is: NR or Unrated
  if(defined($doc->findvalue( '/OpenSearchDescription/movies/movie/certification' ) )) {
    my $rating = norm( $doc->findvalue( '/OpenSearchDescription/movies/movie/certification' ) );
    if( $rating ne '0' ) {
      $resultref->{rating} = $rating;
    }
  }
  
  # No description when adding? Add the description from themoviedb
  if((!defined ($ceref->{description}) or ($ceref->{description} eq "")) and !$self->{OnlyAugmentFacts}) {
    my $desc = norm( $doc->findvalue( '/OpenSearchDescription/movies/movie/overview' ) );
    if( $desc ne 'No overview found.' ) {
      $resultref->{description} = $desc;
    }
  }

  # TODO themoviedb does not store a year of production only the first screening, that should go to previosly-shown instead
  # $resultref->{production_date} = $doc->findvalue( '/OpenSearchDescription/movies/movie/released' );

  $resultref->{url} = $doc->findvalue( '/OpenSearchDescription/movies/movie/url' );

  $self->FillCredits( $resultref, 'actors', $doc, 'Actor');

#  $self->FillCredits( $resultref, 'adapters', $doc, 'Actors');
#  $self->FillCredits( $resultref, 'commentators', $doc, 'Actors');
  $self->FillCredits( $resultref, 'directors', $doc, 'Director');
#  $self->FillCredits( $resultref, 'guests', $doc, 'Actors');
#  $self->FillCredits( $resultref, 'presenters', $doc, 'Actors');
  $self->FillCredits( $resultref, 'producers', $doc, 'Producer');
  $self->FillCredits( $resultref, 'writers', $doc, 'Screenplay');

#  print STDERR Dumper( $apiresult );
}


sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';

  if( $ceref->{url} && $ceref->{url} =~ m|^http://www\.themoviedb\.org/movie/\d+$| ) {
    $result = "programme is already linked to themoviedb.org, ignoring";
    $resultref = undef;
  } elsif( $ruleref->{matchby} eq 'movieid' ) {
    $self->FillHash( $resultref, $ruleref->{remoteref}, $ceref );
  } elsif( $ruleref->{matchby} eq 'title' ) {
    # search by title and year (if present)

    my $searchTerm = $ceref->{title};
    if( $ceref->{production_date} ){
#      my( $year )=( $ceref->{production_date} =~ m|^(\d{4})\-\d+\-\d+$| );
#      $searchTerm .= ' ' . $year;
    }else{
      return( undef,  "Year unknown, not searching at themoviedb.org!" );
    }

    # filter characters that confuse the search api
    # FIXME check again now that we encode umlauts & co.
    $searchTerm =~ s|[-#\?]||g;

    # TODO fix upstream instead of working around here
    my $apiresult = $self->{themoviedb}->Movie_search( encode( 'utf-8', $searchTerm ) );

    if( !$apiresult ) {
      return( undef, $self->{Type} . ' empty result xml, bug upstream site to fix it.' );
    }

    my $doc = ParseXml( \$apiresult );

    if (not defined ($doc)) {
      return( undef, $self->{Type} . ' failed to parse result.' );
    }

    # The data really looks like this...
    my $ns = $doc->find ('/OpenSearchDescription/opensearch:totalResults');
    if( $ns->size() == 0 ) {
      return( undef,  "No valid search result returned" );
    }

    my $numResult = $doc->findvalue( '/OpenSearchDescription/opensearch:totalResults' );
    if( $numResult < 1 ){
      return( undef,  "No matching movie found when searching for: " . $searchTerm );
#    }elsif( $numResult > 1 ){
#      return( undef,  "More then one matching movie found when searching for: " . $searchTerm );
    }else{
#      print STDERR Dumper( $apiresult );

      my( $produced )=( $ceref->{production_date} =~ m|^(\d{4})\-\d+\-\d+$| );
      my @candidates = $doc->findnodes( '/OpenSearchDescription/movies/movie' );
      foreach my $candidate ( @candidates ) {
        # verify that production and release year are close
        my $released = $candidate->findvalue( './released' );
        $released =~ s|^(\d{4})\-\d+\-\d+$|$1|;
        if( !$released ){
          $candidate->unbindNode();
        } elsif( abs( $released - $produced ) > 2 ){
          $candidate->unbindNode();
        }
      }

      @candidates = $doc->findnodes( '/OpenSearchDescription/movies/movie' );
      if( @candidates != 1 ){
        d( 'search did not return a single best hit, ignoring' );
      } else {
        my $movieId = $doc->findvalue( '/OpenSearchDescription/movies/movie/id' );
        my $movieLanguage = $doc->findvalue( '/OpenSearchDescription/movies/movie/language' );
        my $movieTranslated = $doc->findvalue( '/OpenSearchDescription/movies/movie/translated' );

        $self->FillHash( $resultref, $movieId, $ceref );
      }
    }
  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
    $resultref = undef;
  }

  return( $resultref, $result );
}


1;
