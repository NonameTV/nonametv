package NonameTV::Importer::ZoneMedia;

use strict;
use warnings;

=pod

Import data from XLS files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

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

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  $self->{MinMonths} = 1 unless defined $self->{MinMonths};
  $self->{MaxMonths} = 12 unless defined $self->{MaxMonths};

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Zagreb" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

#return if ( $chd->{xmltvid} !~ /reality/ );

  my $ft = CheckFileFormat( $file );

  if( $ft eq FT_GRIDXLS ){
    $self->ImportGridXLS( $file, $chd );
  } elsif( $ft eq FT_FLATXLS ){
    $self->ImportFlatXLS( $file, $chd );
  } else {
    progress( "ZoneMedia: $chd->{xmltvid}: Unknown format of the file $file" );
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
  return FT_UNKNOWN if( ! $oBook->{SheetCount} );

  # test print
#  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
#    my $oWkS = $oBook->{Worksheet}[$iSheet];
#    print $oWkS->{Name} . "\n";
#    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++){
#      for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++){
#        my $oWkC = $oWkS->{Cells}[$iR][$iC];
#        next if( ! $oWkC );
#        next if( ! $oWkC->Value );
#        print "$iR $iC: " . $oWkC->Value . "\n";
#      }
#    }
#  }

  # Grid XLS
  # if sheet[0] -> cell[0][0] = "^ZONE CLUB" => FT_GRIDXLS
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
    my $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} =~ /^\d+/ ){
      my $oWkC = $oWkS->{Cells}[0][0];
      if( $oWkC and $oWkC->Value =~ /^ZONE CLUB/ ){
        return FT_GRIDXLS;
      }
    }
  }

  # Flat XLS
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
    my $oWkS = $oBook->{Worksheet}[$iSheet];
    my $oWkC = $oWkS->{Cells}[0][0];
    if( $oWkC and ( $oWkC->Value =~ /^Tx Date$/i ) or ( $oWkC->Value =~ /^schedule_date$/i ) ){
      return FT_FLATXLS;
    }
  }

  return FT_UNKNOWN;
}
    

sub ImportGridXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "ZoneMedia GridXLS: $chd->{xmltvid}: Processing $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  my $daterow = 1;
  my $startrow = 3;
  my $timecol = 0;
  my $date;
  my $currdate = "x";

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    if( $oWkS->{Name} =~ /^Premiere$/i or $oWkS->{Name} =~ /^INDEX$/i ){
      next;
    }

    progress( "ZoneMedia GridXLS: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++){

      my $oWkC = $oWkS->{Cells}[$daterow][$iC];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );

      if( $date ){

        progress("ZoneMedia GridXLS: $chd->{xmltvid}: Date is $date");

        if( ( $date ne $currdate ) and ( $currdate ne "x" ) ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batch_id , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;
      }

      for(my $iR = $startrow ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++){

        # title
        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $title = $oWkC->Value;

        # time
        $oWkC = $oWkS->{Cells}[$iR][$timecol];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $time = $oWkC->Value;

        progress("ZoneMedia GridXLS: $chd->{xmltvid}: $time - $title");

        my $ce = {
          channel_id => $chd->{id},
          start_time => $time,
          title => norm($title),
        };

        $dsh->AddProgramme( $ce );
      }



    } # next column

  }

  $dsh->EndBatch( 1 );

  return;
}


sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "ZoneMedia FlatXLS: $chd->{xmltvid}: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    if( $chd->{xmltvid} =~ /extreme/ and $oWkS->{Name} !~ /ENG/ ){
      next;
    }

    progress( "ZoneMedia FlatXLS: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    # schedules are starting after that
    # valid schedule row must have date, time and title set
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          next if( ! $oWkS->{Cells}[$iR][$iC] );
          next if( ! $oWkS->{Cells}[$iR][$iC]->Value );

          $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

          $columns{'DATE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Tx Date/i );
          $columns{'DATE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^schedule_date/i );

          $columns{'TIME'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Billed Start/i );
          $columns{'TIME'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^start_time/i );

          $columns{'DURATION'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^duration/i );

          $columns{'TITLE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Title/i );
          $columns{'TITLE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^event_title/i );

          $columns{'EPISODETITLE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Episode Title/i );
          $columns{'EPISODETITLE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^event_episode_title/i );

          $columns{'DESCRIPTION'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^event_short_description/i );

          $columns{'GENRE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^genre/i );

          $columns{'SUBGENRE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^sub_genre/i );

          $columns{'EPISODE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Episode number/i );
          $columns{'EPISODE'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^episode_number/i );

          $columns{'SEASON'} = $iC if ( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Season/i );

        }

foreach my $cl (%columns) {
print "COL >$cl<\n";
}
        next;
      }

      my $oWkC;

      # date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DATE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("ZoneMedia FlatXLS: $chd->{xmltvid}: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batch_id , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;
      }

      # time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );

      # title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TITLE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value if( $oWkC->Value );
      next if( ! $title );

      # episode_title
      my $episode_title;
      if( $columns{'EPISODETITLE'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'EPISODETITLE'}];
        if( $oWkC and $oWkC->Value ){
          $episode_title = $oWkC->Value if( $oWkC->Value );
        }
      }

      # episode_number
      my $episode_number;
      if( $columns{'EPISODE'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'EPISODE'}];
        if( $oWkC and $oWkC->Value ){
          $episode_number = $oWkC->Value if( $oWkC->Value );
        }
      }

      # season
      my $season;
      if( $columns{'SEASON'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'SEASON'}];
        if( $oWkC and $oWkC->Value ){
          $season = $oWkC->Value if( $oWkC->Value );
        }
      }

      # description
      my $description;
      if( $columns{'DESCRIPTION'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'DESCRIPTION'}];
        if( $oWkC and $oWkC->Value ){
          $description = $oWkC->Value if( $oWkC->Value );
        }
      }

      progress("ZoneMedia FlatXLS: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      if( $episode_number ){
        if( $season ){
          $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode_number-1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $episode_number-1 );
        }
      }

      $ce->{subtitle} = $episode_title if $episode_title;
      $ce->{description} = $description if $description;

      $dsh->AddProgramme( $ce );
    }

    %columns = ();

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  $dinfo =~ s/^\s*//;
  $dinfo =~ s/\s*$//;
#print ">$dinfo<\n";

  my( $day, $month, $year );

  # format '10-31-09'
  if( $dinfo =~ /^\d+-\d+-\d+$/ ){
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  }

  # format '29 03 2010'
  elsif( $dinfo =~ /^\d+ \d+ \d+$/ ){
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+) (\d+) (\d+)$/ );
  }

  # format '29/03/2010'
  elsif( $dinfo =~ /^\d+\/\d+\/\d+$/ ){
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  else {
    return undef;
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

#print "ParseTime: >$text<\n";

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  } elsif( $text =~ /^0\.\d+$/){ # format '0.377962962962964'
    my $daysecs = int( 86400 * $text );
    $hour = int( $daysecs / 3600 );
    $min =  int( ( $daysecs - ( $hour * 3600 ) ) / 60 );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

sub UpdateFiles {
  my( $self ) = @_;

  # get current month name
  my $year = DateTime->today->strftime( '%g' );

  # the url to fetch data from
  # is in the format http://newsroom.zonemedia.net/Files/Schedules/CLPE1009L01.xls
  # UrlRoot = http://newsroom.zonemedia.net/Files/Schedules/
  # GrabberInfo = <empty>

  foreach my $data ( @{$self->ListChannels()} ) {

    my $xmltvid = $data->{xmltvid};

    my $today = DateTime->today;

    # do it for MaxMonths in advance
    for(my $month=0; $month <= $self->{MaxMonths} ; $month++) {

      my $dt = $today->clone->add( months => $month );

      for( my $v=1; $v<=3; $v++ ){

        foreach my $sufix ( qw/V L/ ){
          my $filename = sprintf( "%s%02d%02d%s%02d.xls", $data->{grabber_info}, $dt->month, $dt->strftime( '%y' ), $sufix, $v );
          my $url = $self->{UrlRoot} . "/" . $filename;
          progress("ZoneMedia: $xmltvid: Fetching xls file from $url");
          http_get( $url, $self->{FileStore} . '/' . $xmltvid . '/' . $filename );
        }

      }
    }
  }
}

sub http_get {
  my( $url, $file ) = @_;

  qx[curl -s -S -z "$file" -o "$file" "$url"];
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
