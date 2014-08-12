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
use JSON::Any;
use Data::Dumper;
use Encode qw();
use HTTP::Tiny qw();
use URI::Encode qw();
use Params::Validate qw(validate_with :types);
use Locale::Codes::Language qw(all_language_codes);
use Object::Tiny qw(apikey apiurl lang debug client encoder json);
use WWW::Mechanize::Cached;
use CHI;

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

#######################
# PUBLIC METHODS
#######################

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
            cache => {
                type     => SCALAR,
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
                isa      => 'WWW::Mechanize::Cached',
                optional => 1,
                default  => WWW::Mechanize::Cached->new(
                    cache => CHI->new( driver => 'File',
                             root_dir => '/nonametv/contentcache/Tmdb3',
                             expires_in => '1 month', expires_variance => 0.25 ), agent => $default_ua, headers => $default_headers
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

    #print Dumper($response, $self->client->is_cached($url));

    # Debug
    if ( $self->debug ) {
        warn "DEBUG: Got a successful response\n" if $response->{success};
        warn "DEBUG: Got Status -> $response->{status}\n";
        warn "DEBUG: Got Reason -> $response->{reason}\n"   if $response->{reason};
        warn "DEBUG: Got Content -> $response->{_content}\n" if $response->{content};
    } ## end if ( $self->debug )

    # Return
  return unless $response->{_msg};  # Error
    if ( $args->{want_headers} and exists $response->{_request}->{_headers} ) {

        # Return headers only
      return $response->{_request}->{_headers};
    } ## end if ( $args->{want_headers...})
  return unless $response->{_content};  # Blank Content

  if($response->{_content} !~ /^</ ) {
    return $self->json->decode( Encode::decode( 'utf-8-strict', $response->{_content} ) );  # Real Response
  } else {
    # Probably want to remove that file from cache when this happened than just return nothing.
    # This is what happens when you do too many api requests
    warn "Not an actual JSON. HTML found.";
    return;
  }

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

#######################
1;
