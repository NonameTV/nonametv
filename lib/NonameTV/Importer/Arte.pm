package NonameTV::Importer::Arte;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. The parsing of the
data relies only on the text-content of the document, not on the
formatting.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet File2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/progress error/;
use NonameTV::Importer::Arte_util qw/ImportFull/;
use NonameTV::Importer::BaseFile;
use base 'NonameTV::Importer::BaseFile';

sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);
  

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  return if( $file !~ /\.doc$/i );

  my $doc = File2Xml( $file );

  if( not defined( $doc ) )
  {
    error( "Arte: $chd->{xmltvid} Failed to parse $file" );
    return;
  }

  ImportFull( $file, $doc, $chd, $self->{datastorehelper} );
}


1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
