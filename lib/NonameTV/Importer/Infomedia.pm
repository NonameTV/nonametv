package NonameTV::Importer::Infomedia;

=pod

This importer imports data from www.infomedia.lu. The data is fetched
as one html-file per day and channel.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet norm Html2Xml ParseXml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "Infomedia";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  # Date should be in format yyyymmdd.
  $date =~ tr/-//d;

  my $u = URI->new($self->{UrlRoot});
  $u->query_form( {
    chn => $chd->{grabber_info},
    date => $date,
  });

  print "URL: " . $u->as_string() . "\n";
  return( $u->as_string(), undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $doc = Html2Xml( $$cref );
  
  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  } 

  my $ns = $doc->find( "//@*" );

  # Remove all attributes that we ignore anyway.
  foreach my $attr ($ns->get_nodelist) {
    if( $attr->nodeName() ne "class" ) {
      $attr->unbindNode();
    }
  }

  my $str = $doc->toString(1);

  return( \$str, undef );
}

sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) )
  {
    error( "$batch_id: Failed to parse." );
    return 0;
  }
  
  my $ns = $doc->find( '//table[@class="table_schedule"]//tr' );
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No data found" );
    return 0;
  }
  
  $dsh->StartDate( $date, "00:00" );
  
  foreach my $pgm ($ns->get_nodelist)
  {
    # The data consists of alternating rows with time+title or description.
    my $time = norm( $pgm->findvalue( './/p[@class="hour"]//text()' ) );
    next if $time eq "";

    my $title = $pgm->findvalue( './/p[@class="prog"]//text()' );
    my $desc      = $pgm->findvalue( 'following-sibling::tr[1]' . 
                                     '//p[@class="synopsis"]//text()' );


    my( $starttime ) = ( $time =~ /(\d+:\d+)/);
    
    my $ce =  {
      start_time  => $starttime,
      title       => norm($title),
      description => norm($desc),
    };
    
    extract_extra_info( $ce );
    $dsh->AddProgramme( $ce );
  }
  
  return 1;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $date ) = ($batch_id =~ /_(.*)/);

  # Date should be in format yyyymmdd.
  $date =~ tr/-//d;

  my $u = URI->new($self->{UrlRoot});
  $u->query_form( {
    chn => $data->{grabber_info},
    date => $date,
  });
  progress("Infomedia: fetching from: $u");

  my( $content, $code ) = MyGet( $u->as_string );

  return( $content, $code );
}

sub extract_extra_info
{
  my( $ce ) = shift;

}

1;
