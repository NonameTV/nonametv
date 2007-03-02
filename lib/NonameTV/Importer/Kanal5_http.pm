package NonameTV::Importer::Kanal5_http;

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use POSIX qw/floor/;

use NonameTV qw/MyGet norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer::Kanal5_util qw/ParseData/;
use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "Kanal5_http";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $cat = $self->FetchCategories( $batch_id, $chd );
  my $dsh = $self->{datastorehelper};

  return ParseData( $batch_id, $cref, $chd, $cat, $dsh, 0 );
}

# Fetch the association between title and category/program_type for a
# specific channel and day. This is done by fetching the listings for each
# category during the day and looking at which titles are returned.
sub FetchCategories
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  $batch_id .= ".xml";

  my $ds = $self->{datastore};

  my $cat = {};

  info( "$batch_id: Fetching categories" );

  my( $content, $code ) = $self->FetchData( $batch_id , $data );
            
  if( not defined( $content ) )
  {
    error( "$batch_id: Failed to fetch category-listings" );
    return {};
  }
   
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($content); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse: $@" );
    return $cat;
  }
  
  # Find all "TRANSMISSION"-entries.
  my $ns = $doc->find( "//TRANSMISSION" );
  
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No programme entries found" );
    return $cat;
  }
  
  foreach my $tm ($ns->get_nodelist)
  {
    my $title =norm( $tm->findvalue(
      './/PRODUCTTITLE[.//PSIPRODUCTTITLETYPE/@oid="131708570"][1]/@title') );
    
    if( $title =~ /^\s*$/ )
    {
      # Some entries lack a title. 
      # Fallback to the title in the TRANSMISSION-tag.
      $title = norm( $tm->findvalue( '@title' ) );
    }
    
    my $category = norm( $tm->findvalue( './/CATEGORY/@name' ) );
    
    if( $title =~ /^\s*$/ )
    {
      # No title. Skip it.
      next;
    }
    
    if( $category =~ /^\s*$/ )
    {
      # No title. Skip it.
      next;
    }
    
    $cat->{$title} = $category;
  }

  return $cat;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week, $ext ) = ($batch_id =~ /_20(\d+)-(\d+)(.*)/);

  $ext = ".doc" unless $ext;

  my $url = sprintf( "%stab%02d%02d%s", $self->{UrlRoot}, $week, $year, $ext );

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}
  
1;
