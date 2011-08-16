package NonameTV::Importer::WildTV;

use strict;
use warnings;

=pod

Imports data for WILDTV.

NOTE:
You will have to unzip it yourself and select the truncated xml file
or the importer will fail because of utf-8 fail. This will get fixed 
later.

=cut

use utf8;
use Encode;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Unicode::String;

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

  progress( "WILDTV: $chd->{xmltvid}: Processing XML $file" );

  my $xml = XML::LibXML->new;
  my $data = $xml->parse_file($file)->toString(1);

  my $doc;
  eval { $doc = $xml->parse_string($data); };



  if( not defined($doc) ) {
    error( "WILDTV: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

    # the grabber_data should point exactly to one worksheet
    my $rows = $doc->findnodes( ".//programme" );

    if( $rows->size() == 0 ) {
      error( "WILDTV: $chd->{xmltvid}: No Rows found" ) ;
      return;
    }

  foreach my $row ($rows->get_nodelist) {

      my $title = $row->findvalue( './/title' );
      my $start = $self->create_dt( $row->findvalue( './@start' ) );
      my $end = $self->create_dt( $row->findvalue( './@stop' ) );

	  # extra info
	  my $desc = $row->findvalue( './/desc' );
	  
	  my $date = $start->ymd("-");
      
	  if($date ne $currdate ) {
        if( $currdate ne "x" ) {
			$dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("WILDTV: Date is: $date");
      }

      my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $start->ymd("-") . " " . $start->hms(":"),
        end_time => $end->ymd("-") . " " . $end->hms(":"),
        description => norm($desc),
      };
      
      progress( "WILDTV: $chd->{xmltvid}: $start - $title" );
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
  
  my ( $year, $month, $day, $hour, $minute ) = ( $str =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})$/ );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Zagreb',
                          );
  
  return $dt;
}

1;
