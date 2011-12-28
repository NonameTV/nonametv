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

      # skip to the row with the date
      for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );

        if( $oWkC->Value =~ /^\d{2} \d{2} \d{4}$/i ){

          # DATE
          $date = ParseDate( $oWkC->Value );
          next if ( ! $date );
          if( $date ne $currdate ){

            if( $currdate ne "x" ) {
              $dsh->EndBatch( 1 );
            }

            my $batch_id = $xmltvid . "_" . $date;
            $dsh->StartBatch( $batch_id , $channel_id );
            $dsh->StartDate( $date , "00:00" );
            $currdate = $date;
          }

          progress("Outdoor: $xmltvid: Date is: $date");
          $firstrow = $iR + 1;

        }

      }

      # programmes start from row 15
      for(my $iR = 3 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        # Title
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $timeandtitle = $oWkC->Value;
        next if ( ! $timeandtitle );
        
        # Time is before title
        my $time = ParseTime($timeandtitle);
        
        # Title, and remove time from title
        my $title = $timeandtitle;
        $title =~ s/$time //g;
        
        # Year
        my ( $year ) = ($title =~ /\(s(.+)\)/ );
	    $title =~ s/ \(s(.+)\)//g;
        
        #Ep
        my ( $episode ) = ($title =~ /ep(.+)/ );
	    $title =~ s/ ep$episode//g;
        

        progress("Outdoor: $xmltvid: $time - $title");

        my $ce = {
          channel_id   => $channel_id,
          start_time   => $time,
          title        => norm($title),
        };
        
        
        if(defined ($episode)) {
        	$ce->{episode} = sprintf( ". %d .", $episode-1 );
        }

    	if( defined( $year ) and ($year =~ /(\d\d\d\d)/) )
    	{
      		$ce->{production_date} = "$1-01-01";
    	}

        $dsh->AddProgramme( $ce );

      } # next row (next show)

    } # next column (next day)

    $dsh->EndBatch( 1 );
    $currdate = "x";

  } # next worksheet

  return;
}

sub ParseTime
{
  my ( $tinfo ) = @_;

  # format 'hh:mm'
  my( $h, $m, $title ) = ( $tinfo =~ /^(\d+):(\d+)\s+(.*)$/ );

  #$h -= 24 if $h >= 24;

  return sprintf( "%02d:%02d", $h, $m );
}

sub ParseDate {
  my ( $text ) = @_;

  my( $day, $month, $year );

  # format '2011-04-13'
  if( $text =~ /^\d{2} \d{2} \d{4}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2}) (\d{2}) (\d{4})$/i );
  }
  
  return sprintf( "%04d-%02d-%02d" , $year, $month, $day );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
