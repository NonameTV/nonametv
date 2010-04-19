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

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

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

  my $today = DateTime->today( time_zone => 'Europe/Zagreb' );

  # the url is in format 'http://www.rtl.hr/raspored/xmltv/0'
  # where '0' at the end is for today, 1 for tomorrow, etc.

  my( $year, $month, $day ) = ( $objectname =~ /_(\d+)-(\d+)-(\d+)$/ );
  my $dt = DateTime->new(
                          year  => $year,
                          month => $month,
                          day   => $day,
                          time_zone   => 'Europe/Zagreb',
  );

#  if( $dt eq $today ){
#print "DANAS........\n";
#  }

  #my $dur = $dt->subtract_datetime($today);
  my $dur = $dt - $today;

#print "OBJ $objectname\n";
#print "DT  $dt\n";
#print "TOD $today\n";
#print "DUR $dur\n";
#print "CAL " . $dur->calendar_duration . "\n";
#print "DYS " . $dur->delta_days . "\n";
#print "MNS " . $dur->delta_minutes . "\n";

  if( $dur->is_negative ){
    progress( "RTLTV: $objectname: Skipping date in the past " . $dt->ymd() );
    return( undef, undef );
  }

  my $url = $self->{UrlRoot} . "/" . $dur->delta_days;
  progress( "RTLTV: $objectname: Fetching data from $url" );

  return( [$url], undef );
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  $ds->{SILENCE_END_START_OVERLAP}=1;

  my( $date ) = ($batch_id =~ /_(.*)$/);

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
  
  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );

  # Start date
  $dsh->StartDate( $date , "05:00" );
  progress("RTLTV: $chd->{xmltvid}: Date is: $date");

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
    ( $date, $time ) = ParseDateTime( $start );
    next if( ! $date );
    next if( ! $time );

    my $title = $sc->getElementsByTagName( 'title' );
    next if( ! $title );

#    my $genre = $sc->getElementsByTagName( 'category' );
#    my $description = $sc->getElementsByTagName( 'desc' );
#    my $url = $sc->getElementsByTagName( 'url' );

    progress("RTLTV: $chd->{xmltvid}: $time - $title");

    my $ce = {
      channel_id => $chd->{id},
      start_time => $time,
      title => norm($title),
    };

#    $ce->{description} = $description if $description;

#    if( $genre ){
#      my($program_type, $category ) = $ds->LookupCat( "RTLTV", norm($genre) );
#      AddCategory( $ce, $program_type, $category );
#    }

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
