package NonameTV::Importer::Kanal5_http;

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use POSIX qw/floor/;

use NonameTV qw/MyGet Word2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::Kanal5_util qw/ParseData/;
use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    
    # use augment
    $self->{datastore}->{augment} = 1;

    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ($objectname =~ /_20(\d+)-(\d+)/);

  my $url = sprintf( "%stab%02d%02d.doc", $self->{UrlRoot}, $week, $year );

  return( $url, undef );
}

sub ContentExtension {
  return 'doc';
}

sub FilteredExtension {
  return 'xml';
}


sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  if( $$cref =~ /Sidan kunde tyv\S*rr inte hittas/ ) {
    return( undef, "Failed to download" );
  }

  my $doc = Word2Xml( $$cref );
  my $str = $doc->toString(1);

  return( \$str, undef );
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

#  my $cat = $self->FetchCategories( $batch_id, $chd );
  my $dsh = $self->{datastorehelper};

  return ParseData( $batch_id, $cref, $chd, undef, $dsh, 0 );
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

#  info( "$batch_id: Fetching categories" );

  my( $content, $code ) = $self->FetchData( $batch_id , $data );
            
  if( not defined( $content ) )
  {
    error( "$batch_id: Failed to fetch category-listings" );
    return {};
  }

  if( $content =~ /Sidan kunde tyv\S*rr inte hittas/ ) {
    error( "$batch_id: Failed to download" );
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

1;
