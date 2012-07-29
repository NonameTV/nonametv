package NonameTV::Importer::SR;

=pod

This importer imports data from www.sr.se. The data is fetched
as one html-file per day and channel.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet norm Html2Xml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "SR";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  my $doc = Html2Xml( $$cref );
  
  if( not defined( $doc ) )
  {
    error( "$batch_id: Failed to parse." );
    return 0;
  }
  
  my $ns = $doc->find( '//tr[td/@valign="top"]' );
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No data found" );
    return 0;
  }
  
#  $dsh->StartDate( $date, "00:00" );
  
  foreach my $pgm ($ns->get_nodelist)
  {
    # The data consists of alternating rows with time or title+description.
    my $time = norm( $pgm->findvalue( './td[1]//text()' ) );

    my $titledesc = $pgm->findvalue( './td[2]//text()' );

    $titledesc =~ s/^\s*//;
    $titledesc .= "\n";

    my( $title, $desc ) = ($titledesc =~ /^([^\n]*)\n(.*)/);
    $title = norm( $title );
    $desc = norm( $desc );

    print "$time $title\n:$desc\n";
  }

#    my( $starttime ) = ( $time =~ /(\d+:\d+)/);
#    
#    my $ce =  {
#      start_time  => $starttime,
#      title       => norm($title),
#      description => norm($desc),
#   };
    
#    extract_extra_info( $ce );
#    $dsh->AddProgramme( $ce );
#  }
  
  return 1;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $date ) = ($batch_id =~ /_(.*)/);

  # Date should be in format yymmdd.
  $date =~ tr/-//d;
  $date = substr( $date, 2 );

  my $url = $self->{UrlRoot} . $data->{grabber_info} . "/manus/m2006/m" . 
    $date . ".htm";

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub extract_extra_info
{
  my( $ce ) = shift;

}

1;
