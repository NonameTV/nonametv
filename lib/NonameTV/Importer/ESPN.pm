package NonameTV::Importer::ESPN;

use strict;
use warnings;

=pod

Import data from ESPN

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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
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
    error( "ESPN: Unknown file format: $file" );
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
  my $date;
  my $currdate = "x";

  progress( "ESPN FlatXLS: $chd->{xmltvid}: Processing flat XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "ESPN FlatXLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("ESPN FlatXLS: $chd->{xmltvid}: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not $columns{'Title'} ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

            $columns{'TITLE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /TITLE/i );
            $columns{'STARTTIME'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /START TIME/i );
            $columns{'SYNOPSIS'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /SYNOPSIS/i );
          }
        }

foreach my $cl (%columns) {
print "$cl\n";
}
        next;
      }

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DATE'}];
      if( $oWkC  and $oWkC->Value ){

        if( isDate( $oWkC->Value ) ){
          $date = ParseDate( $oWkC->Value );
        }

        if( $date ne $currdate ) {
          if( $currdate ne "x" ) {
	    $dsh->EndBatch( 1 );
          }

          my $batch_id = $chd->{xmltvid} . "_" . $date;
          $dsh->StartBatch( $batch_id , $chd->{id} );
          $dsh->StartDate( $date , "06:00" );
          $currdate = $date;

          progress("ESPN FlatXLS: $chd->{xmltvid}: Date is: $date");
        }
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'STARTTIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;

      # Genre
      $oWkC = $oWkS->{Cells}[$iR][$columns{'GENRE'}];
      my $genre = $oWkC->Value if $oWkC->Value;

      # Quality
      #$oWkC = $oWkS->{Cells}[$iR][$columns{'HD'}];
      #my $quality = $oWkC->Value if $oWkC->Value;

      # Synopsis
      $oWkC = $oWkS->{Cells}[$iR][$columns{'SYNOPSIS'}];
      my $synopsis = $oWkC->Value if $oWkC->Value;

      progress( "ESPN FlatXLS: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'ESPN', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      #$ce->{quality} = 'HDTV' if( $quality =~ /^HD$/i );
      $ce->{description} = $synopsis if $synopsis;

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

  # format '01.09.10'
  if( $text =~ /^\d{2}\.\d{2}\.\d{2}$/i ){
    return 1;

  # format '01/08/2010'
  } elsif( $text =~ /^\d{2}\/\d{2}\/\d{4}$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my ( $text ) = @_;

#print ">$text<\n";

  my( $year, $day, $month );

  # format '01.09.10'
  if( $text =~ /^\d{2}\.\d{2}\.\d{2}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2})\.(\d{2})\.(\d{2})$/i );

  # format '01/08/2010'
  } elsif( $text =~ /^\d{2}\/\d{2}\/\d{4}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2})\/(\d{2})\/(\d{4})$/i );
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
