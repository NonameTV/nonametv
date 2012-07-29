package NonameTV::Importer::MojTV;

use strict;
use warnings;

=pod

Importer for data from MojTV. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.

=cut

use DateTime;
use XML::LibXML;
use Switch;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/progress w error/;
use NonameTV::Importer::Xmltv_util qw/ParseData/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ( $objectname =~ /_(\d+)-(\d+)-(\d+)$/ );

  my $url = sprintf( "%s/%s_%02d-%02d-%02d.xml", $self->{UrlRoot}, $chd->{grabber_info}, $year, $month, $day );

  progress("MojTV: fetching data from $url");

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  # turn right single ' into '
  $$cref =~ s|&#8217;|'|g;

  my $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//tv" );
  if( $ns->size() == 0 ) {
    return (undef, "No xmltv data found" );
  }
  
  my $str = $doc->toString( 1 );

  return( \$str, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};

  return ParseData ($batch_id, $cref, $chd, $ds);
}

1;
