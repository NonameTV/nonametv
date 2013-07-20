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
use Data::Dumper;
use Archive::Zip qw/:ERROR_CODES/;
use File::Slurp;

use NonameTV qw/norm normUtf8 ParseXml AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;
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
  my( $filename, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  my $data = undef;
  
  if( $filename =~ /\.xml$/i ) {
    $data = read_file($filename);
  }
  elsif( $filename =~ /\.zip$/i ) {
    #my( $fh, $tempname )  = tempfile();
    #write_file( $fh, $cref );
    my $zip = Archive::Zip->new();
    if( $zip->read( $filename ) != AZ_OK ) {
      f "Failed to read zip.";
      return 0;
    }

    my @swedish_files;
    
    my @members = $zip->members();
    foreach my $member (@members) {
      push( @swedish_files, $member->{fileName} ) 
	  if $member->{fileName} =~ /.xml$/i;
    }
    
    my $numfiles = scalar( @swedish_files );
    if( $numfiles != 1 ) {
      f "Found $numfiles matching files, expected 1.";
      return 0;
    }

    d "Using file $swedish_files[0]";

    $data = $zip->contents( $swedish_files[0] );
    $filename = $swedish_files[0];
  }
  
  if(defined($data)) {
  $data =~ s|
||g;
    #$data =~ s| source-data-url="http://tvprofil.net/xmltv/" source-info-name="Phazer XML servis 4.0" source-info-url="http://tvprofil.net"||;
    
    $filename =~ s|.xml$||;
    
  	$self->ImportXML( $data, $chd, $filename );
  } else {
  	error("Something went wrong");
  	return 0;
  }


  return;
}

sub ImportXML
{
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  my $currdate = "x";

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($cref); };
  if( $@ ne "" )
  {
    error( "WildTV: Failed to parse $@" );
    return 0;
  }
  
  # Find all "programme"-entries.
  my $ns = $doc->find( ".//programme" );
  
  foreach my $sc ($ns->get_nodelist)
  {
    #
    # start time
    #
    my $start = $self->create_dt( $sc->findvalue( './@start' ) );
    my $date = $start->ymd("-");
    
    if($date ne $currdate ) {
		if( $currdate ne "x" ) {
			$dsh->EndBatch( 1 );
		}

		my $batchid = $chd->{xmltvid} . "_" . $date;
		$dsh->StartBatch( $batchid , $chd->{id} );
		$dsh->StartDate( $date , "06:00" );
		$currdate = $date;

		progress("WildTV: Date is: $date");
	}
    
    #
    # end time
    #
    my $end = $self->create_dt( $sc->findvalue( './@stop' ) );
    
    #
    # title
    #
    my $title = $sc->findvalue( './title' );
    $title =~ s/ amp / &amp; /g if $title; # What the hell
    
    #
    # description
    #
    my $desc = $sc->findvalue( './desc' );


    progress("WildTV: $chd->{xmltvid}: $start - $title");

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title),
      start_time   => $start->hms(":"),
      end_time     => $end->hms(":"),
      description  => norm($desc),
    };

    $dsh->AddProgramme( $ce );

  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  #print("Date >$str<\n");
  
  my $year = substr( $str , 0 , 4 );
  my $month = substr( $str , 4 , 2 );
  my $day = substr( $str , 6 , 2 );
  my $hour = substr( $str , 8 , 2 );
  my $minute = substr( $str , 10 , 2 );
  my $second = substr( $str , 12 , 2 );
  #my $offset = substr( $str , 15 , 5 );
  
  
  if( not defined $year )
  {
    return undef;
  }
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'America/Belem', # Canada
                          );
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

1;
