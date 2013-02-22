package NonameTV::Importer::OutdoorChannel;

use strict;
use warnings;

=pod

channel: OutdoorChannel

Import data from Excel-files delivered via e-mail.
Each file contains more sheets, one sheet per week.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV qw/AddCategory norm MonthNumber/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

# File types
use constant {
  FT_UNKNOWN  => 0,  # unknown
  FT_FLATXLS  => 1,  # flat xls file
  FT_GRIDXLS  => 2,  # xls file with grid
};

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Zagreb" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  $self->ImportGridXLS( $file, $channel_id, $xmltvid );

  return;
}

sub ImportGridXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  $self->{fileerror} = 0;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my( $oBook, $oWkS, $oWkC );

  # Only process .xls files.
  return if $file !~  /\.xls$/i;
  progress( "Outdoor: $xmltvid: Processing $file" );
  
  my $currdate = "x";
  my $date;

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    
    if($oWkS->{Name} =~ /New/) {
        progress("Skipping worksheet $oWkS->{Name}" );
     next;
    }

    progress( "Outdoor: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    # Each column contains data for one day
    # starting with column 3 for monday to column 9 for sunday
    for(my $iC = 2; $iC <= 7 ; $iC++ ) {

      my $firstrow;

      # programmes start from row 15
      for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

		# date (column 1)
        $oWkC = $oWkS->{Cells}[$iR][0];
        next if( ! $oWkC );
		$date = ParseDate( norm($oWkC->Value) );
		#$date = $oWkC->Value;
        next if( ! $date );

	    unless( $date ) {
		  progress("SKIPPING :D");
	      next;
	    }
	  
	  if($date ne $currdate ) {
        if( $currdate ne "x" ) {
			# save last day if we have it in memory
		#	FlushDayData( $channel_xmltvid, $dsh , @ces );
			$dsh->EndBatch( 1 );
        }



        my $batchid = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batchid , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("ExtremeSports: Date is: $date");
      }
	  
	  	#if($iR == 28) { next; }
	  
	  # time (column 1)
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      my $time = ParseTime( norm($oWkC->Value) );
      next if( ! $time );
      
      # title
      $oWkC = $oWkS->{Cells}[$iR][3];
      my $title = $oWkC->Value;
      
      progress("$time - $title");

        my $ce = {
          channel_id   => $channel_id,
		  title		   => norm($title),
          start_time   => $time,
        };
      
      $dsh->AddProgramme( $ce );

      } # next row (next show)

    } # next column (next day)

    $dsh->EndBatch( 1 );

  } # next worksheet

  return;
}

sub ParseTime {
  my( $text ) = @_;

#	print "ParseTime: >$text<\n";

  my( $hour , $min, $sec );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

sub ParseDate {
  my ( $text ) = @_;

  my( $day, $month, $year );
  
#  print("Date: $text\n");

  # format '2011-04-13'
  if( $text =~ /^\d{2}\/\d{2}\/\d{4}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2})\/(\d{2})\/(\d{4})$/i );
  }
  
  return sprintf( "%04d-%02d-%02d" , $year, $month, $day );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
