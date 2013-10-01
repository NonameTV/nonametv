package TMDB::Search;

#######################
# LOAD CORE MODULES
#######################
use strict;
use warnings FATAL => 'all';
use Carp qw(croak carp);

#######################
<<<<<<< HEAD
=======
# LOAD CPAN MODULES
#######################
use Params::Validate qw(validate_with :types);
use Object::Tiny qw(session include_adult max_pages);

#######################
>>>>>>> 02cb4241e8ca64ec24b6fc3827dac2b1d4db489e
# LOAD DIST MODULES
#######################
use TMDB::Session;

#######################
# PUBLIC METHODS
#######################

<<<<<<< HEAD
## Constructor
sub new {
    my $class = shift;
    my $args  = shift;

    my $self = {};
    bless $self, $class;
    $self->{_session} = $args->{session} || croak "Session not provided";
    return $self;
} ## end sub new

## Search Movies
#   Provides searching by title+year
sub movie {
    my $self = shift;
    my @args = @_;

    my ( $title, $year );
    if ( ref $args[0] eq 'HASH' ) {
        $title = $args[0]->{name} if $args[0]->{name};
        $year  = $args[0]->{year} if $args[0]->{year};
    }
    else { $title = $args[0] }

    # title is required
    croak "No search title provided" unless $title;

    # Check if title contains year
    if ( not $year ) {
        if ( $title =~ s{\(\s*(\d{4})\s*\)$}{}x ) { $year = $1; }
    }

    # Build parameters to pass to session
    my $talk_args = {
        method => 'Movie.search',
        params => $title,
    };
    $talk_args->{params} .= "+${year}" if $year;

    # Fetch results
    my $results = $self->_session->talk($talk_args) or return;

    # Process results
    return _parse_movie_result($results);
} ## end sub movie

## Search Person
sub person {
    my $self = shift;
    my $name = shift || croak "Person's name is not provided";

    # Build parameters to pass to session
    my $talk_args = {
        method => 'Person.search',
        params => $name
    };

    # Fetch results
    my $results = $self->_session->talk($talk_args) or return;

    # Process results
    my @persons;
    foreach my $result ( @{$results} ) {
        my %person;
        $person{name} = $result->{name};
        $person{id}   = $result->{id};
        $person{url}  = $result->{url};
        foreach my $image ( @{ $result->{profile} } ) {
            next unless ( $image->{image}->{size} eq 'thumb' );
            $person{thumb} = $image->{image}->{url};
        }
        push @persons, \%person;
    } ## end foreach my $result ( @{$results...})

    return @persons;
} ## end sub person

## Search IMDB
sub imdb {
    my $self = shift;
    my $imdb_id = shift || croak "IMDB ID is required";

    # Build parameters to pass to session
    my $talk_args = {
        method => 'Movie.imdbLookup',
        params => $imdb_id
    };

    # Fetch results
    my $results = $self->_session->talk($talk_args) or return;

    # Process results
    return _parse_movie_result($results);
} ## end sub imdb

## Search DVDID
sub dvdid {
    my $self = shift;
    my $dvdid = shift || croak "DVDID not provided";

    # Build parameters to pass to session
    my $talk_args = {
        method => 'Media.getInfo',
        params => $dvdid
    };

    # Fetch results
    my $results = $self->_session->talk($talk_args) or return;

    # Process results
    return _parse_movie_result($results);
} ## end sub dvdid

## Search by file
sub file {
    my $self = shift;
    my $file = shift || croak "Filename not provided";

    # Build parameters to pass to session
    my $talk_args = {
        method => 'Media.getInfo',
        params => join( '/', OpenSubtitlesHash($file), -s $file ),
    };

    # Fetch results
    my $results = $self->_session->talk($talk_args) or return;

    # Process results
    return _parse_movie_result($results);
} ## end sub file

#######################
# PRIVATE METHODS
#######################

## Session
sub _session { return shift->{_session}; }

## Search result
sub _parse_movie_result {
    my $results = shift;
    my @movies;
    foreach my $result ( @{$results} ) {
        my %movie;
        $movie{name} = $result->{name};
        $movie{year} = $result->{released};
        $movie{year} =~ s{\-\d{2}\-\d{2}$}{}x;
        $movie{id}  = $result->{id};
        $movie{url} = $result->{url};
        foreach my $poster ( @{ $result->{posters} } ) {
            next unless ( $poster->{image}->{size} eq 'thumb' );
            $movie{thumb} = $poster->{image}->{url};
            last;
        }
        push @movies, \%movie;
    } ## end foreach my $result ( @{$results...})
    return @movies;
} ## end sub _parse_movie_result

## File hash
#   Hashing source code from 'OpenSubtitles'
#   http://trac.opensubtitles.org/projects/opensubtitles/wiki/HashSourceCodes#Perl
sub OpenSubtitlesHash {
    my $filename = shift or croak("Need video filename");

    open my $handle, "<", $filename or croak $!;
    binmode $handle;

    my $fsize = -s $filename;

    my $hash = [ $fsize & 0xFFFF, ( $fsize >> 16 ) & 0xFFFF, 0, 0 ];

    $hash = AddUINT64( $hash, ReadUINT64($handle) ) for ( 1 .. 8192 );

    my $offset = $fsize - 65536;
    seek( $handle, $offset > 0 ? $offset : 0, 0 ) or croak $!;

    $hash = AddUINT64( $hash, ReadUINT64($handle) ) for ( 1 .. 8192 );

    close $handle or croak $!;
    return UINT64FormatHex($hash);
} ## end sub OpenSubtitlesHash

sub ReadUINT64 {
    read( $_[0], my $u, 8 );
    return [ unpack( "vvvv", $u ) ];
}

sub AddUINT64 {
    my $o = [ 0, 0, 0, 0 ];
    my $carry = 0;
    for my $i ( 0 .. 3 ) {
        if ( ( $_[0]->[$i] + $_[1]->[$i] + $carry ) > 0xffff ) {
            $o->[$i] += ( $_[0]->[$i] + $_[1]->[$i] + $carry ) & 0xffff;
            $carry = 1;
        }
        else {
            $o->[$i] += ( $_[0]->[$i] + $_[1]->[$i] + $carry );
            $carry = 0;
        }
    } ## end for my $i ( 0 .. 3 )
    return $o;
} ## end sub AddUINT64

sub UINT64FormatHex {
    return sprintf( "%04x%04x%04x%04x",
        $_[0]->[3], $_[0]->[2], $_[0]->[1], $_[0]->[0] );
}
=======
## ====================
## Constructor
## ====================
sub new {
    my $class = shift;
    my %opts  = validate_with(
        params => \@_,
        spec   => {
            session => {
                type => OBJECT,
                isa  => 'TMDB::Session',
            },
            include_adult => {
                type      => SCALAR,
                optional  => 1,
                default   => 'false',
                callbacks => {
                    'valid flag' => sub { lc $_[0] eq 'true' or lc $_[0] eq 'false' }
                },
            },
            max_pages => {
                type      => SCALAR,
                optional  => 1,
                default   => 1,
                callbacks => {
                    'integer' => sub { $_[0] =~ m{\d+} },
                },
            },
        },
    );

    my $self = $class->SUPER::new(%opts);
  return $self;
} ## end sub new

## ====================
## Search Movies
## ====================
sub movie {
    my ( $self, $string ) = @_;

    # Get Year
    my $year;
    if ( $string =~ m{.+\((\d{4})\)$} ) {
        $year = $1;
        $string =~ s{\($year\)$}{};
    } ## end if ( $string =~ m{.+\((\d{4})\)$})

    # Trim
    $string =~ s{(?:^\s+)|(?:\s+$)}{};

    # Search
    my $params = {
        query         => $string,
        include_adult => $self->include_adult,
    };
    $params->{language} = $self->session->lang if $self->session->lang;
    $params->{year} = $year if $year;

    warn "DEBUG: Searching for $string\n" if $self->session->debug;
  return $self->_search(
        {
            method => 'search/movie',
            params => $params,
        }
    );
} ## end sub movie

## ====================
## Search Person
## ====================
sub person {
    my ( $self, $string ) = @_;

    warn "DEBUG: Searching for $string\n" if $self->session->debug;
  return $self->_search(
        {
            method => 'search/person',
            params => {
                query => $string,
            },
        }
    );
} ## end sub person

## ====================
## Search Companies
## ====================
sub company {
    my ( $self, $string ) = @_;

    warn "DEBUG: Searching for $string\n" if $self->session->debug;
  return $self->_search(
        {
            method => 'search/company',
            params => {
                query => $string,
            },
        }
    );
} ## end sub company

## ====================
## Search Lists
## ====================
sub list {
    my ( $self, $string ) = @_;

    warn "DEBUG: Searching for $string\n" if $self->session->debug;
  return $self->_search(
        {
            method => 'search/list',
            params => {
                query => $string,
            },
        }
    );
} ## end sub list

## ====================
## Search Keywords
## ====================
sub keyword {
    my ( $self, $string ) = @_;

    warn "DEBUG: Searching for $string\n" if $self->session->debug;
  return $self->_search(
        {
            method => 'search/keyword',
            params => {
                query => $string,
            },
        }
    );
} ## end sub keyword

## ====================
## Search Collection
## ====================
sub collection {
    my ( $self, $string ) = @_;

    warn "DEBUG: Searching for $string\n" if $self->session->debug;
  return $self->_search(
        {
            method => 'search/collection',
            params => {
                query => $string,
            },
        }
    );
} ## end sub collection

## ====================
## LISTS
## ====================

# Latest
sub latest { return shift->session->talk( { method => 'movie/latest', } ); }

# Upcoming
sub upcoming {
    my ($self) = @_;
  return $self->_search(
        {
            method => 'movie/upcoming',
            params => {
                language => $self->session->lang ? $self->session->lang : undef,
            },
        }
    );
} ## end sub upcoming

# Now Playing
sub now_playing {
    my ($self) = @_;
  return $self->_search(
        {
            method => 'movie/now-playing',
            params => {
                language => $self->session->lang ? $self->session->lang : undef,
            },
        }
    );
} ## end sub now_playing

# Popular
sub popular {
    my ($self) = @_;
  return $self->_search(
        {
            method => 'movie/popular',
            params => {
                language => $self->session->lang ? $self->session->lang : undef,
            },
        }
    );
} ## end sub popular

# Top rated
sub top_rated {
    my ($self) = @_;
  return $self->_search(
        {
            method => 'movie/top-rated',
            params => {
                language => $self->session->lang ? $self->session->lang : undef,
            },
        }
    );
} ## end sub top_rated

# Popular People
sub popular_people {
    my ($self) = @_;
  return $self->_search(
        {
            method => 'person/popular',
            params => {
                language => $self->session->lang ? $self->session->lang : undef,
            },
        }
    );
} ## end sub popular_people

# Latest Person
sub latest_person {
  return shift->session->talk(
        {
            method => 'person/latest',
        }
    );
} ## end sub latest_person

#######################
# DISCOVER
#######################
sub discover {
    my ( $self, @args ) = @_;
    my %options = validate_with(
        params => [@args],
        spec   => {
            sort_by => {
                type      => SCALAR,
                optional  => 1,
                default   => 'popularity.asc',
                callbacks => {
                    'valid flag' => sub {
                             ( lc $_[0] eq 'vote_average.desc' )
                          or ( lc $_[0] eq 'vote_average.asc' )
                          or ( lc $_[0] eq 'release_date.desc' )
                          or ( lc $_[0] eq 'release_date.asc' )
                          or ( lc $_[0] eq 'popularity.desc' )
                          or ( lc $_[0] eq 'popularity.asc' );
                    },
                },
            },
            year => {
                type     => SCALAR,
                optional => 1,
                regex    => qr/^\d{4}\-\d{2}\-\d{2}$/
            },
            'release_date.gte' => {
                type     => SCALAR,
                optional => 1,
                regex    => qr/^\d{4}\-\d{2}\-\d{2}$/
            },
            'release_date.lte' => {
                type     => SCALAR,
                optional => 1,
                regex    => qr/^\d{4}\-\d{2}\-\d{2}$/
            },
            'vote_count.gte' => {
                type     => SCALAR,
                optional => 1,
                regex    => qr/^\d+$/
            },
            'vote_average.gte' => {
                type      => SCALAR,
                optional  => 1,
                regex     => qr/^\d{1,2}\.\d{1,}$/,
                callbacks => {
                    average => sub { $_[0] <= 10 },
                },
            },
            with_genres => {
                type     => SCALAR,
                optional => 1,
            },
            with_companies => {
                type     => SCALAR,
                optional => 1,
            },
        },
    );

  return $self->_search(
        {
            method => 'discover/movie',
            params => {
                language => $self->session->lang ? $self->session->lang : undef,
                include_adult => $self->include_adult,
                %options,
            },
        }
    );

} ## end sub discover

#######################
# PRIVATE METHODS
#######################

## ====================
## Search
## ====================
sub _search {
    my $self = shift;
    my $args = shift;
    $args->{max_pages} = $self->max_pages();
  return $self->session->paginate_results($args);
} ## end sub _search
>>>>>>> 02cb4241e8ca64ec24b6fc3827dac2b1d4db489e

#######################
1;
