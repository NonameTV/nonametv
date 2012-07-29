package NonameTV::Importer::CanalPlusPPV;

use strict;
use warnings;

=pod

Importer for data for pay-per-view channels from Canal+. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.

The downloaded file always contains data for all PPV-channels.
FilterContent is used to filter out the relevant data.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/w f progress error/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    # There is no stop-times or program-lengths in the data and programs
    # are far apart. Therefore, we need to guess the length.
    defined( $self->{ProgramLength} ) or die "You must specify ProgramLength";

    # Canal Plus' webserver returns the following date in some headers:
    # Fri, 31-Dec-9999 23:59:59 GMT
    # This makes Time::Local::timegm and timelocal print an error-message
    # when they are called from HTTP::Date::str2time.
    # Therefore, I have included HTTP::Date and modified it slightly.

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  # Find the first day in the given week.
  # Copied from
  # http://www.nntp.perl.org/group/perl.datetime/5417?show_headers=1 
  my $ds = DateTime->new( year=>$year, day => 4 );
  $ds->add( days => $week * 7 - $ds->day_of_week - 6 );
  
  my $url = $self->{UrlRoot} .
    'date=' . $ds->ymd("-") . '&days=6';

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  if( $$cref eq "" ) {
    return (undef, "No data found." );
  }

  my $channelName = $chd->{grabber_info};

  my $doc = ParseXml( $cref );
  
  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  # Find all "schedule"-entries.
  my $ns = $doc->find( "//schedule" );

  if( $ns->size() == 0 ) {
    return (undef, "No schedules found" );
  }

  foreach my $ch ($ns->get_nodelist) {
    my $currname = $ch->findvalue( '@channelName' );
    if( $currname ne $channelName ) {
      $ch->unbindNode();
    }
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
 
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }
  
  my $ns = $doc->find( "//schedule" );

  if( $ns->size() == 0 ) {
    # It is pretty common for a schedule to be empty. Do not treat this
    # as an error.
    return 1;
  }
  
  foreach my $sc ($ns->get_nodelist) {
    # Sanity check. 
    # What does it mean if there are several programs?
    if( $sc->findvalue( 'count(.//program)' ) != 1 ) {
      w "Wrong number of Programs for Schedule " .
	  $sc->findvalue( '@calendarDate' );
      return 0;
    }
	  
    my $start = $self->create_dt( $sc->findvalue( './@calendarDate' ) );
    if( not defined $start ) {
      w "Invalid starttime '" 
	  . $sc->findvalue( './@calendarDate' ) . "'. Skipping.";
      next;
    }

    my $end = $start->clone->add( hours => $self->{ProgramLength} );
    my $title = $sc->findvalue( './program/@title' );
    my $ce = {
      channel_id  => $chd->{id},
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
      end_time    => $end->ymd("-") . " " . $end->hms(":"),
      title       => $title,
      category    => 'Sports',
    };

    $ds->AddProgramme( $ce );
  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my( $date, $time ) = split( 'T', $str );

  if( not defined $time )
  {
    return undef;
  }
  my( $year, $month, $day ) = split( '-', $date );
  
  # Remove the dot and everything after it.
  $time =~ s/\..*$//;
  
  my( $hour, $minute, $second ) = split( ":", $time );
  
  if( $second > 59 ) {
    return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/Stockholm',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

sub extract_extra_info
{
  my $self = shift;
  my( $ce ) = @_;
  
}
    
1;
