package NonameTV::Importer::TV5Monde;

#use strict;
#use warnings;

=pod

Import data from xls files delivered via e-mail.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use Encode;
use Encode::Guess;
use Spreadsheet::ParseExcel;
use Archive::Zip;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

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

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $channel_xmltvid );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $date;
  my $currdate = "x";

  progress( "TV5Monde: $channel_xmltvid: Processing $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "TV5Monde: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("TV5Monde: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Date or Time is stored in the column 0
      $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );

      if( isDate( $oWkC->Value ) ){

        $date = ParseDate( $oWkC->Value );

        if( $date ne $currdate ) {
          if( $currdate ne "x" ) {
	    $dsh->EndBatch( 1 );
          }

          my $batch_id = $channel_xmltvid . "_" . $date;
          $dsh->StartBatch( $batch_id , $channel_id );
          $dsh->StartDate( $date , "04:00" );
          $currdate = $date;

          progress("TV5Monde: $channel_xmltvid: Date is: $date");
        }

        next;
      }

      if( isTime( $oWkC->Value ) ){

        my $time = $oWkC->Value;

        if( not defined( $time ) ) {
          error( "Invalid start-time '$date' '$time'. Skipping." );
          next;
        }

        # Title - stored in column 1
        $oWkC = $oWkS->{Cells}[$iR][1];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $title = $oWkC->Value;

        progress( "TV5Monde: $channel_xmltvid: $time - $title" );

        my $ce = {
          channel_id => $channel_id,
          title => $title,
          start_time => $time,
        };

        $dsh->AddProgramme( $ce );
      }

    } # next row

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate
{
  my ( $text ) = @_;

  # the format is 'Samedi 1er novembre 2008'
  if( $text =~ /^(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\s+\d+\S*\s+(novembre|décembre)\s+\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  # the format is 'Samedi 1er novembre 2008'
  my( $dayname, $day, $monthname, $year ) = ( $dinfo =~ /^(\S+)\s+(\d+)\S*\s+(\S+)\s+(\d+)$/i );
  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $month = MonthNumber( $monthname, 'fr' );

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub isTime
{
  my ( $text ) = @_;

  # the format is '12:05 or 3:45'
  if( $text =~ /^\d+:\d+$/ ){
    return 1;
  }

  return 0;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
