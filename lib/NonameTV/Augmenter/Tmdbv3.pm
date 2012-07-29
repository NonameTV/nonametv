package NonameTV::Augmenter::Tmdb;

use strict;
use warnings;

use Data::Dumper;
use Encode;
use utf8;
use TMDB;

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

    $self->{themoviedb} = TMDB->new( { api_key => $self->{ApiKey} } );
    #$self->{themoviedb}->key( $self->{ApiKey} );
    #$self->{themoviedb}->lang( $self->{Language} );

    # slow down to avoid rate limiting
    $self->{Slow} = 1;

    return $self;
}

sub FillHash( $$$ ) {
  my( $self, $resultref, $movieId, $ceref )=@_;
 
  if( $self->{Slow} ) {
    sleep (1);
  }
  my $movie = $self->{themoviedb}->movie( $movieId );

  # FIXME shall we use the alternative name if that's what was in the guide???
  # on one hand the augmenters are here to unify various styles on the other
  # hand matching the other guides means less surprise for the users
  #
  # Change original_name to name if you want your specific language's movie name.
  $resultref->{title} = norm( $movie->name() );
  $resultref->{original_title} = norm($ceref->{title});

  # TODO shall we add the tagline as subtitle?
  $resultref->{subtitle} = undef;
  $resultref->{program_type} = 'movie';

  my $votes = $movie->{_info}{votes};
  if( $votes >= $self->{MinRatingCount} ){
    # ratings range from 0 to 10
    $resultref->{'star_rating'} = $movie->{_info}{rating} . ' / 10';
  }
  
  # MPAA - G, PG, PG-13, R, NC-17 - No rating is: NR or Unrated
  if(defined( $movie->certification() )) {
    my $rating = norm( $movie->certification() );
    if( $rating ne '0' ) {
      $resultref->{rating} = $rating;
    }
  }
  
  # No description when adding? Add the description from themoviedb
  if((!defined ($ceref->{description}) or ($ceref->{description} eq "")) and !$self->{OnlyAugmentFacts}) {
    my $desc = norm( $movie->overview() );
    if( $desc ne 'No overview found.' ) {
      $resultref->{description} = $desc;
    }
  }

  # TODO themoviedb does not store a year of production only the first screening, that should go to previosly-shown instead
  # $resultref->{production_date} = $doc->findvalue( '/OpenSearchDescription/movies/movie/released' );

  $resultref->{url} = $movie->url();
  $resultref->{extra_id} = $movie->imdb_id;
  $resultref->{extra_id_type} = "themoviedb";
	
#  	$self->FillCredits( $resultref, 'actors', $doc, 'Actor');

#	  $self->FillCredits( $resultref, 'adapters', $doc, 'Actors');
#  	$self->FillCredits( $resultref, 'commentators', $doc, 'Actors');
#  	$self->FillCredits( $resultref, 'directors', $doc, 'Director');
#  	$self->FillCredits( $resultref, 'guests', $doc, 'Actors');
#  	$self->FillCredits( $resultref, 'presenters', $doc, 'Actors');
#  	$self->FillCredits( $resultref, 'producers', $doc, 'Producer');
  	
  	if(defined($movie->actors)) {
  		$resultref->{actors} = join( ', ', $movie->actors) );
  	}
  	
  	if(defined($movie->director)) {
  		$resultref->{directors} = join( ', ', $movie->director) );
  	}
  	
  	if(defined($movie->writer)) {
  		$resultref->{writers} = join( ', ', $movie->writer) );
  	}
  	
  	if(defined($movie->producer)) {
  		$resultref->{producers} = join( ', ', $movie->producer) );
  	}
  	
  	# Writers can be in multiple "jobs", ie: Author, Writer, Screenplay and more.
#  	$self->FillCredits( $resultref, 'writers', $doc, 'Screenplay');

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

    if( $self->{Slow} ) {
      sleep (1);
    }
    
    # Search
    my $search  = $self->{themoviedb}->search();
    
      # if we have multiple candidate movies strip out all without a matching director
      my @candidates = $search->movie( encode( 'utf-8', $searchTerm ) );
      if( ( @candidates > 1 ) and ( $ceref->{directors} ) ){
        my @directors = split( /, /, $ceref->{directors} );
        my $director = $directors[0];
        foreach my $candidate ( @candidates ) {
          # we have to fetch the remaining candidates to peek at the directors
          my $movieId = $candidate->{id};
          if( $self->{Slow} ) {
            sleep (1);
          }
          my $apiresult = $self->{themoviedb}->Movie_getInfo( $movieId );
          my $doc2 = ParseXml( \$apiresult );

          if (not defined ($doc2)) {
            w( $self->{Type} . ' failed to parse result.' );
            last;
          }

          my @nodes = $doc2->findnodes( '/OpenSearchDescription/movies/movie/cast/person[@job=\'Director\' and @name=\'' . $director . '\']' );
          if( @nodes != 1 ){
            $candidate->unbindNode();
            d( "director '$director' not found, removing candidate" );
          }
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
  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
    $resultref = undef;
  }

  return( $resultref, $result );
}


1;
