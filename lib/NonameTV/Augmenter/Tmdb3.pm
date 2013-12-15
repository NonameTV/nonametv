package NonameTV::Augmenter::Tmdb3;

use strict;
use warnings;

use Data::Dumper;
use Encode;
use utf8;
use TMDB;

use NonameTV qw/AddCategory norm ParseXml/;
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

    $self->{themoviedb} = TMDB->new(
        apikey => $self->{ApiKey},
        lang   => $self->{Language},
    );

    $self->{search} = $self->{themoviedb}->search(
        include_adult => 'false',  # Include adult results. 'true' or 'false'
    );

    # slow down to avoid rate limiting
    $self->{Slow} = 1;

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
          w( 'Unlikely role \'' . $role . '\' for actor. Fix it at ' . $resultref->{url} . '/edit?active_nav_item=cast' );
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
 
  if( $self->{Slow} ) {
    sleep (1);
  }
  my $movie = $self->{themoviedb}->movie( id => $movieId );
#  print Dumper $movie->info;
#  print Dumper $movie->alternative_titles;
#  print Dumper $movie->cast;
#  print Dumper $movie->crew;
#  print Dumper $movie->images;
#  print Dumper $movie->keywords;
#  print Dumper $movie->releases;
#  print Dumper $movie->trailers;
#  print Dumper $movie->translations;
#  print Dumper $movie->lists;
#  print Dumper $movie->reviews;
#  print Dumper $movie->changes;

  if (not defined ($movie)) {
    w( $self->{Type} . ' failed to parse result.' );
    return;
  }

  # FIXME shall we use the alternative name if that's what was in the guide???
  # on one hand the augmenters are here to unify various styles on the other
  # hand matching the other guides means less surprise for the users
  $resultref->{title} = norm( $movie->title );
  if( defined( $movie->info ) ){
    my $original_title = $movie->info->{original_title};
    if( defined( $original_title ) ){
      $resultref->{original_title} = norm( $original_title );
    }else{
      my $url = 'http://www.themoviedb.org/movie/' . $movie->{id};
      w( "original title not on file, add it at $url." );
    }
  }

  # TODO shall we add the tagline as subtitle? (for german movies the tv title is often made of the movie title plus tagline)
  $resultref->{subtitle} = undef;

  $resultref->{program_type} = 'movie';

  if( defined( $movie->info ) ){
    if( defined( $movie->info->{vote_count} ) ){
      my $votes = $movie->info->{vote_count};
      if( $votes >= $self->{MinRatingCount} ){
        # ratings range from 0 to 10
        $resultref->{'star_rating'} = $movie->info->{vote_average} . ' / 10';
      }
    }
  }
  
  # MPAA - G, PG, PG-13, R, NC-17 - No rating is: NR or Unrated
#  if(defined($doc->findvalue( '/OpenSearchDescription/movies/movie/certification' ) )) {
#    my $rating = norm( $doc->findvalue( '/OpenSearchDescription/movies/movie/certification' ) );
#    if( $rating ne '0' ) {
#      $resultref->{rating} = $rating;
#    }
#  }
  
  # No description when adding? Add the description from themoviedb
#  if((!defined ($ceref->{description}) or ($ceref->{description} eq "")) and !$self->{OnlyAugmentFacts}) {
#    my $desc = norm( $doc->findvalue( '/OpenSearchDescription/movies/movie/overview' ) );
#    if( $desc ne 'No overview found.' ) {
#      $resultref->{description} = $desc;
#    }
#  }

  if( exists( $movie->info()->{genres} ) ){
    my @genres = @{ $movie->info()->{genres} };
    foreach my $node ( @genres ) {
      my $genre_id = $node->{id};
      my ( $type, $categ ) = $self->{datastore}->LookupCat( "Tmdb_genre", $genre_id );
      AddCategory( $resultref, $type, $categ );
    }
  }

  # TODO themoviedb does not store a year of production only the first screening, that should go to previosly-shown instead
  # $resultref->{production_date} = $doc->findvalue( '/OpenSearchDescription/movies/movie/released' );

  $resultref->{url} = 'http://www.themoviedb.org/movie/' . $movie->{ id };

#  $self->FillCredits( $resultref, 'actors', $doc, 'Actor');

#  $self->FillCredits( $resultref, 'adapters', $doc, 'Actors');
#  $self->FillCredits( $resultref, 'commentators', $doc, 'Actors');
#  $self->FillCredits( $resultref, 'directors', $doc, 'Director');
#  $self->FillCredits( $resultref, 'guests', $doc, 'Actors');
#  $self->FillCredits( $resultref, 'presenters', $doc, 'Actors');
#  $self->FillCredits( $resultref, 'producers', $doc, 'Producer');
#  $self->FillCredits( $resultref, 'writers', $doc, 'Screenplay');

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
    if( !$ceref->{production_date} && !$ceref->{directors}){
      return( undef,  "Year and directors unknown, not searching at themoviedb.org!" );
    }

    # filter characters that confuse the search api
    # FIXME check again now that we encode umlauts & co.
    $searchTerm =~ s|[-#\?\N{U+00BF}\(\)]||g;

    if( $self->{Slow} ) {
      sleep (1);
    }
    # TODO fix upstream instead of working around here
    my @candidates = $self->{search}->movie( $searchTerm );
    my @keep = ();

    my $numResult = @candidates;
    if( $numResult < 1 ){
      return( undef,  "No matching movie found when searching for: " . $searchTerm );
    }else{

      # strip out all candidates without any matching director
      if( ( @candidates >= 1 ) and ( $ceref->{directors} ) ){
        my @directors = split( /, /, $ceref->{directors} );
        my $match = 0;

        # loop over all remaining movies
        while( @candidates ) {
          my $candidate = shift( @candidates );

          if( defined( $candidate->{id} ) ) {
            # we have to fetch the remaining candidates to peek at the directors
            my $movieId = $candidate->{id};
            if( $self->{Slow} ) {
              sleep (1);
            }
            my $movie = $self->{themoviedb}->movie( id => $movieId );

            my @names = ( );
            foreach my $crew ( $movie->crew ) {
              # tv stations sometimes list the movie as being "by the author" instead of the director, so accept both
              if( ( $crew->{'job'} eq 'Director' )||( $crew->{'job'} eq 'Author' ) ) {
                my $person = $self->{themoviedb}->person( id => $crew->{id} );
                if( defined( $person ) ){
                  if( defined( $person->aka() ) ){
                    if( defined( $person->aka()->[0] ) ){
                      # FIXME actually aka() should simply return an array
                      my $aliases = $person->aka()->[0];
                      if( defined( $aliases ) ){
                        @names =  ( @names, @{ $aliases } );
                      }else{
                        my $url = 'http://www.themoviedb.org/person/' . $crew->{id};
                        w( "something is fishy with this persons aliases, see $url." );
                      }
                      push( @names, $person->name );
                    }else{
                      my $url = 'http://www.themoviedb.org/person/' . $crew->{id};
                    w( "got a person but could not get the aliases (with [0]), see $url." );
                    }
                  }else{
                    my $url = 'http://www.themoviedb.org/person/' . $crew->{id};
                    w( "got a person but could not get the aliases, see $url." );
                  }
                }else{
                  my $url = 'http://www.themoviedb.org/person/' . $crew->{id};
                  w( "got a reference to a person but could not get the person, see $url." );
                }
              }
            }

            my $matches = 0;
            if( @names == 0 ){
              my $url = 'http://www.themoviedb.org/movie/' . $candidate->{ id };
              w( "director not on record, removing candidate. Add it at $url." );
            } else {
              foreach my $a ( @directors ) {
                foreach my $b ( @names ) {
                  if( lc norm( $a ) eq lc norm( $b ) ) {
                    $matches += 1;
                  }
                }
              }
            }
            if( $matches == 0 ){
              d( "director '" . $ceref->{directors} ."' not found, removing candidate" );
            } else {
              push( @keep, $candidate );
            }
          }else{
            w( "got a movie result without id as candidate! " . Dumper( $candidate ) );
          }
        }

        @candidates = @keep;
        @keep = ();
      }

      # filter out movies more then 2 years before/after if we know the year
      if( $ceref->{production_date} ) {
        my( $produced )=( $ceref->{production_date} =~ m|^(\d{4})\-\d+\-\d+$| );
        while( @candidates ) {
          my $candidate = shift( @candidates );
          # verify that production and release year are close
          my $released = $candidate->{ release_date };
          $released =~ s|^(\d{4})\-\d+\-\d+$|$1|;
          if( !$released ){
            my $url = 'http://www.themoviedb.org/movie/' . $candidate->{ id };
            w( "year of release not on record, removing candidate. Add it at $url." );
          } elsif( abs( $released - $produced ) > 2 ){
            d( "year of production '$produced' to far away from year of release '$released', removing candidate" );
          } else {
            push( @keep, $candidate );
          }
        }

        @candidates = @keep;
        @keep = ();
      }

      if( @candidates == 0 ){
        w( 'search for "' . $ceref->{title} . '" did not return any good hit, ignoring' );
      } elsif ( @candidates > 1 ){
        w( 'search for "' . $ceref->{title} . '" did not return a single best hit, ignoring' );
      } else {
        my $movieId = $candidates[0]->{id};

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
