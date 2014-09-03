package NonameTV::Importer::Hustler;

use strict;
use warnings;

=pod

Channels: HustlerTV, Blue Hustler

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use Data::Dumper;
use File::Temp qw/tempfile/;

use CAM::PDF;


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

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

#return if( $file !~ /Blue Hustler listings - November 2008 in CET\.xls/ );


if( $file =~ /\.pdf$/i ) {return $self->ImportPDF( $file, $channel_id, $xmltvid );}

  # Only process .xls files.
  return if( $file !~ /\.xls|.xlsx$/i );
  progress( "Hustler: $xmltvid: Processing $file" );


  my %columns = ();
  my $datecolumn;
  my $date;
  my $currdate = "x";
  my( $coltime, $coltitle, $colgenre, $colduration ) = undef;

  my $oBook;
  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }   #  staro, za .xls

  #print Dumper($oBook->{SheetCount});

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "Hustler: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # determine which column has the
    # information about the date
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not $datecolumn ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          next if( not $oWkS->{Cells}[$iR][$iC] );

          if( isDate( $oWkS->{Cells}[$iR][$iC]->Value ) ){
            $datecolumn = $iC;
            last;
          }
        }
      }
    }
    progress( "Hustler: $chd->{xmltvid}: Found date information in column $datecolumn" );

    # determine which column contains
    # which information
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not defined $coltime and not defined $coltitle and not defined $colduration ){

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          next if( not $oWkS->{Cells}[$iR][$iC] );

          my $coltimerino;

          if($file =~ /\.xlsx$/i) {
            $coltimerino = $oWkS->{Cells}[$iR][$iC]->{Val};
          } else {
            $coltimerino = $oWkS->{Cells}[$iR][$iC]->Value;
          }

          if( not $coltime and isTime( $coltimerino ) ){
            $coltime = $iC;
          } elsif( not $colgenre and isGenre( $oWkS->{Cells}[$iR][$iC]->Value ) ){
            $colgenre = $iC;
          } elsif( not $colduration and isDuration( $oWkS->{Cells}[$iR][$iC]->Value ) ){
            $colduration = $iC;
          } elsif( not $coltitle and isText( $oWkS->{Cells}[$iR][$iC]->Value ) ){
            $coltitle = $iC;
          }
        }
      }

      if( defined $coltime and defined $coltitle ){
        progress( "Hustler: $chd->{xmltvid}: Found columns" );
        last;
      }

      $coltime = undef;
      $colgenre = undef;
      $coltitle = undef;
      $colduration = undef;
    }

    # browse through rows
    # schedules are starting after that
    # valid schedule row must have date, time and title set
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      my $oWkC;

      $oWkC = $oWkS->{Cells}[$iR][$datecolumn];
      next if( ! $oWkC );
      if( isDate( $oWkC->Value ) ){

        $date = ParseDate( $oWkS->{Cells}[$iR][$datecolumn]->Value );

        if( $date ne $currdate ){

          progress("Hustler: Date is $date");

          if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
          }

          my $batch_id = $xmltvid . "_" . $date;
          $dsh->StartBatch( $batch_id , $channel_id );
          $dsh->StartDate( $date , "04:00" );
          $currdate = $date;
        }

        next;
      }

      # time - column $coltime
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC );
      
      if($oWkC->Value eq "") { next; }

      my $time;
      if($file =~ /\.xlsx$/i) {
        $time = ExcelFmt('hh:mm', $oWkC->{Val} ) if( $oWkC->Value );
      } else {
        $time = ParseTime( $oWkC->Value ) if( $oWkC->Value );
      }
      

      next if( ! $time );

      # title - column $coltitle
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      next if( ! $title );

      $title =~ s/PREMIERE -//g if $title;
      $title =~ s/PREMIERE-//g if $title;
      $title =~ s/HUSTLER TV-//g if $title;
      $title =~ s/HUSTLER TV -//g if $title;
      $title =~ s/#//g if $title;

      # duration - column $colduration
      my $duration;
      if( $colduration ){
        $oWkC = $oWkS->{Cells}[$iR][$colduration];
        next if( ! $oWkC );
        $duration = $oWkC->Value if( $oWkC->Value );
      }

      # genre - column $colgenre
      my $genre;
      if( $colgenre ){
        $oWkC = $oWkS->{Cells}[$iR][$colgenre];
        $genre = $oWkC->Value if( $oWkC->Value );
      }

      progress("Hustler: $xmltvid: $time - $title");


      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
        rating => 18,
      };


      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'Hustler', $genre );
        AddCategory( $ce, $program_type, $category );
      } else {AddCategory( $ce, "movie", "adult" );}

      $dsh->AddProgramme( $ce );
    }

    %columns = ();

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ImportPDF{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .pdf files.
  return if $file !~  /\.pdf$/i;

  my $batch_id;
  my $date;
  my $currdate = "x";

  progress( "Daring: $xmltvid: Processing $file" );

  my $doc = CAM::PDF->new($file) || die "$CAM::PDF::errstr\n";
  my $str;
  my $time;
  my $title;
  my $genre;

  foreach my $p ($doc->rangeToArray(1,$doc->numPages(),'1-end'))
      {
      $str = $str . $doc->getPageText($p); 
      }   

 CAM::PDF->asciify(\$str);  #print "stra: $str";

  # filtering
  $str =~ s/\n+/\n/g;
  $str =~ s/PREMIER.{0,3}\n/PREMIERE-/g; 
  $str =~ s/\nDaring.TV\nListing.*\n.Times shown are in CET.\n/\n/g;

  my @lines = split("\n", $str);

  foreach my $line (@lines) {

   # if( ($line eq "") || ($line eq "Daring!TV") || ($line eq "Listings for July      2012")  || ($line eq "(Times shown are in CET)") ){next;}

      if( isDate( $line ) ){
        $date = ParseDate( $line ); #print "date: $date \n";
        if( $date ne $currdate ){
          progress("Hustler: Date is $date");

          if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
          }

          my $batch_id = $xmltvid . "_" . $date;
          $dsh->StartBatch( $batch_id , $channel_id );
          $dsh->StartDate( $date , "05:00" );
          $currdate = $date;
        }
        next;
      }

      if( isTime( $line ) ){
        $time = ParseTime( $line ); #print "vreme: $time ";
        next;
      }

      if( not isDuration( $line ) and not isTime( $line ) and not isDate( $line ) ){
        $title = $line; #print ": $title \n";
        next;
      }

        progress("Hustler: $xmltvid: $time - $title");

      if( isDuration( $line ) ){
        my $duration = $line; #print "trajanje: $duration ";
       my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
        rating => 18,
       };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'Hustler', $genre );
        AddCategory( $ce, $program_type, $category );
      } else {AddCategory( $ce, "movie", "adult" );}

      $dsh->AddProgramme( $ce );
        next;
      }
   }

  return;
}



sub isDate
{
  my ( $text ) = @_;

#print ">$text<\n";

  # the format is 'Monday, 1 July 2008'
  if( $text =~ /^\S+\,\s*\d+\s+\S+\s+\d+$/ ){
    return 1;
  } elsif( $text =~ /^\S+\s+\d+\s+\S+\s+\d+$/ ){
    return 1;
  }

  return 0;
}

sub isTime
{
  my ( $text ) = @_;

  # the format is '00:00'
  if( $text =~ /^\d+\:\d+$/ ){
    return 1;
  } else {
    $text = ExcelFmt('hh:mm', $text);

    if( $text =~ /^\d+\:\d+$/ ){
        return 1;
    }
  }

  return 0;
}

sub isGenre
{
  my ( $text ) = @_;

  # the format is 'movie|magazine'
  if( $text =~ /^(movie|magazine)$/ ){
    return 1;
  }

  return 0;
}

sub isText
{
  my ( $text ) = @_;

  # the format is whatever but not blank
  if( $text =~ /\S+/ ){
    return 1;
  }

  return 0;
}

sub isDuration
{
  my ( $text ) = @_;

  # the format is '(00:00)'
  if( $text =~ /^\(\d+\:\d+\)$/ ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $dayname, $day, $monthname, $year );

  # the format is 'Monday, 1 July 2008'
  if( $dinfo =~ /^\S+\,\s*\d+\s+\S+\s+\d+$/ ){
    ( $dayname, $day, $monthname, $year ) = ( $dinfo =~ /^(\S+)\,\s*(\d+)\s+(\S+)\s+(\d+)$/ );
  } elsif( $dinfo =~ /^\S+\s+\d+\s+\S+\s+\d+$/ ){
    ( $dayname, $day, $monthname, $year ) = ( $dinfo =~ /^(\S+)\s+(\d+)\s+(\S+)\s+(\d+)$/ );
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $month = MonthNumber( $monthname , "en" );

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime
{
  my ( $tinfo ) = @_;

  my( $hour, $minute ) = ( $tinfo =~ /^(\d+)\:(\d+)$/ );

  if(!$hour) { return; }

  $hour = 0 if( $hour eq 24 );

  return sprintf( "%02d:%02d", $hour, $minute );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
