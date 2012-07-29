package NonameTV::Importer::KidsCo;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use DateTime::Duration;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

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

  my $ft = CheckFileFormat( $file );

  if( $ft eq FT_GRIDXLS ){
    $self->ImportGridXLS( $file, $channel_id, $xmltvid );
  } else {
    error( "KidsCo: $xmltvid: Unknown file format of $file" );
  }

  return;
}

sub CheckFileFormat
{
  my( $file ) = @_;

  # Only process .xls files.
  return FT_UNKNOWN if( $file !~ /\.xls$/i );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  return FT_UNKNOWN if( ! $oBook );

  # xls files with grid
  # which can differ from day to day or can
  # contain the schema for the whole period
  my $oWkS = $oBook->{Worksheet}[0];
  if( $oWkS->{Name} =~ /^CEE/ ){
    return FT_GRIDXLS;
  }

  return FT_UNKNOWN;
}

sub ImportGridXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "KidsCo GridXLS: $xmltvid: Processing $file" );

  my $coltime = 1;  # the time is in the column no. 1
  my $firstcol = 4;  # first column - monday
  my $lastcol = 10;  # last column - sunday
  my $firstrow = 4;  # schedules are starting from this row

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "KidsCo GridXLS: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    my $firstdate = ParsePeriod( $oWkS->{Name} );
    progress( "KidsCo GridXLS: $xmltvid: Importing data for period from " . $firstdate->ymd("-") );

    my $dayno = 0;
    my @shows = ();

    # browse through columns
    for(my $iC = $firstcol ; $iC <= $lastcol ; $iC++) {

      # get the date
      my $oWkC = $oWkS->{Cells}[3][$iC];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $date = ParseDate( $oWkC->Value );
      next if( ! $date );
      if( $date lt $firstdate ){
        progress( "KidsCo GridXLS: $xmltvid: Skipping date " . $date->ymd("-") );
        next;
      }

      # browse through rows
      # start at row firstrow
      for(my $iR = $firstrow ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        my $text = $oWkC->Value;
        next if( ! $text );

        my $title = $text;

        # fetch the time from $coltime column
        $oWkC = $oWkS->{Cells}[$iR][$coltime];
        next if( ! $oWkC );
        my $time = $oWkC->Value;
        next if( ! $time );
        next if( $time =~ /^KEY$/ );

        my $show = {
          start_time => $time,
          title => $title,
        };

        @{$shows[$dayno]} = () if not $shows[$dayno];
        push( @{$shows[$dayno]} , $show );

        # find to how many columns this column spreads to the right
        # all these days have the same show at this time slot
        for( my $c = $iC + 1 ; $c <= $lastcol ; $c++) {
          my $dayoff = $dayno + ($c - $iC);
          $oWkC = $oWkS->{Cells}[$iR][$c];
          if( ! $oWkC->Value ){
            @{$shows[ $dayno + ($c - $iC) ]} = () if not $shows[ $dayno + ($c - $iC) ];
            push( @{$shows[ $dayno + ($c - $iC) ]} , $show );
          } else {
            last;
          }
        }

      } # next row

      $dayno++;

    } # next column

    # sort shows by the start time
    @shows = SortShows( @shows );

    FlushData( $dsh, $firstdate, $channel_id, $xmltvid, @shows );

  } # next worksheet

  return;
}

sub bytime {

  my $at = $$a{start_time};

  my( $h1, $m1 ) = ( $at =~ /^(\d+)\:(\d+)$/ );
  my $t1 = int( sprintf( "%02d%02d", $h1, $m1 ) );

  my $bt = $$b{start_time};

  my( $h2, $m2 ) = ( $bt =~ /^(\d+)\:(\d+)$/ );
  my $t2 = int( sprintf( "%02d%02d", $h2, $m2 ) );

  $t1 <=> $t2;
}

sub SortShows {
  my ( @shows ) = @_;

  my @sorted;

  for( my $d = 0; $d < 7; $d++ ){
    last if( not $shows[$d] );
    my @tmpshows = sort bytime @{$shows[$d]};
    @{$shows[$d]} = @tmpshows;
  }

  return @shows;
}

sub FlushData {
  my ( $dsh, $firstdate, $channel_id, $xmltvid, @shows ) = @_;

  my $date = $firstdate;
  my $currdate = "x";

  # run through the shows
  foreach my $dayshows ( @shows ) {

    if( $date ) {

      progress( "KidsCo GridXLS: $xmltvid: Date is " . $date->ymd("-") );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ){
          $dsh->EndBatch( 1 );
        }

        my $batch_id = "${xmltvid}_" . $date->ymd("-");
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date->ymd("-") , "05:00" );
        $currdate = $date->clone;
      }
    }

    foreach my $s ( @{$dayshows} ) {

      progress( "KidsCo GridXLS: $xmltvid: $s->{start_time} - $s->{title}" );

      my $ce = {
        channel_id => $channel_id,
        start_time => $s->{start_time},
        title => $s->{title},
      };

      $dsh->AddProgramme( $ce );

    } # next show in the day

    # increment the date
    $date->add( days => 1 );

  } # next day

  $dsh->EndBatch( 1 );

}

sub ParsePeriod {
  my ( $text ) = @_;

#print ">$text<\n";
  my( $day, $monthname, $year );

  # format 'CEE ME January 1 2009'
  if( $text =~ /^CEE ME (january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+\s+\d+$/i ){
    ( $monthname, $day, $year ) = ( $text =~ /^CEE ME (\S+)\s+(\d+)\s+(\d+)$/ );
  }

  # format 'CEE Feb 2 2009'
  if( $text =~ /^CEE (jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+\d+\s+\d+$/i ){
    ( $monthname, $day, $year ) = ( $text =~ /^CEE (\S+)\s+(\d+)\s+(\d+)$/ );
  }

  # format 'March 2 2009'
  if( $text =~ /^(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+\s+\d+$/i ){
    ( $monthname, $day, $year ) = ( $text =~ /^(\S+)\s+(\d+)\s+(\d+)$/ );
  }

  # format 'CEE ME Dec 1' or 'CEE ME Dec8'
  if( $text =~ /^CEE ME (jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*\d+$/i ){
    ( $monthname, $day ) = ( $text =~ /^CEE ME (\S+)\s*(\d+)$/ );
    $year = DateTime->today->year();
  }

#print "DAY: $day\n";
#print "MON: $monthname\n";

  my $month = MonthNumber( $monthname , 'en' );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
                          );

  return $dt;
}

sub ParseDate {
  my ( $text ) = @_;
#print ">$text<\n";

  # format 'January 31 2009'
  my( $monthname, $day, $year );

  if( $text =~ /^\S+\s+\d+\s+\d+$/ ){
    ( $monthname, $day, $year ) = ( $text =~ /^(\S+)\s+(\d+)\s+(\d+)$/ );
  } else {
    return undef;
  }
#print "$monthname\n";
#print "$day\n";
#print "$year\n";

  my $month = MonthNumber( $monthname , 'en' );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
                          );

  return $dt;
}


1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
