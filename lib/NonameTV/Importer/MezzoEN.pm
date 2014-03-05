package NonameTV::Importer::MezzoEN;

use strict;
use warnings;


=pod

Import data from XLSX files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Spreadsheet::Read;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");


use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm normUtf8 AddCategory MonthNumber/;
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

  #$self->{datastore}->{augment} = 1;

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

  if( $file =~ /\.xlsx$/i ){
    $self->ImportXLSX( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  }


  return;
}

sub ImportXML {
	my $self = shift;
  my( $file, $chd ) = @_;
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $self->{fileerror} = 1;

	# Do something beautiful here later on.

	error("From now on you need to convert XML files to XLS files.");

	return 0;
}

sub ImportXLSX {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls or .xlsx files.
  progress( "MezzoEN: $xmltvid: Processing $file" );

	my %columns = ();
  my $date;
  my $currdate = "x";
  my $coldate = 0;
  my $coltime = 1;
  my $coltitle = 3;
  my $colyear = 4;
  my $coldesc = 7;

my $oBook;

if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }

#my $ref = ReadData ($file);

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} !~ /1/ ){
      progress( "MezzoEN: Skipping other sheet: $oWkS->{Name}" );
      next;
    }

    progress( "MezzoEN: Processing worksheet: $oWkS->{Name}" );

	my $foundcolumns = 0;
    # browse through rows
    my $i = 0;
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    $i++;

      my $oWkC;

      # date
            $oWkC = $oWkS->{Cells}[$iR][$coldate];
            next if( ! $oWkC );

      	  $date = $oWkC->{Val} if( $oWkC->Value );
            $date = ParseDate( ExcelFmt('yyyy-mm-dd', $date) );
            next if( ! $date );

      if( $date ne $currdate ){

        progress("MezzoEN: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC );



      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );

	  #Convert Excel Time -> localtime
      $time = ExcelFmt('hh:mm', $time);
      $time =~ s/_/:/g; # They fail sometimes


      # title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      $oWkC = $oWkS->{Cells}[$iR][$coldesc];
      my $desc = $oWkC->Value if( $oWkC );


      my $ce = {
        channel_id  => $channel_id,
        start_time  => $time,
        title 		=> norm($title),
        description => norm($desc),
      };

      # Prod year
	  $oWkC = $oWkS->{Cells}[$iR][$colyear];
	  my $year = $oWkC->Value if( $oWkC );

	  if(($year) and $year ne "" and $year =~ /(\d\d\d\d)/) {
	  	$ce->{production_date} = "$1-01-01";
	  }


		 my( $t, $st ) = ($ce->{title} =~ /(.*)\: (.*)/);
         if( defined( $st ) )
         {
              # This program is part of a series and it has a colon in the title.
              # Assume that the colon separates the title from the subtitle.
              $ce->{title} = $t;
              $title = $t;
              $ce->{subtitle} = $st;
         }

	  progress("MezzoEN: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  my $xmltvid = $chd->{xmltvid};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "MezzoEN: $xmltvid: Processing XLS $file" );

#return if ( $file !~ /grille_en2/ );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "MezzoEN: $file: Failed to parse xls" );
    return;
  }

  if( not $oBook->{SheetCount} ){
    error( "MezzoEN: $file: No worksheets found in file" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} =~ /AM(\s+|\/)PM/ ){
      progress("MezzoEN: $xmltvid: Skipping worksheet named '$oWkS->{Name}'");
      next;
    }

    progress("MezzoEN: $xmltvid: Processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

            # other possible names of the columns
            $columns{'DATE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^DATES$/ );
            $columns{'DATE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Broadcast day$/ );
            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^TIMES$/ );
            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^HOURS$/ );
            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^HEURE$/ );
            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^HEURES$/ );
            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Start time$/ );
            $columns{'LENGTH'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^LENGHTS$/ );
            $columns{'LENGTH'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Duration \(hh:mm:ss\)$/ );
            $columns{'LENGTH'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^DUREE$/ );
            $columns{'LENGTH'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^DUREES$/ );
            $columns{'TITLE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^TITLES$/ );
            $columns{'TITLE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^TITRE$/ );
            $columns{'TITLE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^TITRES$/ );
            $columns{'DESCRIPTION'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^DESCRIPTIONS$/ );
            $columns{'DESCRIPTION'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^SYNOPSIS$/ );
            $columns{'DESCRIPTION'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Resume$/ );
            $columns{'YEAR'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^ANNEES$/ );
            $columns{'GENRE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^GENRES$/ );
            $columns{'DIRECTOR'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^DIRECTORS$/ );
            $columns{'DIRECTOR'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^REALISATEURS$/ );

            $columns{'YEAR'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Année de production$/ );
            $columns{'YEAR'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Production Year$/ );
            $columns{'YEAR'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^AnnÈe de production$/ );
            $columns{'DATE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Date de programmation$/ );
            $columns{'DATE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Date de Programmation$/ );
            $columns{'DURATION'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Durée de Prog\. \(hh:mm:ss\)$/ );
            $columns{'DURATION'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^DurÈe de Prog\. \(hh:mm:ss\)$/ );
            $columns{'DURATION'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Durée réelle$/ );
            $columns{'GENRE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Genre$/ );
            $columns{'GENRE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Category$/ );
            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Heure de d/ );
            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Heure de début$/ );
            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Heure de début arrondie$/ );
            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Heure de dÈbut arrondie$/ );
            $columns{'DIRECTOR'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Réalisateurs$/ );
            $columns{'DIRECTOR'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Directors$/ );
            $columns{'DIRECTOR'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^RÈalisateurs$/ );
            $columns{'DESCRIPTION'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Résumé long$/ );
            $columns{'DESCRIPTION'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^RÈsumÈ long$/ );
            $columns{'TITLE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Titre$/ );
            $columns{'TITLE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Title$/ );
            $columns{'TITLE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Titre presse$/ );
          }

          next;
        }
      }

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DATE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate2( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batch_id , $chd->{id} );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("MezzoEN: $xmltvid: Date is: $date");
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );

      my $time = ParseTime( $oWkC->Value );
      if( not defined( $time ) ) {
        error( "Invalid start-time '$date' '" . $oWkC->Value . "'. Skipping." );
        next;
      }

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TITLE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      # Length
      #$oWkC = $oWkS->{Cells}[$iR][$columns{'LENGTH'}];
      #next if( ! $oWkC );
      #next if( ! $oWkC->Value );
      #my $duration = $oWkC->Value;

      # Description
      my $description;
      if( $columns{'DESCRIPTION'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'DESCRIPTION'}];
        $description = $oWkC->Value if ( $oWkC and $oWkC->Value );
      }

      # Year
      my $year;
      if( $columns{'YEAR'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'YEAR'}];
        $year = $oWkC->Value if ( $oWkC and $oWkC->Value );
      }

      # Genre
      my $genre;
      if( $columns{'GENRE'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'GENRE'}];
        $genre = $oWkC->Value if ( $oWkC and $oWkC->Value );
      }

      # Director
      my $directors;
      if( $columns{'DIRECTOR'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'DIRECTOR'}];
        $directors = $oWkC->Value if ( $oWkC and $oWkC->Value );
      }

      progress( "MezzoEN: $xmltvid: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      $ce->{description} = $description if $description;
      $ce->{directors} = $directors if $directors;

      if( $year and ( $year =~ /(\d\d\d\d)/ ) ){
        $ce->{production_date} = "$1-01-01";
      }

      if( $genre and length( $genre ) ){
        my($program_type, $category ) = $ds->LookupCat( "MezzoEN", $genre );
        AddCategory( $ce, $program_type, $category );
      }

      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next sheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $day, $month, $year );

#print ">$dinfo<\n";

  # format '033 03 Jul 2008'
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{2}.\d{2}.\d{4}$/ ){ # format '11/18/2011'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}\/\d{1,2}\/\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  else {
    return undef;
  }

  return undef if( ! $year);

  $year+= 2000 if $year< 100;

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          );

  $dt->set_time_zone( "UTC" );

  return $dt->ymd();
}

sub ParseDate2
{
  my( $dateinfo ) = @_;

  my( $month, $day, $year );

  if( $dateinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){
    ( $year, $month, $day ) = ( $dateinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dateinfo =~ /^\d+-\d+-\d+$/ ){
    ( $month, $day, $year ) = ( $dateinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } else {
    return undef;
  }

  $year += 2000 if( $year < 100);

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime
{
  my( $timeinfo ) = @_;

#print ">$timeinfo<\n";

  my( $hour, $min, $sec );

  if( $timeinfo =~ /^\d+:\d+:\d+$/ ){ # format '11:45:00'
    ( $hour, $min, $sec ) = ( $timeinfo =~ /^(\d+):(\d+):(\d+)$/ );
  } elsif( $timeinfo =~ /^\d+:\d+\s+AM\/PM$/ ){ # format '13:15 AM/PM'
    ( $hour, $min ) = ( $timeinfo =~ /^(\d+):(\d+)\s+AM\/PM$/ );
  } elsif( $timeinfo =~ /^\d+:\d+$/ ){ # format '11:45:00'
    ( $hour, $min ) = ( $timeinfo =~ /^(\d+):(\d+)$/ );
  } else {
    return undef;
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End: