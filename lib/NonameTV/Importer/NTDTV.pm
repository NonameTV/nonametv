package NonameTV::Importer::NTDTV;

use strict;
use warnings;

=pod

Import data from xls files delivered via e-mail.
Each day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, 'US/Eastern' );
  $self->{datastorehelper} = $dsh;

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

  if( $file =~ /\.xls$/i ){
    $self->ImportGridXLS( $file, $channel_id, $channel_xmltvid );
  }
}

sub ImportGridXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "NTDTV: $xmltvid: Processing $file" );

  # the month should be extracted from the filename
  my( $dtstart, $firstdate, $lastdate ) = ParsePeriod( $file );
  if( not $dtstart ){
    error("NTDTV: $xmltvid: Unable to determine period for which the data are");
    return;
  }

  my $coltime = 0;  # the time is in the column no. 0
  my $firstcol = 1;  # first column - monday
  my $lastcol = 7;  # last column - sunday
  my $firstrow = 1;  # schedules are starting from this row

  my @shows = ();

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "NTDTV: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    progress( "NTDTV: $xmltvid: Importing data for period from " . $firstdate->ymd("-") . " to " . $lastdate->ymd("-") );

    # The DateTime::Duration sometimes returns wrong number
    # of weeks for the period given. Therefore we will
    # spread it over 6 weeks to be sure that we have covered the whole month
    #my $period = $lastdate - $firstdate;
    #my $spreadweeks = int( $period->delta_days / 7 ) + 1;
    #my $spreadweeks = $period->weeks;
    my $spreadweeks = 6;

    progress( "NTDTV: $xmltvid: Schedules scheme will spread accross $spreadweeks weeks" );

    my $dayno = 0;

    # browse through columns
    for(my $iC = $firstcol ; $iC <= $lastcol ; $iC++) {

      # browse through rows
      # start at row firstrow
      for(my $iR = $firstrow ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        my $text = $oWkC->Value;
        next if( ! $text );

        my $title = $text;

        # fetch the time from $coltime column
        $oWkC = $oWkS->{Cells}[$iR][$coltime];
        next if( ! $oWkC );
        my $time = $oWkC->Value;
        next if( ! $time );

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

    # spread shows accross weeks
    if( $spreadweeks ){
      @shows = SpreadWeeks( $spreadweeks, @shows );
    }

    FlushData( $dsh, $dtstart, $firstdate, $lastdate, $channel_id, $xmltvid, @shows );

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
    my @tmpshows = sort bytime @{$shows[$d]};
    @{$shows[$d]} = @tmpshows;
  }

  return @shows;
}

sub SpreadWeeks {
  my ( $spreadweeks, @shows ) = @_;

  for( my $w = 1; $w < $spreadweeks; $w++ ){
    for( my $d = 0; $d < 7; $d++ ){
      my @tmpshows = @{$shows[$d]};
      @{$shows[ ( $w * 7 ) + $d ]} = @tmpshows;
    }
  }

  return @shows;
}

sub FlushData {
  my ( $dsh, $dtstart, $firstdate, $lastdate, $channel_id, $xmltvid, @shows ) = @_;

  my $date = $dtstart;
  my $currdate = "x";

  # run through the shows
  foreach my $dayshows ( @shows ) {

    if( $date < $firstdate or $date > $lastdate ){
      progress( "NTDTV: $xmltvid: Date " . $date->ymd("-") . " is outside of the month " . $firstdate->month_name . " -> skipping" );
      $date->add( days => 1 );
      next;
    }

    progress( "NTDTV: $xmltvid: Date is " . $date->ymd("-") );

    if( $date ne $currdate ) {

      if( $currdate ne "x" ){
        $dsh->EndBatch( 1 );
      }

      my $batch_id = "${xmltvid}_" . $date->ymd("-");
      $dsh->StartBatch( $batch_id, $channel_id );
      $dsh->StartDate( $date->ymd("-") , "06:00" );
      $currdate = $date->clone;
    }

    foreach my $s ( @{$dayshows} ) {

      progress( "NTDTV: $xmltvid: $s->{start_time} - $s->{title}" );

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

  my @days = qw/Monday Tuesday Wednesday Thursday Friday Saturday Sunday/;

  # format 'ProgSchedule_Frame_TV_Guide_12-2008_USEast Eng.xls'
  my( $month, $year ) = ( $text =~ /TV_Guide_(\d+)-(\d+)/ );

  if ( not $month or not $year ){
    error("Error while parsing filename");
    return( undef, undef, undef );
  }

  my $firstdate = DateTime->new( year   => $year,
                                 month  => $month,
                                 day    => 1,
                                 hour   => 0,
                                 minute => 0,
                                 second => 0,
                                 time_zone => 'US/Eastern',
                                 );

  # find the name of the first day of the month
  my $firstday = $firstdate->day_name;

  # find the name of the last day of the month
  my $lastdate = DateTime->last_day_of_month( year => $year, month => $month );

  # the schedules data is on weekly basis
  # find the offset, or how many days it spreads to previous month
  my $offset = -1;
  for( my $i = 0; $i < scalar(@days); $i++ ){
    if( $days[$i] eq $firstday ){
      $offset = $i;
    }
  }

  if( $offset eq -1 ){
    error("Can't determine day offset");
    return( undef, undef, undef );
  }

  # find the first date which can be covered by this schedule
  # we will skip later the dates not from the correct month
  my $dtstart = $firstdate->clone->subtract( days => $offset );

  return( $dtstart, $firstdate, $lastdate );
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
