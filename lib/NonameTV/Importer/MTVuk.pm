package NonameTV::Importer::MTVuk;

use strict;
use warnings;

=pod

Import data from mtv.uk website.

Channels: MTV ONE, MTV TWO, MTV HITS, MTV DANCE, MTV BASE, TMF, VH1, VH1 Classic

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Encode qw/decode encode/;

use NonameTV qw/MyGet norm Html2Xml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

use constant {
  T_HEAD1 => 11,
  T_HEAD2 => 12,
  T_HEAD3 => 13,
  T_SHOW => 14,
  T_DESC => 15,
  T_STOP => 16,
};

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/London" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $today = DateTime->today();

  # the url is in format 'http://www.mtv.co.uk/channel/vh1/schedule/1'
  # where 1 is for today, 7 is for today + 6 days

  my( $year, $month, $day ) = ( $objectname =~ /_(\d+)-(\d+)-(\d+)$/ );
  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day,
                          time_zone   => 'Europe/London',
  );

  if( DateTime->compare( $dt, $today ) lt 0 ){
    progress( "MTVuk: $objectname: Skipping date in the past " . $dt->ymd() );
    return( undef, undef );
  }

  my $day_diff = $dt->subtract_datetime( $today )->delta_days;
  my $url = sprintf( "%s/tv-guide/page/%s/%d", $self->{UrlRoot}, $chd->{grabber_info}, $day_diff );
  progress( "MTVuk: $objectname: Fetching data from $url" );

  return( $url, undef );
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  $dsh->StartDate( $date, "00:00" );

  my $doc = Html2Xml( $$cref );
  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  }

  # Find all "<div id="schedule-136306" class="teaser">"
  my $ns = $doc->find( "//div[\@class=\"teaser\"]//." );
  if( $ns->size() == 0 ) {
    return (undef, "No schedules found" );
  }

  foreach my $sc ($ns->get_nodelist){

    my $time = $sc->findvalue( "./div[\@class=\"schedule-time\"]" );
    next if( ! $time );

    my $title = $sc->findvalue( "./div[\@class=\"tHeader\"]" );
    next if( ! $title );

    my $description = $sc->findvalue( "./p" );

    progress("MTVuk: $chd->{xmltvid}: $time - $title");

    my $ce = {
      channel_id => $chd->{id},
      start_time => $time,
      title => $title,
    };

    $ce->{description} = $description if $description;


    $dsh->AddProgramme( $ce );
  }

  return 1;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
