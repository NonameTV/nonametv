package NonameTV::TemplateLinkify;

use strict;
use warnings;

use NonameTV::Log qw/w/;
use Template::Plugin::Filter;

use base qw( Template::Plugin::Filter );

sub init {
    my $self = shift;

    $self->{ _DYNAMIC } = 1;

    # first arg can specify filter name
    $self->install_filter($self->{ _ARGS }->[0] || 'linkify');

    eval "use URI::Find;";
    if( !$@ ){
        $self->{finder} = URI::Find->new(sub {
            my($uri, $orig_uri) = @_;
            return qq|<a href="$uri">$orig_uri</a>|;
        });
    } else {
      w( "URI::Find not found, not changing URLs to links" );
    }

    return $self;
}

sub filter {
    my ($self, $text, $args, $config) = @_;

    if( defined( $self->{finder} ) ) {
        $self->{finder}->find( \$text );
    }

    return $text;
}

1;
