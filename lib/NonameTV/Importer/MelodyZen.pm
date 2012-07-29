package NonameTV::Importer::MelodyZen;

use strict;
use warnings;

=pod

Channels: MelodyZen HD

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use File::Temp qw/tempfile/;
use Clone;
use Clone qw(clone);

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

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "MelodyZen: $xmltvid: Processing $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  my @months;
  my @ces;
  my $year;

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "MelodyZen: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # find for which month this schedule is
    # in the first row will stand something like 'EPG MelodyZen.tv - 1 video track + 3 audio tracks - MARCH / APRIL 2009'
    for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++){

      next if( not $oWkS->{Cells}[0][$iC] );

      if( $oWkS->{Cells}[0][$iC]->Value =~ /JANUARY/i ){ push( @months, 1 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /FEBRUARY/i ){ push( @months, 2 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /MARCH/i ){ push( @months, 3 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /APRIL/i ){ push( @months, 4 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /MAY/i ){ push( @months, 5 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /JUNE/i ){ push( @months, 6 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /JULY/i ){ push( @months, 7 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /AUGUST/i ){ push( @months, 8 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /SEPTEMBER/i ){ push( @months, 9 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /OCTOBER/i ){ push( @months, 10 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /NOVEMBER/i ){ push( @months, 11 ); }
      if( $oWkS->{Cells}[0][$iC]->Value =~ /DECEMBER/i ){ push( @months, 12 ); }

      if( $oWkS->{Cells}[0][$iC]->Value =~ /\d{4}\s*$/i ){
        ( $year ) = ( $oWkS->{Cells}[0][$iC]->Value =~ /(\d{4})\s*$/i );
      }
    }

    progress( "MelodyZen: $chd->{xmltvid}: The schedule is for months " . join( ",", @months ) . " of $year" );

    # browse through rows
    # schedules are starting after we find
    # something like 'MelodyZen.tv VIDEO' in 1st column
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      my $oWkC;

      # title - column 1
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;

      # time - column 0
      $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => $title,
      };

      $ce->{quality} = "HDTV";

      push( @ces, $ce );

    }

    foreach my $month ( @months ) {
      FlushData( $chd, $dsh, $month, $year, @ces );
    }
  }

  return;
}

sub FlushData {
  my ( $chd, $dsh, $month, $year, @data ) = @_;

  return if not @data;

  my $batch_id = $chd->{xmltvid} . "_" . $year . "_" . $month;
  $dsh->StartBatch( $batch_id , $chd->{id} );

  my $lastday = DateTime->last_day_of_month( year => $year, month => $month )->day;

  my $date;

  for( my $day = 1 ; $day <= $lastday ; $day ++ ){

    $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );

    $dsh->StartDate( $date , "05:30" );

    progress("MelodyZen: $chd->{xmltvid}: Date is: $date");

    my $daydata = clone( \@data );

    foreach my $element (@{$daydata}) {
      progress("MelodyZen: $chd->{xmltvid}: $element->{start_time} - $element->{title}");
      $dsh->AddProgramme( $element );
    }

  }

  $dsh->EndBatch( 1 );
}

sub ParseTime
{
  my ( $tinfo ) = @_;

  return undef if( $tinfo !~ /^\d+h$/ );

  my( $hour ) = ( $tinfo =~ /^(\d+)h$/ );

  return sprintf( "%02d:%02d", $hour, 0 );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
