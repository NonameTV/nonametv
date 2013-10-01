package TMDB::Session;

#######################
# LOAD CORE MODULES
#######################
use strict;
use warnings FATAL => 'all';
use Carp qw(croak carp);

#######################
# LOAD CPAN MODULES
#######################
<<<<<<< HEAD
use Encode qw();
use LWP::UserAgent;
use JSON::Any;
=======
use JSON::Any;
use Encode qw();
use HTTP::Tiny qw();
use URI::Encode qw();
use Params::Validate qw(validate_with :types);
use Locale::Codes::Language qw(all_language_codes);
use Object::Tiny qw(apikey apiurl lang debug client encoder json);

#######################
# PACKAGE VARIABLES
#######################

# Valid language codes
my %valid_lang_codes = map { $_ => 1 } all_language_codes('alpha-2');

# Default Headers
my $default_headers = {
    'Accept'       => 'application/json',
    'Content-Type' => 'application/json',
};

# Default User Agent
my $default_ua = 'perl-tmdb-client';
>>>>>>> 02cb4241e8ca64ec24b6fc3827dac2b1d4db489e

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
    return $self->_init($args);
} ## end sub new

## Talk
sub talk {
    my $self = shift;
    my $args = shift;

    my $get = join( '/',
        $self->api_url, $self->api_version, $args->{method},
        $self->lang,    $self->api_type,    $self->api_key,
        $args->{params} );

    my $response = $self->ua->get($get);
    return unless $response->is_success();

    my $perl_ref =
        JSON::Any->new()
        ->Load(
        Encode::encode( 'utf-8-strict', $response->decoded_content ) );
    return if not $perl_ref->[0];
    return if ( $perl_ref->[0] =~ /nothing\s*found/ix );
    return $perl_ref;
} ## end sub talk

## Accessors
sub api_key     { return shift->{_api_key}; }
sub api_type    { return shift->{_api_type}; }
sub api_url     { return shift->{_api_url}; }
sub api_version { return shift->{_api_version}; }
sub lang        { return shift->{_lang}; }
sub ua          { return shift->{_ua}; }

#######################
# PRIVATE METHODS
#######################

## Initialize
sub _init {
    my $self = shift;
    my $args = shift;

    # Default User Agent
    my $ua = LWP::UserAgent->new( agent => "perl-tmdb/" . $args->{_VERSION} );

    # Required Args
    $self->{_api_key} = $args->{api_key} || croak "API key is not provided";

    # Optional Args
    $self->{_ua}   = $args->{ua}   || $ua;      # UserAgent
    $self->{_lang} = $args->{lang} || 'en-US';  # Language

    # Check user agent
    croak "LWP::UserAgent expected"
        unless $self->{_ua}->isa('LWP::UserAgent');

    # API settings
    $self->{_api_url}     = 'http://api.themoviedb.org';  # Base URL
    $self->{_api_version} = '2.1';                        # Version
    $self->{_api_type}    = 'json';                       # Always use JSON

    return $self;
} ## end sub _init
=======
## ====================
## Constructor
## ====================
sub new {
    my $class = shift;
    my %opts  = validate_with(
        params => \@_,
        spec   => {
            apikey => {
                type => SCALAR,
            },
            apiurl => {
                type     => SCALAR,
                optional => 1,
                default  => 'http://api.themoviedb.org/3',
            },
            lang => {
                type      => SCALAR,
                optional  => 1,
                callbacks => {
                    'valid language code' => sub { $valid_lang_codes{ lc $_[0] } },
                },
            },
            client => {
                type     => OBJECT,
                isa      => 'HTTP::Tiny',
                optional => 1,
                default  => HTTP::Tiny->new(
                    agent           => $default_ua,
                    default_headers => $default_headers,
                ),
            },
            encoder => {
                type     => OBJECT,
                isa      => 'URI::Encode',
                optional => 1,
                default  => URI::Encode->new(),
            },
            json => {
                type     => OBJECT,
                can      => 'Load',
                optional => 1,
                default  => JSON::Any->new(
                    utf8 => 1,
                ),
            },
            debug => {
                type     => BOOLEAN,
                optional => 1,
                default  => 0,
            },
        },
    );

    $opts{lang} = lc $opts{lang} if $opts{lang};
    my $self = $class->SUPER::new(%opts);
  return $self;
} ## end sub new

## ====================
## Talk
## ====================
sub talk {
    my ( $self, $args ) = @_;

    # Build Call
    my $url = $self->apiurl . '/' . $args->{method} . '?api_key=' . $self->apikey;
    if ( $args->{params} ) {
        foreach my $param ( sort { lc $a cmp lc $b } keys %{ $args->{params} } ) {
          next unless defined $args->{params}->{$param};
            $url .= "&${param}=" . $args->{params}->{$param};
        } ## end foreach my $param ( sort { ...})
    } ## end if ( $args->{params} )

    # Encode
    $url = $self->encoder->encode($url);

    # Talk
    warn "DEBUG: GET -> $url\n" if $self->debug;
    my $response = $self->client->get($url);

    # Debug
    if ( $self->debug ) {
        warn "DEBUG: Got a successful response\n" if $response->{success};
        warn "DEBUG: Got Status -> $response->{status}\n";
        warn "DEBUG: Got Reason -> $response->{reason}\n"   if $response->{reason};
        warn "DEBUG: Got Content -> $response->{content}\n" if $response->{content};
    } ## end if ( $self->debug )

    # Return
  return unless $response->{success};  # Error
    if ( $args->{want_headers} and exists $response->{headers} ) {

        # Return headers only
      return $response->{headers};
    } ## end if ( $args->{want_headers...})
  return unless $response->{content};  # Blank Content
  return $self->json->decode(
        Encode::decode( 'utf-8-strict', $response->{content} ) );  # Real Response
} ## end sub talk

## ====================
## PAGINATE RESULTS
## ====================
sub paginate_results {
    my ( $self, $args ) = @_;

    my $response = $self->talk($args);
    my $results = $response->{results} || [];

    # Paginate
    if (    $response->{page}
        and $response->{total_pages}
        and ( $response->{total_pages} > $response->{page} ) )
    {
        my $page_limit = $args->{max_pages} || '1';
        my $current_page = $response->{page};
        while ($page_limit) {
          last if ( $current_page == $page_limit );
            $current_page++;
            $args->{params}->{page} = $current_page;
            my $next_page = $self->talk($args);
            push @$results, @{ $next_page->{results} },;
          last if ( $next_page->{page} == $next_page->{total_pages} );
            $page_limit--;
        } ## end while ($page_limit)
    } ## end if ( $response->{page}...)

    # Done
  return @$results if wantarray;
  return $results;
} ## end sub paginate_results
>>>>>>> 02cb4241e8ca64ec24b6fc3827dac2b1d4db489e

#######################
1;
