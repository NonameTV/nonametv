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
    my $self  = $class-&gt;SUPER::new( @_ );
    bless ($self, $class);

#    print Dumper( $self );

    defined( $self-&gt;{ApiKey} )   or die "You must specify ApiKey";
    defined( $self-&gt;{Language} ) or die "You must specify Language";

    # only consider Ratings with 10 or more votes by default
    if( !defined( $self-&gt;{MinRatingCount} ) ){
      $self-&gt;{MinRatingCount} = 10;
    }

    # only copy the synopsis if you trust their rights clearance enough!
    if( !defined( $self-&gt;{OnlyAugmentFacts} ) ){
      $self-&gt;{OnlyAugmentFacts} = 0;
    }

    # need config for main content cache path
    my $conf = ReadConfig( );

#    my $cachefile = $conf-&gt;{ContentCachePath} . '/' . $self-&gt;{Type} . '/tvdb.db';
#    my $bannerdir = $conf-&gt;{ContentCachePath} . '/' . $self-&gt;{Type} . '/banner';

    $self-&gt;{themoviedb} = TMDB-&gt;new(
        apikey =&gt; $self-&gt;{ApiKey},
        lang   =&gt; $self-&gt;{Language},
    );

    $self-&gt;{search} = $self-&gt;{themoviedb}-&gt;search(
        include_adult =&gt; 'false',  # Include adult results. 'true' or 'false'
    );

    # slow down to avoid rate limiting
    $self-&gt;{Slow} = 1;

    return $self;
}


sub FillCredits( $$$$$ ) {
  my( $self, $resultref, $credit, $doc, $job )=@_;

  my @nodes = $doc-&gt;findnodes( '/OpenSearchDescription/movies/movie/cast/person[@job=\'' . $job . '\']' );
  my @credits = ( );
  foreach my $node ( @nodes ) {
    my $name = $node-&gt;findvalue( './@name' );
    if( $job eq 'Actor' ) {
      my $role = $node-&gt;findvalue( './@character' );
      if( $role ) {
        # skip roles like '-', but allow roles like G, M, Q (The Guru, James Bond)
        if( ( length( $role ) &gt; 1 )||( $role =~ m|^[A-Z]$| ) ){
          $name .= ' (' . $role . ')';
        } else {
          w( 'Unlikely role \'' . $role . '\' for actor. Fix it at ' . $resultref-&gt;{url} . '/edit?active_nav_item=cast' );
        }
      }
    }
    push( @credits, $name );
  }
  if( @credits ) {
    $resultref-&gt;{$credit} = join( ', ', @credits );
  }
}


sub FillHash( $$$ ) {
  my( $self, $resultref, $movieId, $ceref )=@_;
 
  if( $self-&gt;{Slow} ) {
    sleep (1);
  }
  my $movie = $self-&gt;{themoviedb}-&gt;movie( id =&gt; $movieId );
#  print Dumper $movie-&gt;info;
#  print Dumper $movie-&gt;alternative_titles;
#  print Dumper $movie-&gt;cast;
#  print Dumper $movie-&gt;crew;
#  print Dumper $movie-&gt;images;
#  print Dumper $movie-&gt;keywords;
#  print Dumper $movie-&gt;releases;
#  print Dumper $movie-&gt;trailers;
#  print Dumper $movie-&gt;translations;
#  print Dumper $movie-&gt;lists;
#  print Dumper $movie-&gt;reviews;
#  print Dumper $movie-&gt;changes;

  if (not defined ($movie)) {
    w( $self-&gt;{Type} . ' failed to parse result.' );
    return;
  }

  # FIXME shall we use the alternative name if that's what was in the guide???
  # on one hand the augmenters are here to unify various styles on the other
  # hand matching the other guides means less surprise for the users
  $resultref-&gt;{title} = norm( $movie-&gt;title );
  if( defined( $movie-&gt;info ) ){
    my $original_title = $movie-&gt;info-&gt;{original_title};
    if( defined( $original_title ) ){
      $resultref-&gt;{original_title} = norm( $original_title );
    }else{
      my $url = 'http://www.themoviedb.org/movie/' . $movie-&gt;{id};
      w( "original title not on file, add it at $url." );
    }
  }

  # TODO shall we add the tagline as subtitle? (for german movies the tv title is often made of the movie title plus tagline)
  $resultref-&gt;{subtitle} = undef;

  $resultref-&gt;{program_type} = 'movie';

  if( defined( $movie-&gt;info ) ){
    if( defined( $movie-&gt;info-&gt;{vote_count} ) ){
      my $votes = $movie-&gt;info-&gt;{vote_count};
      if( $votes &gt;= $self-&gt;{MinRatingCount} ){
        # ratings range from 0 to 10
        $resultref-&gt;{'star_rating'} = $movie-&gt;info-&gt;{vote_average} . ' / 10';
      }
    }
  }
  
  # MPAA - G, PG, PG-13, R, NC-17 - No rating is: NR or Unrated
#  if(defined($doc-&gt;findvalue( '/OpenSearchDescription/movies/movie/certification' ) )) {
#    my $rating = norm( $doc-&gt;findvalue( '/OpenSearchDescription/movies/movie/certification' ) );
#    if( $rating ne '0' ) {
#      $resultref-&gt;{rating} = $rating;
#    }
#  }
  
  # No description when adding? Add the description from themoviedb
#  if((!defined ($ceref-&gt;{description}) or ($ceref-&gt;{description} eq "")) and !$self-&gt;{OnlyAugmentFacts}) {
#    my $desc = norm( $doc-&gt;findvalue( '/OpenSearchDescription/movies/movie/overview' ) );
#    if( $desc ne 'No overview found.' ) {
#      $resultref-&gt;{description} = $desc;
#    }
#  }

  if( exists( $movie-&gt;info()-&gt;{genres} ) ){
    my @genres = @{ $movie-&gt;info()-&gt;{genres} };
    foreach my $node ( @genres ) {
      my $genre_id = $node-&gt;{id};
      my ( $type, $categ ) = $self-&gt;{datastore}-&gt;LookupCat( "Tmdb_genre", $genre_id );
      AddCategory( $resultref, $type, $categ );
    }
  }

  # TODO themoviedb does not store a year of production only the first screening, that should go to previosly-shown instead
  # $resultref-&gt;{production_date} = $doc-&gt;findvalue( '/OpenSearchDescription/movies/movie/released' );

  $resultref-&gt;{url} = 'http://www.themoviedb.org/movie/' . $movie-&gt;{ id };

#  $self-&gt;FillCredits( $resultref, 'actors', $doc, 'Actor');

#  $self-&gt;FillCredits( $resultref, 'adapters', $doc, 'Actors');
#  $self-&gt;FillCredits( $resultref, 'commentators', $doc, 'Actors');
#  $self-&gt;FillCredits( $resultref, 'directors', $doc, 'Director');
#  $self-&gt;FillCredits( $resultref, 'guests', $doc, 'Actors');
#  $self-&gt;FillCredits( $resultref, 'presenters', $doc, 'Actors');
#  $self-&gt;FillCredits( $resultref, 'producers', $doc, 'Producer');
#  $self-&gt;FillCredits( $resultref, 'writers', $doc, 'Screenplay');

#  print STDERR Dumper( $apiresult );
}


sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';

  if( $ceref-&gt;{url} &amp;&amp; $ceref-&gt;{url} =~ m|^http://www\.themoviedb\.org/movie/\d+$| ) {
    $result = "programme is already linked to themoviedb.org, ignoring";
    $resultref = undef;
  } elsif( $ruleref-&gt;{matchby} eq 'movieid' ) {
    $self-&gt;FillHash( $resultref, $ruleref-&gt;{remoteref}, $ceref );
  } elsif( $ruleref-&gt;{matchby} eq 'title' ) {
    # search by title and year (if present)

    my $searchTerm = $ceref-&gt;{title};
    if( !$ceref-&gt;{production_date} &amp;&amp; !$ceref-&gt;{directors}){
      return( undef,  "Year and directors unknown, not searching at themoviedb.org!" );
    }

    # filter characters that confuse the search api
    # FIXME check again now that we encode umlauts &amp; co.
    $searchTerm =~ s|[-#\?\N{U+00BF}\(\)]||g;

    if( $self-&gt;{Slow} ) {
      sleep (1);
    }
    # TODO fix upstream instead of working around here
    my @candidates = $self-&gt;{search}-&gt;movie( $searchTerm );
    my @keep = ();

    my $numResult = @candidates;
    if( $numResult &lt; 1 ){
      return( undef,  "No matching movie found when searching for: " . $searchTerm );
    }else{

      # strip out all candidates without any matching director
      if( ( @candidates &gt;= 1 ) and ( $ceref-&gt;{directors} ) ){
        my @directors = split( /, /, $ceref-&gt;{directors} );
        my $match = 0;

        # loop over all remaining movies
        while( @candidates ) {
          my $candidate = shift( @candidates );

          if( defined( $candidate-&gt;{id} ) ) {
            # we have to fetch the remaining candidates to peek at the directors
            my $movieId = $candidate-&gt;{id};
            if( $self-&gt;{Slow} ) {
              sleep (1);
            }
            my $movie = $self-&gt;{themoviedb}-&gt;movie( id =&gt; $movieId );

            my @names = ( );
            foreach my $crew ( $movie-&gt;crew ) {
              if( $crew-&gt;{'job'} eq 'Director' ) {
                my $person = $self-&gt;{themoviedb}-&gt;person( id =&gt; $crew-&gt;{id} );
                if( defined( $person ) ){
                  if( defined( $person-&gt;aka() ) ){
                    if( defined( $person-&gt;aka()-&gt;[0] ) ){
                      # FIXME actually aka() should simply return an array
                      my $aliases = $person-&gt;aka()-&gt;[0];
                      if( defined( $aliases ) ){
                        @names =  ( @names, @{ $aliases } );
                      }else{
                        my $url = 'http://www.themoviedb.org/person/' . $crew-&gt;{id};
                        w( "something is fishy with this persons aliases, see $url." );
                      }
                      push( @names, $person-&gt;name );
                    }else{
                      my $url = 'http://www.themoviedb.org/person/' . $crew-&gt;{id};
                    w( "got a person but could not get the aliases (with [0]), see $url." );
                    }
                  }else{
                    my $url = 'http://www.themoviedb.org/person/' . $crew-&gt;{id};
                    w( "got a person but could not get the aliases, see $url." );
                  }
                }else{
                  my $url = 'http://www.themoviedb.org/person/' . $crew-&gt;{id};
                  w( "got a reference to a person but could not get the person, see $url." );
                }
              }
            }

            my $matches = 0;
            if( @names == 0 ){
              my $url = 'http://www.themoviedb.org/movie/' . $candidate-&gt;{ id };
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
              d( "director '" . $ceref-&gt;{directors} ."' not found, removing candidate" );
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
      if( $ceref-&gt;{production_date} ) {
        my( $produced )=( $ceref-&gt;{production_date} =~ m|^(\d{4})\-\d+\-\d+$| );
        while( @candidates ) {
          my $candidate = shift( @candidates );
          # verify that production and release year are close
          my $released = $candidate-&gt;{ release_date };
          $released =~ s|^(\d{4})\-\d+\-\d+$|$1|;
          if( !$released ){
            my $url = 'http://www.themoviedb.org/movie/' . $candidate-&gt;{ id };
            w( "year of release not on record, removing candidate. Add it at $url." );
          } elsif( abs( $released - $produced ) &gt; 2 ){
            d( "year of production '$produced' to far away from year of release '$released', removing candidate" );
          } else {
            push( @keep, $candidate );
          }
        }

        @candidates = @keep;
        @keep = ();
      }

      if( @candidates == 0 ){
        w( 'search for "' . $ceref-&gt;{title} . '" did not return any good hit, ignoring' );
      } elsif ( @candidates &gt; 1 ){
        w( 'search for "' . $ceref-&gt;{title} . '" did not return a single best hit, ignoring' );
      } else {
        my $movieId = $candidates[0]-&gt;{id};

        $self-&gt;FillHash( $resultref, $movieId, $ceref );
      }
    }
  }else{
    $result = "don't know how to match by '" . $ruleref-&gt;{matchby} . "'";
    $resultref = undef;
  }

  return( $resultref, $result );
}


1;