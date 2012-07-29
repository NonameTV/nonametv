package NonameTV::Importer::Poker;

use strict;
use warnings;

=pod

channel: Poker

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
  progress( "Poker: $xmltvid: Processing $file" );
  
  my $currdate = "x";
  my $date;

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "Poker: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    # extract the month from cell[2][5]
    # the month is in the format 'Jan-10'
    $oWkC = $oWkS->{Cells}[1][5];
    if( ! $oWkC or ! $oWkC->Value or $oWkC->Value !~ /^\S+-\d+$/ ){
      $oWkC = $oWkS->{Cells}[2][5];
    }
    if( ! $oWkC or ! $oWkC->Value ){
      progress( "Poker: $xmltvid: Unable to extract the month of this sheet" );
      next;
    }
    my( $monthname, $year ) = ( $oWkC->Value =~ /^(\S+)-(\d+)$/ );
    $year += 2000 if $year < 100;
    my $month = MonthNumber( $monthname, "en" );

    # Each column contains data for one day
    # starting with column 3 for monday to column 9 for sunday
    for(my $iC = 3; $iC <= 9 ; $iC++ ) {

      my $firstrow;

      # skip to the row with the date
      for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );

        if( $oWkC->Value =~ /^\d+-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)$/i ){

          # DATE
          $date = ParseDate( $year, $month, $oWkC->Value );
          next if ( ! $date );

          if( $date ne $currdate ){

            if( $currdate ne "x" ) {
              $dsh->EndBatch( 1 );
            }

            my $batch_id = $xmltvid . "_" . $date;
            $dsh->StartBatch( $batch_id , $channel_id );
            $dsh->StartDate( $date , "07:00" );
            $currdate = $date;
          }

          progress("Poker: $xmltvid: Date is: $date");
          $firstrow = $iR + 1;

        }

      }

      # programmes start from row 15
      for(my $iR = $firstrow ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        # Time - column 0
        $oWkC = $oWkS->{Cells}[$iR][0];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $time = ParseTime( $oWkC->Value );
        next if ( ! $time );

        # Title
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $title = $oWkC->Value;
        next if ( ! $title );
        
        # Remove unnesscary shit.
        $title =~ s/\(P\) //g;
        $title =~ s/ \(taped\)//g;

        progress("Poker: $xmltvid: $time - $title");

        my $ce = {
          channel_id   => $channel_id,
          start_time   => $time,
          title        => norm($title),
        };

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
  my( $h, $m ) = ( $tinfo =~ /^(\d+):(\d+)$/ );

  $h -= 24 if $h >= 24;

  return sprintf( "%02d:%02d", $h, $m );
}

sub ParseDate
{
  my ( $wksyear, $wksmonth, $text ) = @_;

  my( $day, $month, $monthname );

  # format '8-Jan'
  if( $text =~ /^\d+-\S+$/ ){
    ( $day, $monthname ) = ( $text =~ /^(\d+)-(\S+)$/ );
    $month = MonthNumber( $monthname, "en" );
  } else {
    return undef;
  }

  return sprintf( "%04d-%02d-%02d" , $wksyear, $month, $day );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
