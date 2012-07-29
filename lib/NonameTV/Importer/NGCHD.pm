package NonameTV::Importer::NGCHD;

#use strict;
#use warnings;

=pod

Import data from Xls files delivered via e-mail.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use Encode;
use Encode::Guess;
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

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $ft = CheckFileFormat( $file );

  if( $ft eq FT_FLATXLS ){
    $self->ImportFlatXLS( $file, $channel_id, $channel_xmltvid );
  } elsif( $ft eq FT_GRIDXLS ){
    $self->ImportGridXLS( $file, $channel_id, $channel_xmltvid );
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

  # the content of this cell shoul be 'PROGRAM/ EmisiA3n'
  for(my $iW = 0 ; $iW <= $oBook->{SheetCount} ; $iW++) {
    my $oWkS = $oBook->{Worksheet}[$iW];
    for(my $iR = 0 ; $iR <= 5 ; $iR++) {
      for(my $iC = 0 ; $iC <= 5 ; $iC++) {
        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
#print "$iR $iC " . $oWkC->Value . "\n";
        return FT_FLATXLS if( $oWkC->Value =~ /^PROGRAM\// );
      }
    }
  }

  # check the content of the cell[0][3]
  for(my $iW = 0 ; $iW <= $oBook->{SheetCount} ; $iW++) {
    my $oWkS = $oBook->{Worksheet}[$iW];
    for(my $iR = 0 ; $iR <= 5 ; $iR++) {
      for(my $iC = 0 ; $iC <= 5 ; $iC++) {
        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
#print "$iR $iC " . $oWkC->Value . "\n";
        return FT_GRIDXLS if( $oWkC->Value =~ /NATIONAL GEOGRAPHIC CHANNEL HD/ );
      }
    }
  }

  return FT_UNKNOWN;
}


sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "NGCHD Flat XLS: $channel_xmltvid: Processing $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "NGCHD Flat XLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("NGCHD Flat XLS: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){

        # the column names are stored in the row
        # where columns contain: CET-1, CET, CET+1, PROGRAM/ Emisió

        my $found = 0;

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{ norm($oWkS->{Cells}[$iR][$iC]->Value) } = $iC;

            if( $oWkS->{Cells}[$iR][$iC]->Value =~ /CET/ ){
              $columns{DATE} = $iC;
            }

            if( $oWkS->{Cells}[$iR][$iC]->Value =~ /PROGRAM\// ){
              $columns{PROGRAM} = $iC;
              $found = 1;
            }

          }
        }

        %columns = () if not $found;
        next;
      }
#foreach my $cl (%columns) {
#print ">$cl<\n";
#}

      # Date (it is stored in the column 'CET-1'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'CET-1'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      if( isDate( $oWkC->Value ) ){

        $date = ParseDate( $oWkC->Value );

        if( $date ne $currdate ) {
          if( $currdate ne "x" ) {
	    $dsh->EndBatch( 1 );
          }

          my $batch_id = $channel_xmltvid . "_" . $date;
          $dsh->StartBatch( $batch_id , $channel_id );
          $dsh->StartDate( $date , "08:00" );
          $currdate = $date;

          progress("NGCHD Flat XLS: $channel_xmltvid: Date is: $date");
        }

        next;
      }

      # Time Slot
      $oWkC = $oWkS->{Cells}[$iR][$columns{'CET'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;

      if( not defined( $time ) ) {
        error( "Invalid start-time '$date' '$time'. Skipping." );
        next;
      }

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'PROGRAM'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $program = $oWkC->Value;

      # SERIE
      $oWkC = $oWkS->{Cells}[$iR][$columns{'SERIE'}] if $columns{'SERIE'};
      next if( ! $oWkC );
      my $serie = $oWkC->Value;

      # EPISODE TITLE
      $oWkC = $oWkS->{Cells}[$iR][$columns{'EPISODE TITLE'}] if $columns{'EPISODE TITLE'};
      next if( ! $oWkC );
      my $episodetitle = $oWkC->Value;

      my( $title, $episode ) = ParseShow( $program );

      progress( "NGCHD Flat XLS: $channel_xmltvid: $time - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $time,
      };

      $ce->{subtitle} = $serie if $serie;
      #$ce->{decription} = $program if $program;

      #if( $episode ){
        #$ce->{episode} = sprintf( ". %d .", $episode-1 );
      #}

      $ce->{quality} = 'HDTV';

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
  progress( "NGCHD GridXLS: $xmltvid: Processing $file" );

  my $monthname;
  my $month;
  my $year;

  # find the year and month from the filename
  # format: 'NatGeo HD JULY 2010 Schedule.xls'
  if( $file =~ /(january|february|march|aprul|may|june|july|august|september|october|november|december)/i ){
    $monthname = $1;
    $month = MonthNumber( $monthname, 'en' );
  }
  if( $file =~ /(20\d{2})/i ){
    $year = $1;
  }
  if( ! $month or ! $year ){
    error( "NGCHD GridXLS: $xmltvid: Error extracting month and year from filename" );
    return;
  }

  my $coltime = 0;  # the time is in the column no. 0
  my $firstcol = 1;  # first column - monday
  my $lastcol = 7;  # last column - sunday
  my $firstrow = 0;  # schedules are starting from this row

  my @shows = ();
  my ( $firstdate, $lastdate );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  my $dayno = 0;

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    if( $oWkS->{Name} !~ /^WK/i ){
      progress( "NGCHD GridXLS: $xmltvid: Skipping worksheet: $oWkS->{Name}" );
      next;
    }
    progress( "NGCHD GridXLS: $xmltvid: Processing worksheet: $oWkS->{Name}" );

#    ( $firstdate, $lastdate ) = ParsePeriod( $oWkS->{Name} );
#    progress( "NGCHD GridXLS: $xmltvid: Importing data for period from " . $firstdate->ymd("-") . " to " . $lastdate->ymd("-") );
#    my $period = $lastdate - $firstdate;
#    my $spreadweeks = int( $period->delta_days / 7 ) + 1;
#    if( $period->delta_days > 6 ){
#      progress( "NGCHD GridXLS: $xmltvid: Schedules scheme will spread accross $spreadweeks weeks" );
#    }

    # browse through columns
    for(my $iC = $firstcol ; $iC <= $lastcol ; $iC++) {

print "kolona $iC dayno $dayno\n";

      # browse through rows
      # start at row firstrow
      for(my $iR = $firstrow ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $text = $oWkC->Value;
#print "$iR $iC >$text<\n";

        if( isDate( $text ) ){

          my $day = ParseDate($text);
print "DAY $day DAYNO $dayno\n";
          next if( ! $day );

          if( $dayno eq 0 ){
            if( $day eq 1 ){
              $dayno = $day;
              $firstdate = sprintf( "%04d-%02d-%02d", $year, $month, $day ) if not $firstdate;
              $lastdate = sprintf( "%04d-%02d-%02d", $year, $month, $day );
            } else {
              progress( "NGCHD GridXLS: $xmltvid: Skipping day from the previous month: $day" );
            }
          } else {
            $dayno = $day;
            $firstdate = sprintf( "%04d-%02d-%02d", $year, $month, $day ) if not $firstdate;
            $lastdate = sprintf( "%04d-%02d-%02d", $year, $month, $day );
          }
print "DAY $day DAYNO $dayno\n";

print "FD $firstdate LD $lastdate\n";
        }

        next if( $dayno eq 0 );

        my $title = $text;

        # fetch the time from $coltime column
        $oWkC = $oWkS->{Cells}[$iR][$coltime];
        next if( ! $oWkC );
        my $time = $oWkC->Value;
        next if( ! $time );
        next if( $time !~ /\d+:\d+/ );

        my $show = {
          start_time => $time,
          title => $title,
        };
        @{$shows[$dayno - 1]} = () if not $shows[$dayno - 1];
        push( @{$shows[$dayno - 1]} , $show );

        # find to how many columns this column spreads to the right
        # all these days have the same show at this time slot
        for( my $c = $iC + 1 ; $c <= $lastcol ; $c++) {
          $oWkC = $oWkS->{Cells}[$iR][$c];
          if( ! $oWkC->Value ){
            @{$shows[ $dayno - 1 + ($c - $iC) ]} = () if not $shows[ $dayno - 1 + ($c - $iC) ];
            push( @{$shows[ $dayno - 1 + ($c - $iC) ]} , $show );
          } else {
            last;
          }
        }

      } # next row

    } # next column

    FlushData( $dsh, $firstdate, $lastdate, $channel_id, $xmltvid, @shows );
    undef $firstdate;
    undef $lastdate;

  } # next worksheet

  return;
}

sub FlushData {
  my ( $dsh, $firstdate, $lastdate, $channel_id, $xmltvid, @shows ) = @_;

print "FlushData firstdate: $firstdate\n";
print "FlushData lastdate:  $lastdate\n";

  my( $year, $month, $day ) = ( $firstdate =~ /^(\d{4})-(\d{2})-(\d{2})$/ );
  my $fdt = DateTime->new( year   => $year,
                           month  => $month,
                           day    => $day,
                           hour   => 0,
                           minute => 0,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
  );
  ( $year, $month, $day ) = ( $lastdate =~ /^(\d{4})-(\d{2})-(\d{2})$/ );
  my $ldt = DateTime->new( year   => $year,
                           month  => $month,
                           day    => $day,
                           hour   => 0,
                           minute => 0,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
  );

print "FlushData First DATE $fdt\n";
print "FlushData Last  DATE $ldt\n";

  my $date = $fdt;
  my $currdate = "x";

  # run through the shows
  foreach my $dayshows ( @shows ) {

    progress( "NGCHD GridXLS: $xmltvid: Date is " . $date->ymd() );

    if( $date ne $currdate ) {

      if( $currdate ne "x" ){
        $dsh->EndBatch( 1 );
      }

      my $batch_id = "${xmltvid}_" . $date->ymd();
      $dsh->StartBatch( $batch_id, $channel_id );
      $dsh->StartDate( $date->ymd(), "06:00" );
      $currdate = $date->clone();
    }

    foreach my $s ( @{$dayshows} ) {

      progress( "NGCHD GridXLS: $xmltvid: $s->{start_time} - $s->{title}" );

      my $ce = {
        channel_id => $channel_id,
        start_time => $s->{start_time},
        title => $s->{title},
      };

      $dsh->AddProgramme( $ce );

    } # next show in the day

    # increment the date
    $date->add( days => 1 );
    last if( $date gt $ldt );

  } # next day

  $dsh->EndBatch( 1 );

}

sub isDate
{
  my ( $text ) = @_;

#print "isDate >$text<\n";

  # the format is '01-10-08'
  if( $text =~ /^\d{2}-\d{2}-\d{2}$/ ){
    return 1;
  } elsif( $text =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s+\d+$/i ){
    return 1;
  } elsif( $text =~ /^(ponedjeljak|utorak|srijeda|Četvrtak|petak|subota|nedjelja)\s+\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $dayname, $day, $month, $year );

  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # the format is '2010-04-25'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d+-\d+-\d+$/ ){ # the format is '01-10-08'
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s+(\d+)$/i ){
    ( $dayname, $day ) = ( $dinfo =~ /^(\S+)\s+(\d+)$/ );
    return $day;
  } elsif( $dinfo =~ /^(ponedjeljak|utorak|srijeda|Četvrtak|petak|subota|nedjelja)\s+(\d+)$/i ){
    ( $dayname, $day ) = ( $dinfo =~ /^(\S+)\s+(\d+)$/ );
    return $day;
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseShow
{
  my ( $text ) = @_;

  my( $title, $episode );

  if( $text =~ /^.*:\s+Episode\s+\d+/ ){
    ( $title, $episode ) = ( $text =~ /(.*):\s+Episode\s+(\d+)/ );
  } else {
    $title = $text;
  }

  return( $title, $episode );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
