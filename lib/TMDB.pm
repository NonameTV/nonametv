package TMDB;

#######################
# LOAD MODULES
#######################
use strict;
use warnings FATAL => 'all';
use Carp qw(croak carp);

#######################
# VERSION
#######################
<<<<<<< HEAD
our $VERSION = '0.03';
=======
our $VERSION = '0.08';

#######################
# LOAD CPAN MODULES
#######################
use Object::Tiny qw(session);
>>>>>>> 02cb4241e8ca64ec24b6fc3827dac2b1d4db489e

#######################
# LOAD DIST MODULES
#######################
<<<<<<< HEAD
use TMDB::Session;
use TMDB::Search;
use TMDB::Movie;
use TMDB::Person;
=======
use TMDB::Genre;
use TMDB::Movie;
use TMDB::Config;
use TMDB::Person;
use TMDB::Search;
use TMDB::Company;
use TMDB::Session;
use TMDB::Collection;
>>>>>>> 02cb4241e8ca64ec24b6fc3827dac2b1d4db489e

#######################
# PUBLIC METHODS
#######################

<<<<<<< HEAD
## Constructor
sub new {
    my ( $class, $args ) = @_;
    my $self = {};

    # Initialize
    bless $self, $class;
    return $self->_init($args);
} ## end sub new

## Search Object
sub search {
    my $self = shift;
    return TMDB::Search->new( { session => $self->_session } );
}

## Movie Object
sub movie {
    my $self = shift;
    my $id = shift || croak "Movie ID is required";
    return TMDB::Movie->new(
        {
            session => $self->_session,
            id      => $id
        }
    );
} ## end sub movie

## Person Object
sub person {
    my $self = shift;
    my $id = shift || croak "Person ID is required";
    return TMDB::Person->new(
        {
            session => $self->_session,
            id      => $id
        }
    );
} ## end sub person

#######################
# PRIVATE METHODS
#######################

## Initialize
sub _init {
    my $self = shift;
    my $args = shift || {};

    croak "Hash reference expected" unless ( ref $args eq 'HASH' );

    $args->{_VERSION} = $VERSION;
    $self->{_session} = TMDB::Session->new($args);
    return $self;
} ## end sub _init

## Session
sub _session {
    my $self = shift;
    if (@_) { return $self->{_session} = @_; }
    return $self->{_session};
}
=======
## ====================
## CONSTRUCTOR
## ====================
sub new {
    my ( $class, @args ) = @_;
    my $self = {};
    bless $self, $class;

    # Init Session
    $self->{session} = TMDB::Session->new(@args);
  return $self;
} ## end sub new

## ====================
## TMDB OBJECTS
## ====================
sub collection {
  return TMDB::Collection->new(
        session => shift->session,
        @_
    );
} ## end sub collection
sub company { return TMDB::Company->new( session => shift->session, @_ ); }
sub config { return TMDB::Config->new( session => shift->session, @_ ); }
sub genre { return TMDB::Genre->new( session => shift->session, @_ ); }
sub movie { return TMDB::Movie->new( session => shift->session, @_ ); }
sub person { return TMDB::Person->new( session => shift->session, @_ ); }
sub search { return TMDB::Search->new( session => shift->session, @_ ); }
>>>>>>> 02cb4241e8ca64ec24b6fc3827dac2b1d4db489e

#######################
1;

__END__

#######################
# POD SECTION
#######################
<<<<<<< HEAD
=======

>>>>>>> 02cb4241e8ca64ec24b6fc3827dac2b1d4db489e
=pod

=head1 NAME

TMDB - Perl wrapper for The MovieDB API

=head1 SYNOPSIS

<<<<<<< HEAD
    use TMDB;

    # Initialize
    my $tmdb = TMDB->new( { api_key => 'xxxxxx' } );

    # Search for movies
    my @results = $tmdb->search->movie('Italian Job');
    foreach my $result (@results) {
        print "#$result->{id}: $result->{name} ($result->{year})\n";
    }

    # Get movie info
    my $movie = $tmdb->movie('19995');
    printf( "%s (%s)\n", $movie->name, $movie->year );
    printf( "%s\n", $movie->tagline );
    printf( "Overview: %s\n", $movie->overview );
    printf( "Director: %s\n", join( ',', $movie->director ) );
    printf( "Cast: %s\n",     join( ',', $movie->cast ) );
    
=head1 DESCRIPTION

L<The MovieDB|http://www.themoviedb.org/> is a free and open movie database.
This module provides a Perl wrapper to L<The MovieDB
API|http://api.themoviedb.org>. In order to use this module, you must first get
an API key by L<signing up|http://www.themoviedb.org/account/signup>.

=head1 METHODS

=head2 new(\%options)

    my $tmdb = TMDB->new({api_key => 'xxxxxxx', ua => $ua});

The constructor accepts the following options

=over

=item api_key

Requierd. This is your TMDb API key

=item ua

Optional. You can initialize with your own L<LWP::UserAgent>

=back

=head2 SEARCH

The following search methods are available

=over

=item movie($name)

=item movie({name => $name, year => $year})

    my @results = $tmdb->search->movie('Avatar');           # Using a title
    my @results = $tmdb->search->movie('Avatar (2009)');    # Title includes year
    my @results =
      $tmdb->search->movie( { name => 'Avatar', year => '2009' } );  # Split them up

The search result returned is an array, or undef if nothing is found. Each
element in the result array is a hash ref containing C<name> (movie name),
C<year> (release year), C<id> (TMDb ID), C<thumb> (A thumbnail image URL) and
C<url> (TMDb movie URL).

=item person($name)

    my @results = $tmdb->search->person('George Clooney');

The search result returned is an array, or undef if nothing is found. Each
element in the result array is a hash ref containing C<name> (Person's name),
C<id> (TMDb ID), C<thumb> (A thumbnail image URL) and C<url> (TMDb profile
URL).

=item imdb($imdb_id)

    my @results = $tmdb->search->imdb('tt1542344');

This allows you to search a movie by its IMDB ID. The search result returned is
the same as L</movie($name)>

=item dvdid($dvdid)

    my @results = $tmdb->search->dvdid($dvdid);

This allows you to search a movie by its
L<DVDID|http://www.srcf.ucam.org/~cjk32/dvdid/>. The search result returned is
the same as L</movie($name)>

=item file($filename)

    my @results = $tmdb->search->file($filename);

This allows you to search a movie by passing a file. The file's
L<HashID|http://trac.opensubtitles.org/projects/opensubtitles/wiki/HashSourceCodes>
and size is used to search TMDb. The search result returned is the same as
L</movie($name)>

=back

=head2 movie

    # Initialize using TMDb ID
    my $movie = $tmdb->movie($id);

    # Movie Information
    $movie->name();                   # Get Movie name
    $movie->year();                   # Release year
    $movie->released();               # Release date
    $movie->url();                    # TMDb URL
    $movie->id();                     # TMDb ID
    $movie->imdb_id();                # IMDB ID
    $movie->tagline();                # Movie tagline
    $movie->overview();               # Movie Overview/plot
    $movie->rating();                 # Rating on TMDb
    $movie->runtime();                # Runtime
    $movie->trailer();                # link to YouTube trailer
    $movie->homepage();               # Official homepage
    $movie->certification();          # MPAA certification
    $movie->budget();                 # Budget

    # Cast & Crew
    #   All of these methods returns an array
    $movie->cast();
    $movie->director();
    $movie->producer();
    $movie->writers();

    # Images
    #   Returns an array with image URLs
    $movie->posters($size)
      ; # Specify what size you want (original/mid/cover/thumb). Defaults to 'original'
    $movie->backdrops($size)
      ; # Specify what size you want (original/poster/thumb). Defaults to 'original'

    # Genres
    #   Returns an array
    $movie->genres();

    # Studios
    #   Returns an array
    $movie->studios();

    # ALl in one
    #   Get a flattened hash containing all movie details
    my $info = $movie->info();
    use Data::Dumper;
    print Dumper $info;

=head2 person

    # Initialize using TMDb ID
    my $person = $tmdb->person($id);

    # Details
    $person->name();        # Name
    $person->id();          # TMDb ID
    $person->bio();         # Biography
    $person->birthday();    # Birthday
    $person->url();         # TMDb profile URL

    # Filmography
    #   Returns an array with movie names
    $person->movies();

    # Images
    #   Returns an array with image URLs
    $person->posters($size)
      ;    # Specify what size (original/profile/thumb). Defaults to 'original'

    # ALl in one
    #   Get a flattened hash containing all person details
    my $info = $person->info();
    use Data::Dumper;
    print Dumper $info;
    
=head1 DEPENDENCIES

L<Encode>

L<LWP::UserAgent>

L<YAML::Any>

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to C<bug-tmdb@rt.cpan.org>, or
through the web interface at
L<http://rt.cpan.org/Public/Dist/Display.html?Name=TMDB>

=======
      use TMDB;

      # Initialize
      my $tmdb = TMDB->new( apikey => 'xxxxxxxxxx' );

      # Search
      # =======

      # Search for a movie
      my @results = $tmdb->search->movie('Snatch');
      foreach my $result (@results) {
        printf( "%s:\t%s (%s)\n",
            $result->{id}, $result->{title},
            split( /-/, $result->{release_date}, 1 ) );
      }

      # Search for an actor
      my @results = $tmdb->search->person('Sean Connery');
      foreach my $result (@results) {
        printf( "%s:\t%s\n", $result->{id}, $result->{name} );
      }

      # Movie Data
      # ===========

      # Movie Object
      my $movie = $tmdb->movie( id => '107' );

      # Movie details
      my $movie_title     = $movie->title;
      my $movie_year      = $movie->year;
      my $movie_tagline   = $movie->tagline;
      my $movie_overview  = $movie->overview;
      my @movie_directors = $movie->director;
      my @movie_actors    = $movie->actors;

      printf( "%s (%s)\n%s", $movie_title, $movie_year,
        '=' x length($movie_title) );
      printf( "Tagline: %s\n",     $movie_tagline );
      printf( "Overview: %s\n",    $movie_overview );
      printf( "Directed by: %s\n", join( ',', @movie_directors ) );
      print("\nCast:\n");
      printf( "\t-%s\n", $_ ) for @movie_actors;

      # Person Data
      # ===========

      # Person Object
      my $person = $tmdb->person( id => '1331' );

      # Person Details
      my $person_name   = $person->name;
      my $person_bio    = $person->bio;
      my @person_movies = $person->starred_in;

      printf( "%s\n%s\n%s\n",
        $person_name, '=' x length($person_name), $person_bio );
      print("\nActed in:\n");
      printf( "\t-%s\n", $_ ) for @person_movies;


=head1 DESCRIPTION

L<The MovieDB|http://www.themoviedb.org/> is a free and open movie
database. This module provides a Perl wrapper to L<The MovieDB
API|http://help.themoviedb.org/kb/api/about-3>. In order to use this
module, you must first get an API key by L<signing
up|http://www.themoviedb.org/account/signup>.

B<NOTE:> TMDB-v0.04 and higher uses TheMoviDB API version C</3>. This
brings some significant differences both to the API and the interface
this module provides, along with updated dependencies for this
distribution. If you like to continue to use v2.1 API, you can continue
to use L<TMDB-0.03x|https://metacpan.org/release/MITHUN/TMDB-0.03/>.

=head1 INITIALIZATION

      # Initialize
      my $tmdb = TMDB->new(
         apikey => 'xxxxxxxxxx...',  # API Key
         lang   => 'en',             # A valid ISO 639-1 (Aplha-2) language code
         client => $http_tiny,       # A valid HTTP::Tiny object
         json   => $json_object,     # A Valid JSON object
      );

The constructor accepts the following options:

=over

=item apikey

This is your API key

=item lang

This must be a valid ISO 639-1 (Alpha-2) language code. Note that with
C</3>, the API no longer falls back to an English default.

L<List of ISO 639-1
codes|http://en.wikipedia.org/wiki/List_of_ISO_639-1_codes>.

=item client

You can provide your own L<HTTP::Client> object, otherwise a default
one is used.

=item json

You can provide your own L<JSON> implementation that can C<decode>
JSON. This will fall back to using L<JSON::Any>. However, L<JSON::XS>
is recommended.

=back

=head1 CONFIGURATION

      # Get Config
      my $config = $tmdb->config;
      print Dumper $config->config;   # Get all of it

      # Get the base URL
      my $base_url        = $config->img_base_url();
      my $secure_base_url = $config->img_secure_base_url();

      # Sizes (All are array-refs)
      my $poster_sizes   = $config->img_poster_sizes();
      my $backdrop_sizes = $config->img_backdrop_sizes();
      my $profile_sizes  = $config->img_profile_sizes();
      my $logo_sizes     = $config->img_logo_sizes();

      # List of _change keys_
      my $change_keys = $config->change_keys();

This provides the configuration for the C</3> API. See
L<http://docs.themoviedb.apiary.io/#configuration> for more details.

=head1 SEARCH

      # Configuration
      my $search = $tmdb->search(
         include_adult => 'false',  # Include adult results. 'true' or 'false'
         max_pages     => 5,        # Max number of paged results
      );

      # Search
      my $search  = $tmdb->search();
      my @results = $search->movie('Snatch (2000)');    # Search for movies
      my @results = $search->person('Brad Pitt');       # Search people by Name
      my @results = $search->company('Sony Pictures');  # Search for companies
      my @results = $search->keyword('thriller');       # Search for keywords
      my @results = $search->collection('Star Wars');   # Search for collections
      my @results = $search->list('top 250');           # Search lists

      # Discover
      my @results = $search->discover(
          {
              sort_by            => 'popularity.asc',
              'vote_average.gte' => '7.2',
              'vote_count.gte'   => '10',
          }
      );

      # Get Lists
      my $lists         = $tmdb->search();
      my $latest        = $lists->latest();      # Latest movie added to TheMovieDB
      my $latest_person = $lists->latest_person; # Latest person added to TheMovieDB
      my @now_playing   = $lists->now_playing(); # What's currently in theaters
      my @upcoming      = $lists->upcoming();    # Coming soon ...
      my @popular       = $lists->popular();     # What's currently popular
      my @popular_people = $lists->popular_people();  # Who's currently popular
      my @top_rated      = $lists->top_rated();       # Get the top rated list


=head1 MOVIE

      # Get the movie object
      my $movie = $tmdb->movie( id => '49521' );

      # Movie Data (as returned by the API)
      use Data::Dumper qw(Dumper);
      print Dumper $movie->info;
      print Dumper $movie->alternative_titles;
      print Dumper $movie->cast;
      print Dumper $movie->crew;
      print Dumper $movie->images;
      print Dumper $movie->keywords;
      print Dumper $movie->releases;
      print Dumper $movie->trailers;
      print Dumper $movie->translations;
      print Dumper $movie->lists;
      print Dumper $movie->reviews;
      print Dumper $movie->changes;

      # Filtered Movie data
      print $movie->title;
      print $movie->year;
      print $movie->tagline;
      print $movie->overview;
      print $movie->description;         # Same as `overview`
      print $movie->genres;
      print $movie->imdb_id;
      print $movie->collection;          # Collection ID
      print $movie->actors;              # Names of Actors
      print $movie->director;            # Names of Directors
      print $movie->producer;            # Names of Producers
      print $movie->executive_producer;  # Names of Executive Producers
      print $movie->writer;              # Names of Writers/Screenplay

      # Images
      print $movie->poster;              # Main Poster
      print $movie->posters;             # list of posters
      print $movie->backdrop;            # Main backdrop
      print $movie->backdrops;           # List of backdrops
      print $movie->trailers_youtube;    # List of Youtube trailers URLs

      # Latest Movie on TMDB
      print Dumper $movie->latest;

      # Get TMDB's version to check if anything changed
      print $movie->version;


=head1 PEOPLE

      # Get the person object
      my $person = $tmdb->person( id => '1331' );

      # Movie Data (as returned by the API)
      use Data::Dumper qw(Dumper);
      print Dumper $person->info;
      print Dumper $person->credits;
      print Dumper $person->images;

      # Filtered Person data
      print $person->name;
      print $person->aka;                 # Also Known As (list of names)
      print $person->bio;
      print $person->image;               # Main profile image
      print $person->starred_in;          # List of titles (as cast)
      print $person->directed;            # list of titles Directed
      print $person->produced;            # list of titles produced
      print $person->executive_produced;  # List of titles as an Executive Producer
      print $person->wrote;               # List of titles as a writer/screenplay

      # Get TMDB's version to check if anything changed
      print $person->version;


=head1 COLLECTION

      # Get the collection object
      my $collection = $tmdb->collection(id => '2344');

      # Collection data (as returned by the API)
      use Data::Dumper;
      print Dumper $collection->info;

      # Filtered Collection Data
      print $collection->titles;  # List of titles in the collection
      print $collection->ids;     # List of movie IDs in the collection

      # Get TMDB's version to check if anything changed
      print $collection->version;


=head1 COMPANY

		# Get the company object
		my $company = $tmdb->company(id => '1');

		# Company info (as returned by the API)
		use Data::Dumper qw(Dumper);
		print Dumper $company->info;
		print Dumper $company->movies;

		# Filtered company data
		print $company->name; # Name of the Company
		print $company->logo; # Logo

		# Get TMDB's version to check if anything changed
		print $company->version;

=head1 GENRE

		# Get a list
		my @genres = $tmdb->genre->list();

		# Get a list of movies
		my @movies = $tmdb->genre(id => '35')->movies;


=head1 DEPENDENCIES

=over

=item L<Encode>

=item L<HTTP::Tiny>

=item L<JSON::Any>

=item L<Locale::Codes>

=item L<Object::Tiny>

=item L<Params::Validate>

=item L<URI::Encode>

=back

=head1 BUGS AND LIMITATIONS

This module not (yet!) support POST-ing data to TheMovieDB

All data returned is UTF-8 encoded

Please report any bugs or feature requests to C<bug-tmdb@rt.cpan.org>,
or through the web interface at
L<http://rt.cpan.org/Public/Dist/Display.html?Name=TMDB>

=head1 SEE ALSO

=over

=item L<The MovieDB API|http://docs.themoviedb.apiary.io/>

=item L<API Support|https://www.themoviedb.org/talk/category/5047958519c29526b50017d6>

=item L<WWW::TMDB::API>

=back

>>>>>>> 02cb4241e8ca64ec24b6fc3827dac2b1d4db489e
=head1 AUTHOR

Mithun Ayachit C<mithun@cpan.org>

=head1 LICENSE AND COPYRIGHT

<<<<<<< HEAD
Copyright (c) 2012, Mithun Ayachit. All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. See L<perlartistic>.
=======
Copyright (c) 2013, Mithun Ayachit. All rights reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>.
>>>>>>> 02cb4241e8ca64ec24b6fc3827dac2b1d4db489e

=cut
