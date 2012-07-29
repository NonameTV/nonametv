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
    if( $file =~ /monthly/i ){
      $self->ImportFlatXLS( $file, $chd );
    } elsif( $file =~ /weekly/i ){
      $self->ImportGridXLS( $file, $chd );
    }
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

            $columns{'CHANNEL'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Channel/ );

            $columns{'DATE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Schedule date \(DD\/MM\/YY\)/ );

            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /SCHEDULED TIME 24 HOUR CLOCK \(HH:MM\) CET/ );

            $columns{'DURATION'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /SCHEDULED DURATION \(HH:MM\)/ );

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
      $oWkC = $oWkS->{Cells}[$iR][$columns{'CHANNEL'}];
      my $channel = $oWkC->Value;

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DATE'}];
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
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;

      # Duration
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DURATION'}];
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

sub ImportGridXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $date;
  my $currdate = "x";

  my $coltime = 2;
  my $colstart = 3;
  my $colend = 9;

  progress( "EEntertainmentTV GridXLS: $chd->{xmltvid}: Processing flat XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "EEntertainmentTV GridXLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("EEntertainmentTV GridXLS: $chd->{xmltvid}: processing worksheet named '$oWkS->{Name}'");

    for(my $iC = $colstart ; $iC <= $colend ; $iC++) {

      for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );

        if( isDate( $oWkC->Value ) ){
          $date = ParseDate( $oWkC->Value );

          if( $date ne $currdate ) {
            if( $currdate ne "x" ) {
	      $dsh->EndBatch( 1 );
            }

            my $batch_id = $chd->{xmltvid} . "_" . $date;
            $dsh->StartBatch( $batch_id , $chd->{id} );
            $dsh->StartDate( $date , "06:00" );
            $currdate = $date;

            progress("EEntertainmentTV GridXLS: $chd->{xmltvid}: Date is: $date");
          }
        }

        # time
        $oWkC = $oWkS->{Cells}[$iR][$coltime];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $time = ParseTime( $oWkC->Value );
        next if( ! $time );

        # title
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $title = $oWkC->Value;
        next if( ! $title );

        progress( "EEntertainmentTV GridXLS: $chd->{xmltvid}: $time - $title" );

        my $ce = {
          channel_id => $chd->{id},
          title => $title,
          start_time => $time,
        };

        $dsh->AddProgramme( $ce );
      }
    }
  }

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my ( $text ) = @_;

#print ">$text<\n";

  # format '01/07/10'
  if( $text =~ /^\d{2}\/\d{2}\/\d{2}$/i ){
    return 1;

  # format 'Monday\n27 December 10'
  } elsif( $text =~ /^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\n\d+\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my ( $text ) = @_;

#print ">$text<\n";

  my( $dayname, $year, $day, $month, $monthname );

  # format '01/07/10'
  if( $text =~ /^\d{2}\/\d{2}\/\d{2}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2})\/(\d{2})\/(\d{2})$/i );

  # format 'Monday\n27 December 10'
  } elsif( $text =~ /^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\n\d+\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d+$/i ){
    ( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+)\n(\d+)\s+(\S+)\s+(\d+)$/i );
    $month = MonthNumber( $monthname, "en" );
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my ( $text ) = @_;

#print ">$text<\n";

  my( $hour, $min );

  if( $text =~ /^\d{4}$/i ){
    ( $hour, $min ) = ( $text =~ /^(\d{2})(\d{2})$/i );
    $hour -= 24 if $hour gt 23;
  }

  return sprintf( '%02d:%02d', $hour, $min );
}


1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
