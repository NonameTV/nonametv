package TMDB::Person;

#######################
# LOAD CORE MODULES
#######################
use strict;
use warnings FATAL => 'all';
use Carp qw(croak carp);

#######################
# LOAD DIST MODULES
#######################
use TMDB::Session;

#######################
# PUBLIC METHODS
#######################

## Constructor
sub new {
    my $class = shift;
    my $args  = shift;

    my $self = {};
    bless $self, $class;
    return $self->_init($args);
} ## end sub new

# Short Accessors
sub info       { return shift->{_info}; }
sub name       { return shift->info->{name}; }
sub birthplace { return shift->info->{birthplace}; }
sub url        { return shift->info->{url}; }
sub id         { return shift->info->{id}; }
sub birthday   { return shift->info->{birthday}; }
sub biography  { return shift->info->{biography}; }
sub bio        { return shift->biography(); }

# Filmography
sub movies {
    my $self = shift;
    my @movies;
    foreach ( @{ $self->info->{filmography} } ) { push @movies, $_->{name}; }
    return @movies;
} ## end sub movies

# Posters
sub posters {
    my $self = shift;
    my $size = shift || 'original';

    my @posters;
    foreach my $poster ( @{ $self->info->{profile} } ) {
        next unless ( $poster->{image}->{size} =~ m{$size} );
        push @posters, $poster->{image}->{url};
    }
    return @posters;
} ## end sub posters

#######################
# PRIVATE METHODS
#######################

## Initialize
sub _init {
    my $self = shift;
    my $args = shift;

    $self->{_session} = $args->{session};

    my $talk_args = {
        method => 'Person.getInfo',
        params => $args->{id},
    };

    # Get info
    my $results = $self->_session->talk($talk_args)
        or croak "No Person found. Please try searching instead";

    # Store info
    $self->{_info} = $results->[0];
    return $self;
} ## end sub _init

## Session
sub _session { return shift->{_session}; }

#######################
1;
