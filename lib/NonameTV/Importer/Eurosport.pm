package NonameTV::Importer::Eurosport;

use strict;
use warnings;

=pod

Import data from xml-files that we download via FTP.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/ParseXml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/f/;

use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  defined( $self->{FtpRoot} ) or die "You must specify FtpRoot";
  defined( $self->{Filename} ) or die "You must specify Filename";
  
  my $conf = ReadConfig();

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  # Note: HTTP::Cache::Transparent caches the file and only downloads
  # it if it has changed. This works since LWP interprets the 
  # if-modified-since header and handles it locally.

  my $dir = $chd->{grabber_info};
  my $url = $self->{FtpRoot} . $dir . '/' . $self->{Filename};

print "$url\n";
  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  my $doc = ParseXml( $cref );
  
  if( not defined( $doc ) ) {
    f "Failed to parse";
    return 0;
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//BroadcastDate_GMT" );
  
  if( $ns->size() == 0 ) {
    f "No BroadcastDates found";
    return 0;
  }

  foreach my $sched_date ($ns->get_nodelist) {
    my( $date ) = norm( $sched_date->findvalue( '@Day' ) );
    my $dt = create_dt( $date );

    my $ns2 = $sched_date->find('Emission');
    foreach my $emission ($ns2->get_nodelist) {
      my $start_time = $emission->findvalue( 'StartTimeGMT' );
      my $end_time = $emission->findvalue( 'EndTimeGMT' );

      my $start_dt = create_time( $dt, $start_time );
      my $end_dt = create_time( $dt, $end_time );

      if( $end_dt < $start_dt ) {
        $end_dt->add( days => 1 );
      }

      my $title = norm( $emission->findvalue( 'Title' ) );
      my $desc = norm( $emission->findvalue( 'Feature' ) );

	  my $type = norm( $emission->findvalue( 'BroadcastType' ) );

      my $ce = {
        channel_id => $channel_id,
        start_time => $start_dt->ymd('-') . ' ' . $start_dt->hms(':'),
        end_time   => $end_dt->ymd('-') . ' ' . $end_dt->hms(':'),
        title => $title,
        description => $desc,
      };
      
      # Find live-info and rerun
	  if( $type eq "DIREKT" )
	  {
	    $ce->{live} = "1";
	  }
	  else
	  {
	    $ce->{live} = "0";
	  }
	  
	  if( $type eq "Repris" )
	  {
	    $ce->{rerun} = "1";
	  }
	  else
	  {
	    $ce->{rerun} = "0";
	  }

      $ds->AddProgramme( $ce );
      
    }
  }

  return 1;
}

sub create_dt {
  my( $text ) = @_;

  my($day, $month, $year ) = split( "/", $text );

  return DateTime->new( year => $year,
                        month => $month,
                        day => $day,
                        time_zone => "GMT" );
}

sub create_time {
  my( $dt, $time ) = @_;

  my $result = $dt->clone();

  my( $hour, $minute ) = split(':', $time );

  $result->set( hour => $hour,
                minute => $minute,
                );

  return $result;
}
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
