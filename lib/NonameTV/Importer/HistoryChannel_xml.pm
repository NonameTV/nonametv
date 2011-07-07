package NonameTV::Importer::HistoryChannel_xml;

use strict;
use warnings;

=pod

Imports data from History Channel (AETN, sent by Global Listings).
The lists is in XML format. Every day is handled as a seperate batch.

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;

use NonameTV qw/norm ParseXml AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  }


  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
    my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "HistoryXML: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "HistoryXML: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

    # the grabber_data should point exactly to one worksheet
    my $rows = $doc->findnodes( ".//BROADCAST" );

    if( $rows->size() == 0 ) {
      error( "HistoryXML: $chd->{xmltvid}: No Rows found" ) ;
      return;
    }

  foreach my $row ($rows->get_nodelist) {

      my $time = $row->findvalue( './/BROADCAST_START_DATETIME' );
      my $title = $row->findvalue( './/BROADCAST_TITLE' );
      my $start = $self->create_dt( $row->findvalue( './/BROADCAST_START_DATETIME' ) );
      
      my $date = $start->ymd("-");
      
	  if($date ne $currdate ) {
        if( $currdate ne "x" ) {
			$dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("HistoryXML: Date is: $date");
      }

	  # extra info
	  my $subtitle = $row->findvalue( './/BROADCAST_SUBTITLE' );
	  my $season = $row->findvalue( './/PROGRAMME//SERIES_NUMBER' );
	  my $episode = $row->findvalue( './/PROGRAMME//EPISODE_NUMBER' );
	  my $of_episode = $row->findvalue( './/PROGRAMME//NUMBER_OF_EPISODES' );
	  my $desc = $row->findvalue( './/PROGRAMME//TEXT//TEXT_TEXT' );
	  my $year = $row->findvalue( './/PROGRAMME//PROGRAMME_YEAR' );
	  


      my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $start->ymd("-") . " " . $start->hms(":"),
        description => norm($desc),
      };
      
      $ce->{subtitle} = norm($subtitle) if $subtitle;
      
      if( defined( $year ) and ($year =~ /(\d\d\d\d)/) )
    	{
      		$ce->{production_date} = "$1-01-01";
    	}
      
      # Episode info in xmltv-format
      if( ($episode ne "") and ( $of_episode ne "") and ( $season ne "") )
      {
        $ce->{episode} = sprintf( "%d . %d/%d .", $season-1, $episode-1, $of_episode );
      }
      elsif( ($episode ne "") and ( $of_episode ne "") )
      {
        $ce->{episode} = sprintf( ". %d/%d .", $episode-1, $of_episode );
      }
      elsif( ($episode ne "") and ( $season ne "") )
      {
        $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      }
      elsif( $episode ne "" )
      {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }
      
      progress( "HistoryXML: $chd->{xmltvid}: $start - $title" );
      $ds->AddProgramme( $ce );

    } # next row

  #  $column = undef;

  $dsh->EndBatch( 1 );

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
  
  my( $hour, $minute ) = split( ":", $time );
  

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Stockholm',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

1;
