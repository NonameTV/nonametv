package NonameTV::Importer::Kanal5_mail;

use strict;
use warnings;

use utf8;

use DateTime;
use XML::LibXML;
use File::Slurp;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f/;

use NonameTV::Importer::Kanal5_util qw/ParseData/;

use NonameTV::Importer::BaseUnstructured;

use base 'NonameTV::Importer::BaseUnstructured';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContent
{
  my $self = shift;
  my( $filename, $cref, $chd ) = @_;

  $self->{fileerror} = 0;

  my $dsh = $self->{datastorehelper};

  # We have no category information for data delivered via e-mail.
  my $cat = {};

  return ParseData( $filename, $cref, $chd, $cat, $dsh, 1 );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
