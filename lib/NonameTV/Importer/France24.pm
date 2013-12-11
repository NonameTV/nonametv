package NonameTV::Importer::France24;

use strict;
use warnings;

=pod

Import data from Xml-files delivered via e-mail in zip-files.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Archive::Zip qw/:ERROR_CODES/;
use Data::Dumper;
use File::Temp qw/tempfile/;
use File::Slurp qw/write_file read_file/;
use IO::Scalar;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/d p w f progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  # use augment
  $self->{datastore}->{augment} = 1;
  
  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "UTC" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $filename, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  my $currdate = "x";
  my $channel_name = $chd->{display_name};

  my $data;
  my $new_filename;

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

    my @english_files;

    my @members = $zip->members();
    foreach my $member (@members) {
      push( @english_files, $member->{fileName} ) 
	  if $member->{fileName} =~ /NGL*.*xml$/i;
    }
    
    my $numfiles = scalar( @english_files );
    if( $numfiles != 1 ) {
      f "Found $numfiles matching files, expected 1.";
      return 0;
    }


    d "Using file $english_files[0]";
    $new_filename = $english_files[0];
    $data = $zip->contents( $english_files[0] );
  }
  
  if(!defined($data)) {
  	return 0;
  }
  
$data =~ s|
||g;
$data =~ s| xmlns="urn:schemas-harris-com:bcm:tvguide"||;

  #my $docz = ParseXml( $data );
  my $doc = XML::LibXML->load_xml(string => $data);
  
  my $rows = $doc->findnodes( ".//Day" );

  if( $rows->size() == 0 ) {
	error( "France24: $chd->{xmltvid}: No Rows found" ) ;
	return;
  }

  # Days is in their own list
  foreach my $row ($rows->get_nodelist) {
  	# date
  	my $date = ParseDate($row->findvalue( './/Date' ));

	if($date ne $currdate ) {
		if( $currdate ne "x" ) {
			$dsh->EndBatch( 1 );
		}

		my $batchid = $chd->{xmltvid} . "_" . $date;
		$dsh->StartBatch( $batchid , $chd->{id} );
		$dsh->StartDate( $date , "06:00" );
		$currdate = $date;

		progress("France24: Date is: $date");
	}
  

	# Programmes is in a node of the day
    foreach my $prog ($row->childNodes()) {
      	my $title = $prog->findvalue( './Genre' ); #
      	
      	# Not a title - possible a value for the day
      	if( !$title ){
      		next;
      	}
      	
      	my $time = $prog->findvalue( './TVGuideTime' );
      	
      	my $dt = $self->create_dt( $date . "T" . $time );
      	
      	# Uppercase the first letter
        $title = ucfirst(lc($title));
      	
      	my $ce = {
          channel_id => $chd->{id},
          title => norm($title),
          start_time => $dt->ymd("-") . " " . $dt->hms(":"),
        };
      	
      	progress( "France24: ".$dt->hms(":")." - $title" );
        $ds->AddProgramme( $ce );
      
    }

  } # next row

  #  $column = undef;

  $dsh->EndBatch( 1 );

  return 1;
}
sub ParseDate {
  my ( $text ) = @_;

  my( $year, $day, $month );

  # format '2011-04-13'
  if( $text =~ /^\d{4}\-\d{2}\-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\-(\d{2})\-(\d{2})$/i );

  # format '2011/05/16'
  } elsif( $text =~ /^\d{4}\/\d{2}\/\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\/(\d{2})\/(\d{2})$/i );
   
  # format '1/14/2012'
  } elsif( $text =~ /^\d+\/\d+\/\d{4}$/i ){
    ( $month, $day, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/i );
    
  # format '02/14/12'
  } elsif( $text =~ /^\d+\/\d+\/\d{2}$/i ){
    ( $month, $day, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/i );
  }
  

  $year += 2000 if $year < 100;


  return sprintf( '%d-%02d-%02d', $year, $month, $day );
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

  my $dt = DateTime->new( year => $year,
                          month => $month,
                          day => $day,
                          hour => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => "Europe/Stockholm",
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
