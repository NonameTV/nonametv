package NonameTV::Importer::EEntertainmentTV;

use strict;
use warnings;

=pod

Import data from Da Vinci Learning

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

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

  if( $file =~ /\.xml$/i ){
    #$self->ImportXML( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportFlatXLS( $file, $chd );
  } else {
    error( "EEntertainmentTV: Unknown file format: $file" );
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

  progress( "EEntertainmentTV FlatXLS: $chd->{xmltvid}: Processing flat XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "EEntertainmentTV FlatXLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("EEntertainmentTV FlatXLS: $chd->{xmltvid}: processing worksheet named '$oWkS->{Name}'");

    my $foundcolumns = 0;

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /PROGRAMME TITLE\/SLOT NAME/ );
          }
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}
        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # Channel
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Channel'}];
      my $channel = $oWkC->Value;

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Schedule date (DD/MM/YY)'}];
      if( $oWkC and $oWkC->Value ){

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

          progress("EEntertainmentTV FlatXLS: $chd->{xmltvid}: Date is: $date");
        }
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'SCHEDULED TIME 24 HOUR CLOCK (HH:MM) CET/CAT'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;

      # Duration
      $oWkC = $oWkS->{Cells}[$iR][$columns{'SCHEDULED DURATION (HH:MM)'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $duration = $oWkC->Value;

      # ID
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Alpha Numeric KEY'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $id = $oWkC->Value;

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'PROGRAMME TITLE/SLOT NAME (30 characters)'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;

      # Episode title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'EPISODE TITLE (100 characters) (EPNM)'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $episodetitle = $oWkC->Value;

      # Genre id
      $oWkC = $oWkS->{Cells}[$iR][$columns{'dvb genre id (number) XX (DVBG)'}];
      my $genreid = $oWkC->Value if( $oWkC and $oWkC->Value );

      # Genre name
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DVB GENRE NAME (30 chr)  (GENR)'}];
      my $genrename = $oWkC->Value if( $oWkC and $oWkC->Value );

      # SubGenre id
      $oWkC = $oWkS->{Cells}[$iR][$columns{'dvb subgenre id (Number)  XX (DVBS)'}];
      my $subgenreid = $oWkC->Value if( $oWkC and $oWkC->Value );

      # SubGenre name
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DVB Sub-Genre Name (30 char) (SUBG)'}];
      my $subgenrename = $oWkC->Value if( $oWkC and $oWkC->Value );

      # Rating
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Censorship code (was called dvb parental rating)'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $rating = $oWkC->Value;

      # Synopsis
      $oWkC = $oWkS->{Cells}[$iR][$columns{'SYNOPSIS (200 chr) Short Format'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $synopsis = $oWkC->Value;

      # Production year
      $oWkC = $oWkS->{Cells}[$iR][$columns{'YEAR (of production) (4 chr) (YEAR)'}];
      my $productionyear = $oWkC->Value if( $oWkC and $oWkC->Value );

      # Language
      $oWkC = $oWkS->{Cells}[$iR][$columns{'LANGUAGE'}];
      my $language = $oWkC->Value if( $oWkC and $oWkC->Value );

      progress( "EEntertainmentTV FlatXLS: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      $ce->{schedule_id} = $id if ( $id =~ /\S/ );
      $ce->{subtitle} = $episodetitle if $episodetitle;
      $ce->{description} = $synopsis if $synopsis;
      $ce->{aspect} = "4:3";
      $ce->{rating} = $rating if ( $rating =~ /\S/ );

      if( $genrename ){
        my($program_type, $category ) = $ds->LookupCat( 'EEntertainmentTV', $genrename );
        AddCategory( $ce, $program_type, $category );
      }

      if( $productionyear and ( $productionyear =~ /(\d\d\d\d)/ ) ){
        $ce->{production_date} = "$1-01-01";
      }

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

  # format '01/07/10'
  if( $text =~ /^\d{2}\/\d{2}\/\d{2}$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my ( $text ) = @_;

#print ">$text<\n";

  my( $year, $day, $month );

  # format '01/07/10'
  if( $text =~ /^\d{2}\/\d{2}\/\d{2}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2})\/(\d{2})\/(\d{2})$/i );
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
