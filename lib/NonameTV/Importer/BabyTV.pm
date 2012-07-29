package NonameTV::Importer::BabyTV;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
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

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "BabyTV: $xmltvid: Processing $file" );

  my $coltime = 1;
  my $colsegment = 2;
  my $colstart = 3;
  my $colstop = 9;

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "BabyTV: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    my @shows = ();

    # find month
    my $month;
    my $year;
    if( $oWkS->{Cells}[0][0] and $oWkS->{Cells}[0][0]->Value ){
      ( $month, $year ) = ParseMonth( $oWkS->{Cells}[0][0]->Value );
    }
    next if( ! $month or ! $year );
print "$month $year\n";

    # browse through columns
    for(my $iC = $colstart ; $iC <= $colstop ; $iC++) {

      for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        my $oWkC;

        # time
        $oWkC = $oWkS->{Cells}[$iR][$coltime];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
	my( $starttime, $endtime ) = ParseTime( $oWkC->Value );
        next if( ! $starttime or ! $endtime );

        # segment
        $oWkC = $oWkS->{Cells}[$iR][$colsegment];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $segment = $oWkC->Value;
        next if( ! $segment );

        # title
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $title = $oWkC->Value;
        next if( ! $title );

        my $ce = {
          channel_id   => $chd->{id},
          title        => $title,
          subtitle     => $segment,
        };

        @{$shows[$iC - $colstart]} = () if not $shows[$iC - $colstart];
        push( @{$shows[$iC - $colstart]} , $ce );

      } # next row

    } # next column

    @shows = SpreadWeeks( 2, @shows );

    $self->FlushData( $chd, $month, $year, @shows );

  } # next worksheet

  return;
}

sub ParseMonth
{
  my ( $text ) = @_;

#print ">$text<\n";

  my( $monthname, $month, $year );

  # format: 'BabyTV Static EPG - October 2010'
  if( $text =~ /^BabyTV Static EPG - \S+\s*\d+$/i ){
    ( $monthname, $year ) = ( $text =~ /^BabyTV Static EPG - (\S+)\s*(\d+)$/i );
  } else {
    return( undef, undef );
  }

  $year += 2000 if $year lt 100;

  $month = MonthNumber( $monthname, "en" );

  return( $month, $year );
}

sub ParseTime
{
  my ( $text ) = @_;

#print ">$text<\n";

  my( $hour1, $min1, $hour2, $min2 );

  if( $text =~ /^\d{2}:\d{2}\s+-\s+\d{2}:\d{2}$/ ){
    ( $hour1, $min1, $hour2, $min2 ) = ( $text =~ /^(\d{2}):(\d{2})\s+-\s+(\d{2}):(\d{2})$/ );
  } else {
    return( undef, undef );
  }

  return( sprintf( "%02d:%02d", $hour1, $min1 ), sprintf( "%02d:%02d", $hour2, $min2 ) );
}

sub SpreadWeeks {
  my ( $weeks, @shows ) = @_;

  for( my $w = 1; $w < $weeks; $w++ ){
    for( my $d = 0; $d < 7; $d++ ){
      my @tmpshows = @{$shows[$d]};
      @{$shows[ ( $w * 7 ) + $d ]} = @tmpshows;
    }
  }

  return @shows;
}

sub FlushData {
  my $self = shift;
  my ( $chd, $month, $year, @shows ) = @_;

  my $ds = $self->{datastore};

  # find the offset of the first day in a month
  my @days = qw/Monday Tuesday Wednesday Thursday Friday Saturday Sunday/;
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => 1,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
                          );

  my $off = 0;
  my $offstart;
  foreach my $day (@days) {
    if( $day eq $dt->day_name ){
      $offstart = $off;
      last;
    }
    $off++;
  }
print "$offstart\n";;




#  my $date = $dtstart;
#  my $currdate = "x";
#
#  my $batch_id = "${xmltvid}_schema_" . $firstdate->ymd("-");
#  $dsh->StartBatch( $batch_id, $channel_id );
#
#  # run through the shows
#foreach my $dayshows ( @shows ) {
#
#if( $date < $firstdate or $date > $lastdate ){
#progress( "WFC: $xmltvid: Date " . $date->ymd("-") . " is outside of the month " . $firstdate->month_name . " -> skipping" );
#$date->add( days => 1 );
#next;
#}
#
#progress( "WFC: $xmltvid: Date is " . $date->ymd("-") );
#
#if( $date ne $currdate ) {
#
#$dsh->StartDate( $date->ymd("-") , "06:00" );
#$currdate = $date->clone;
#
#}
#
#foreach my $s ( @{$dayshows} ) {
#
#progress( "WFC: $xmltvid: $s->{start_time} - $s->{title}" );
##
#my $ce = {
#channel_id => $channel_id,
#start_time => $s->{start_time},
#title => $s->{title},
#};
#
#$dsh->AddProgramme( $ce );
##$ds->AddProgramme( $ce );
#
#
#} # next show in the day
#
## increment the date
#$date->add( days => 1 );
#} # next day
#
#$dsh->EndBatch( 1 );
#
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
