package NonameTV::Importer::Hayat;

use strict;
use warnings;

=pod

Import data from Hayat

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/norm AddCategory MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Zagreb" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xml$/i ){
    #$self->ImportXML( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportFlatXLS( $file, $chd );
  } else {
    error( "Hayat: Unknown file format: $file" );
  }

  return;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();

  my $coldate = 0;
  my $coltime = 0;
  my $coltitle = 1;

  my $date;
  my $currdate = "x";

  progress( "Hayat FlatXLS: $chd->{xmltvid}: Processing flat XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "Hayat FlatXLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("Hayat FlatXLS: $chd->{xmltvid}: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$coldate];
      if( $oWkC and $oWkC->Value ){

        if( isDate( $oWkC->Value ) ){
          $date = ParseDate( $oWkC->Value );
print "DATE $date\n";
        }

        if( $date ne $currdate ) {
          if( $currdate ne "x" ) {
	    $dsh->EndBatch( 1 );
          }

          my $batch_id = $chd->{xmltvid} . "_" . $date;
          $dsh->StartBatch( $batch_id , $chd->{id} );
          $dsh->StartDate( $date , "06:00" );
          $currdate = $date;

          progress("Hayat FlatXLS: $chd->{xmltvid}: Date is: $date");
        }
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;

      progress( "Hayat FlatXLS: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my ( $text ) = @_;

#print ">$text<\n";

  # format 'PROGRAMSKA SHEMA ZA PETAK, 24.09.2010.'
  if( $text =~ /^PROGRAMSKA SHEMA ZA.*\d{2}\.\d{2}\.\d{4}\.$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my ( $text ) = @_;

#print ">$text<\n";

  my( $year, $day, $month );

  # format '01.09.10'
  if( $text =~ /^PROGRAMSKA SHEMA ZA.*\d{2}\.\d{2}\.\d{4}\.$/i ){
    ( $day, $month, $year ) = ( $text =~ /^PROGRAMSKA SHEMA ZA.*(\d{2})\.(\d{2})\.(\d{4})\.$/i );
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
