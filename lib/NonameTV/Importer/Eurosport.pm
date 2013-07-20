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
use Data::Dumper;

use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  defined( $self->{FtpRoot} ) or die "You must specify FtpRoot";
  defined( $self->{Filename} ) or die "You must specify Filename";

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  return $self;
}

sub UpdateFiles
{
  my( $self ) = @_;

foreach my $chd ( @{$self->ListChannels()} ) {
  my $dir = $chd->{grabber_info};
  my $url = $self->{FtpRoot} . $dir . '/' . $self->{Filename};

  #my( $content, $code ) = MyGet( $url );
  #print $url;
  #ftp_get( $url, $self->{FileStore} . '/' .  $chd->{xmltvid} . '/' . $self->{Filename} );

}

  return;
}

sub ftp_get {
  my( $url, $file ) = @_;

  qx[curl -S -s -z "$file" -o "$file" "$url"];
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

#print $file;

my $cref=`cat $file`;

  my $doc;
    my $xml = XML::LibXML->new;
    eval { $doc = $xml->parse_string($cref); };

    if( not defined( $doc ) ) {
      error( "SvtXML: $file: Failed to parse xml" );
      return;
    }

    # Find all paragraphs.
    #my $ns = $doc->find( "//BroadcastDate_GMT" );

  # Find all paragraphs.
  my $ns = $doc->find( "//BroadcastDate_GMT" );

  if( $ns->size() == 0 ) {
    f "No BroadcastDates found";
    return 0;
  }

  foreach my $sched_date ($ns->get_nodelist) {
    my( $date ) = norm( $sched_date->findvalue( '@Day' ) );
    print Dumper($date);
    my $dt = create_dt( $date );

    #print Dumper($dt);

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

	print Dumper($ce);

      #$ds->AddProgramme( $ce );

      progress("Eurosport: $chd->{xmltvid}: $start_dt - $title");

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
