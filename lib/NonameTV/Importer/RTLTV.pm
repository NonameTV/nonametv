package NonameTV::Importer::RTLTV;

use strict;
use warnings;

=pod

Importer for data from RTLTV. 
The downloaded files is in xml-format.

Features:

=cut

use DateTime;
use DateTime::Duration;
use XML::LibXML;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Zagreb" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $url = $self->{UrlRoot} . "/" . $chd->{grabber_info};
  progress( "RTLTV: $chd->{xmltvid}: Fetching data from $url" );

  return( [$url], undef );
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  #$ds->{SILENCE_END_START_OVERLAP}=1;


  # clean some characters from xml that can not be parsed
  my $xmldata = $$cref;
  $xmldata =~ s/\&bdquo;/\"/;
  $xmldata =~ s/&amp;bdquo;/\"/;
  $xmldata =~ s/&nbsp;//;
  $xmldata =~ s/&scaron;//;
  $xmldata =~ s/&eacute;//;
  $xmldata =~ s/ \& / and /g;

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($xmldata); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }
  
  my $date;
  my $currdate = "x";

  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );
  if( $ns->size() == 0 ) {
    error( "RTLTV: $chd->{xmltvid}: No 'programme' blocks found" ) ;
    return 0;
  }
  progress( "RTLTV: $chd->{xmltvid}: " . $ns->size() . " programme blocks found" );

  foreach my $sc ($ns->get_nodelist)
  {
    
    #
    # start time
    #
    my $start = $sc->findvalue( './@start' );
    if( not defined $start )
    {
      error( "$batch_id: Invalid starttime '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }

    my $time;

    #
    # date and time
    #
    ( $date, $time ) = ParseDateTime( $start );
    next if( ! $date );
    next if( ! $time );

    if( $date ne $currdate ) {

      $dsh->StartDate( $date , "06:00" );
      $currdate = $date;

      progress("RTLTV: $chd->{xmltvid}: Date is: $date");
    }

    my $title = $sc->findvalue( 'title' );
    next if( ! $title );

    my $genre = $sc->findvalue( 'category' );
    my $description = $sc->findvalue( 'desc' );
    my $url = $sc->findvalue( 'url' );

    progress("RTLTV: $chd->{xmltvid}: $time - $title");

    my $ce = {
      channel_id => $chd->{id},
      start_time => $time,
      title => norm($title),
    };

    $ce->{description} = $description if $description;
    $ce->{url} = $url if $url;

    if( $genre ){
      my($program_type, $category ) = $ds->LookupCat( "RTLTV", norm($genre) );
      AddCategory( $ce, $program_type, $category );
    }

    $dsh->AddProgramme( $ce );
  }

  # Success
  return 1;
}

sub ParseDateTime
{
  my( $text ) = @_;

  my( $year, $month, $day, $hour, $min, $sec ) = ( $text =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s+/ );

  return( $year . "-" . $month . "-" . $day , $hour . ":" . $min );
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my $url = $self->{UrlRoot};
  progress("RTLTV: fetching data from $url");

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

1;
