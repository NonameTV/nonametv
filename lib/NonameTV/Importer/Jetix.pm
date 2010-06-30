package NonameTV::Importer::Jetix;

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

print "FILE: $file\n";
#return if ( $file !~ /Disney/ );

  my $ft = CheckFileFormat( $file );
print "FT $ft\n";

  if( $ft eq FT_FLATXLS ){
    $self->ImportFlatXLS( $file, $channel_id, $xmltvid );
  } elsif( $ft eq FT_GRIDXLS ){
    $self->ImportGridXLS( $file, $channel_id, $xmltvid );
  } else {
    error( "Jetix: $xmltvid: Unknown file format of $file" );
  }

  return;
}

sub CheckFileFormat
{
  my( $file ) = @_;

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  return FT_UNKNOWN if( ! $oBook );

  # the flat sheet file which sometimes uses
  # Jetix Play has the single sheet and
  # column names in the first row
  # check against the name of the 3rd column value of the first row
  # the content of this column shoul be 'English Prog Title'
  if( $oBook->{SheetCount} eq 1 ){
    my $oWkS = $oBook->{Worksheet}[0];
    my $oWkC = $oWkS->{Cells}[0][2];
    if( $oWkC ){
      return FT_FLATXLS if( $oWkC->Value =~ /^English Prog Title$/ );
    }
  }

  # both Jetix and Jetix Play sometimes send
  # xls files with grid
  # which can differ from day to day or can
  # contain the schema for the whole period
  my $oWkS = $oBook->{Worksheet}[0];
  if( $oWkS->{Name} =~ /Highlights/i ){
    $oWkS = $oBook->{Worksheet}[1];
  }
  my $oWkC = $oWkS->{Cells}[0][0];
print $oWkC->Value . "\n";
  if( $oWkC and $oWkC->Value ){
    if( $oWkC->Value =~ /Jetix.*EXCLUDING RUSSIA/ or $oWkC->Value =~ /Jetix Play/ or $oWkC->Value =~ /Hungary/ ){
      return FT_GRIDXLS;
    } elsif( $oWkC->Value =~ /Disney XD/i or $oWkC->Value =~ /Jetix/i ){
      return FT_GRIDXLS;
    }
  }

  return FT_UNKNOWN;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "Jetix FlatXLS: $xmltvid: Processing FlatXLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  if( not defined( $oBook ) ) {
    error( "Jetix FlatXLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("Jetix FlatXLS: $xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

            # the name of the column 'GMT Time'
            # is sometimes '0 Time'
            $columns{'GMT Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /0 Time/ );
            $columns{'GMT Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /-1 Time/ );
          }
        }
#foreach my $cl (%columns) {
#print ">$cl<\n";
#}
        next;
      }

      # Date
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );
      my $dateinfo = $oWkC->Value;
      next if( ! $dateinfo );

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'GMT Time'}];
      next if( ! $oWkC );
      my $time = $oWkC->Value;
      next if( ! $time );

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'English Prog Title'}];
      next if( ! $oWkC );
      my $engtitle = $oWkC->Value;
      next if( ! $engtitle );

      # Episode title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'English Eps Title'}];
      next if( ! $oWkC );
      my $episodetitle = $oWkC->Value;

      # Program Synopsis
      $oWkC = $oWkS->{Cells}[$iR][$columns{'English Prog Synopsis'}];
      next if( ! $oWkC );
      my $synopsis = $oWkC->Value;

      # Genre
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Genre'}];
      next if( ! $oWkC );
      my $genre = $oWkC->Value;

      my $date = ParseDate( $dateinfo );

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }
        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "03:00" );
        $currdate = $date;

        progress("Jetix FlatXLS: $xmltvid: Date is: $date");
      }

      progress( "Jetix FlatXLS: $xmltvid: $time - $engtitle" );

      my $ce = {
        channel_id => $channel_id,
        title => $engtitle,
        start_time => $time,
      };

      $ce->{subtitle} = $episodetitle if $episodetitle;
      $ce->{description} = $synopsis if $synopsis;

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'Jetix', $genre );
        AddCategory( $ce, $program_type, $category );
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
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "Jetix GridXLS: $xmltvid: Processing $file" );

  my $coltime = 0;  # the time is in the column no. 0
  my $firstcol = 1;  # first column - monday
  my $lastcol = 7;  # last column - sunday
  my $firstrow = 4;  # schedules are starting from this row

  my @shows = ();
  my ( $firstdate, $lastdate );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    next if( $oWkS->{Name} =~ /Highlights/i );

    progress( "Jetix GridXLS: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    ( $firstdate, $lastdate ) = ParsePeriod( $oWkS->{Name} );
    progress( "Jetix GridXLS: $xmltvid: Importing data for period from " . $firstdate->ymd("-") . " to " . $lastdate->ymd("-") );
    my $period = $lastdate - $firstdate;
    my $spreadweeks = int( $period->delta_days / 7 ) + 1;
    if( $period->delta_days > 6 ){
      progress( "Jetix GridXLS: $xmltvid: Schedules scheme will spread accross $spreadweeks weeks" );
    }

    my $dayno = 0;

    # browse through columns
    for(my $iC = $firstcol ; $iC <= $lastcol ; $iC++) {

print "kolona $iC dayno $dayno\n";

      # browse through rows
      # start at row firstrow
      for(my $iR = $firstrow ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        my $text = $oWkC->Value;
        next if( ! $text );
print "$iR $iC >$text<\n";

        my $title = $text;

        # fetch the time from $coltime column
        $oWkC = $oWkS->{Cells}[$iR][$coltime];
        next if( ! $oWkC );
        my $time = $oWkC->Value;
        next if( ! $time );
        next if( $time =~ /^KEY$/ );
print "$iR $iC >$time<\n";

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
print "dayoff $dayoff\n";
          $oWkC = $oWkS->{Cells}[$iR][$c];
          if( ! $oWkC->Value ){
print "spread " . $show->{title} . "\n";
            @{$shows[ $dayno + ($c - $iC) ]} = () if not $shows[ $dayno + ($c - $iC) ];
            push( @{$shows[ $dayno + ($c - $iC) ]} , $show );
          } else {
            last;
          }
        }

      } # next row
print "zadnje u koloni $iC\n----------------\n";

      $dayno++;

    } # next column

    if( $spreadweeks ){
      @shows = SpreadWeeks( $spreadweeks, @shows );
    }

    FlushData( $dsh, $firstdate, $lastdate, $channel_id, $xmltvid, @shows );

  } # next worksheet

  return;
}

sub SpreadWeeks {
  my ( $spreadweeks, @shows ) = @_;

print "SpreadWeeks 1\n";
  for( my $w = 1; $w < $spreadweeks; $w++ ){
    for( my $d = 0; $d < 7; $d++ ){
      my @tmpshows = @{$shows[$d]};
      @{$shows[ ( $w * 7 ) + $d ]} = @tmpshows;
    }
  }

print "SpreadWeeks 2\n";
  return @shows;
}

sub FlushData {
  my ( $dsh, $firstdate, $lastdate, $channel_id, $xmltvid, @shows ) = @_;

  my $date = $firstdate;
  my $currdate = "x";

  # run through the shows
  foreach my $dayshows ( @shows ) {

    if( $date ) {

      progress( "Jetix GridXLS: $xmltvid: Date is " . $date->ymd("-") );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ){
          $dsh->EndBatch( 1 );
        }

        my $batch_id = "${xmltvid}_" . $date->ymd("-");
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date->ymd("-") , "06:00" );
        $currdate = $date->clone;
      }
    }

    foreach my $s ( @{$dayshows} ) {

      progress( "Jetix GridXLS: $xmltvid: $s->{start_time} - $s->{title}" );

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

print "ParsePeriod >$text<\n";
  my( $day1, $monthname1 );
  my( $day2, $monthname2 );

  # format '28th July - 3rd August'
  if( $text =~ /^\s*\d+(st|nd|rd|th)\s+\S+\s*-\s*\d+(st|nd|rd|th)\s+\S+\s*$/i ){
    ( $day1, $monthname1, $day2, $monthname2 ) = ( $text =~ /^\s*(\d+)\S+\s+(\S+)\s*-\s*(\d+)\S+\s+(\S+)\s*$/ );
  }

  # format '2 Feb - 8 Feb'
  if( $text =~ /^\s*\d+\s+\S+\s*-\s*\d+\s+\S+\s*$/i ){
    ( $day1, $monthname1, $day2, $monthname2 ) = ( $text =~ /^\s*(\d+)\s+(\S+)\s*-\s*(\d+)\s+(\S+)\s*$/ );
  }

  # format '4th - 10th Aug'
  elsif( $text =~ /^\s*\d+(st|nd|rd|th)\s*-\s*\d+(st|nd|rd|th)\s+\S+\s*$/i ){
    ( $day1, $day2, $monthname1 ) = ( $text =~ /^\s*(\d+)\S+\s*-\s*(\d+)\S+\s+(\S+)\s*$/ );
    $monthname2 = $monthname1;
  }

  # format 'JETIX PLAY 7th July to 3rd Aug'
  elsif( $text =~ /^\s*JETIX PLAY\s+\d+(st|nd|rd|th)\s+\S+\s+to\s+\d+(st|nd|rd|th)\s+\S+\s*$/i ){
    ( $day1, $monthname1, $day2, $monthname2 ) = ( $text =~ /^\s*JETIX PLAY\s+(\d+)\S+\s+(\S+)\s+to\s+(\d+)\S+\s+(\S+)\s*$/ );
  }

print "ParsePeriod DAY1: $day1\n";
print "ParsePeriod MON1: $monthname1\n";
print "ParsePeriod DAY2: $day2\n";
print "ParsePeriod MON2: $monthname2\n";

  my $year = 2009;

  my $month1 = MonthNumber( $monthname1 , 'en' );

  my $dt1 = DateTime->new( year   => $year,
                          month  => $month1,
                          day    => $day1,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/London',
                          );

  #$dt1->set_time_zone( "UTC" );

  my $month2 = MonthNumber( $monthname2 , 'en' );

  my $dt2 = DateTime->new( year   => $year,
                          month  => $month2,
                          day    => $day2,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/London',
                          );

  #$dt2->set_time_zone( "UTC" );

  return ( $dt1, $dt2 );
}

sub SetDate {
  my ( $first, $off ) = @_;

  my $d = $first->clone->add( days => ( $off - 1 ) );

  return $d;
}

sub ParseDate {
  my ( $text ) = @_;

  my( $day, $monthname, $year ) = ( $text =~ /^(\d+)-(\S+)-(\d+)$/ );

  my $month = MonthNumber( $monthname , 'en' );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}


1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
