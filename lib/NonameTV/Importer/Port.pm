package NonameTV::Importer::Port;

use strict;
use warnings;

=pod

Import data from Xml-files downloaded from PORT.hu

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  return $self;
}

sub FetchDataFromSite
{

    my $self = shift;
    my( $batch_id, $data ) = @_;

    my $u = $self->{UrlRoot} . "/" . $data->{grabber_info};
    progress("Port: Fetching data from $u");

    my ( $content, $code ) = MyGet ( $u );

    return( $content, $code );
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  progress( "Port: $channel_xmltvid: Processing XML" );

  my $doc;
  my $xml = XML::LibXML->new;

  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" ) {
    error( "Port: $batch_id: Failed to parse $@" );
    return 0;
  }

  # find for how many channels this file has data
  my $channels = $doc->findnodes( "//Channel" );
  if( $channels->size() == 0 ) {
    error( "Port: $channel_xmltvid: $$cref: No channels found" ) ;
    return;
  }
  progress( "Port: $channel_xmltvid: found " . $channels->size() . " channels" );

  # browse through channels
  foreach my $chan ($channels->get_nodelist) {

    my $chan_id = $chan->getAttribute('Id');

    progress( "Port: $channel_xmltvid: browsing channel id $chan_id for EventDates" );

    # find all eventdates for this channel
    my $eventdates = $chan->findnodes( ".//EventDate" );
    if( $eventdates->size() == 0 ) {
      error( "Port: $channel_xmltvid: No EventDates found" ) ;
      next;
    }
    progress( "Port: $channel_xmltvid: found " . $eventdates->size() . " EventDates" );

    # browse through channels
    foreach my $eventdate ($eventdates->get_nodelist) {

      my $eventdate_date = $eventdate->getAttribute('Date');

      progress( "Port: $channel_xmltvid: browsing $eventdate_date for events" );

      # find all events for this EventDate
      my $events = $eventdate->findnodes( ".//Event" );
      if( $events->size() == 0 ) {
        error( "Port: $channel_xmltvid: No Events found for $eventdate_date" ) ;
        next;
      }
      progress( "Port: $channel_xmltvid: found " . $events->size() . " events in $eventdate_date" );

      # browse through events
      foreach my $event ($events->get_nodelist) {

        my $event_id = $event->getAttribute('Id');

        my $startdate= $event->findvalue( 'StartDate' );
        my $stopdate= $event->findvalue( 'StopDate' );
        my $title= $event->findvalue( 'Title' );
        my $shortdesc= $event->findvalue( 'Shortdescription' );
        my $longdesc= $event->findvalue( 'Longdescription' );
        my $dvbccateg= $event->findvalue( 'DVBCategoryName' );
        my $categlevel= $event->findvalue( 'CategoryNibbleLevel1' );
        my $rating= $event->findvalue( 'Rating' );

        my $starttime = create_dt( $startdate );
        next if not $starttime;

        my $endtime = create_dt( $stopdate );
        next if not $endtime;

        next if not $title;

        progress( "Port: $channel_xmltvid: $starttime - $title" );

        my $ce = {
          channel_id => $channel_id,
          title => $title,
          start_time => $starttime->ymd("-") . " " . $starttime->hms(":"),
          end_time => $endtime->ymd("-") . " " . $endtime->hms(":"),
        };

        $ce->{description} = norm($shortdesc) if $shortdesc;
        $ce->{description} = norm($longdesc) if $longdesc;

        # some characters cleanup
        $ce->{description} =~ s/\x8a/\n/g;

        if( $dvbccateg ){
          my($program_type, $category ) = $ds->LookupCat( 'Port', $dvbccateg );
          AddCategory( $ce, $program_type, $category );
        }

        $ce->{rating} = $rating if $rating;
    
        $ds->AddProgramme( $ce );

      }
    }
  }

  return 1;
}

sub create_dt {
  my ( $dtinfo ) = @_;

  if( $dtinfo !~ /^\d{4}-\d{2}-\d{2}T\d\d:\d\d:\d\d$/ ){
    return 0;
  }

  my( $year, $month, $day, $hour, $minute, $second ) = ( $dtinfo =~ /^(\d{4})-(\d{2})-(\d{2})T(\d\d):(\d\d):(\d\d)$/ );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          nanosecond => 0,
                          time_zone => 'Europe/Budapest',
  );

  #$dt->set_time_zone( "UTC" );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
