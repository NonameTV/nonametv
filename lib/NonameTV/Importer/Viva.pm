package NonameTV::Importer::Viva;

use strict;
use warnings;

=pod

channel: Viva

Import data from Excel-files delivered via e-mail.
Each file contains more sheets, one sheet per week.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV qw/AddCategory norm/;

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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
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
  progress( "Viva: $xmltvid: Processing $file" );
  
  my $currdate = "x";
  my $date;

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "Viva: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    # Each column contains data for one day
    # starting with column 1 for monday to column 13 for sunday
    for(my $iC = 1; $iC <= 13 ; $iC+=2 ) {

      # DATE is in the 5th row
      $oWkC = $oWkS->{Cells}[4][$iC];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if ( ! $date );

      if( $date ne $currdate ){

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;
      }

      progress("Viva: $xmltvid: Date is: $date");


      # programmes start from row 6
      for(my $iR = 5 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

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

        progress("Viva: $xmltvid: $time - $title");

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

  return sprintf( "%02d:%02d", $h, $m );
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $m, $d, $y );

  # format 'Donnerstag 12.02.2009'
  if( $dinfo =~ /^\S+\s+\d+\.\d+\.\d+$/ ){
    ( $d, $m, $y ) = ( $dinfo =~ /^\S+\s+(\d+)\.(\d+)\.(\d+)$/ );
  } else {
    return undef;
  }

  $y += 2000 if $y < 100;

  return sprintf( "%04d-%02d-%02d" , $y, $m, $d );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
