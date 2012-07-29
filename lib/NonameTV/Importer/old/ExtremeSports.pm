package NonameTV::Importer::ExtremeSports;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail or fetched from web.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory/;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

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
  progress( "ExtremeSports: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";


  my $batch_id = $xmltvid . "_" . $file;
  $ds->StartBatch( $batch_id , $channel_id );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} !~ /Extreme PE Eng/i and $oWkS->{Name} !~ /Extreme_ENG/i and $oWkS->{Name} !~ /Extreme_DEU/i ){
      error( "ExtremeSports: $chd->{xmltvid}: Skipping worksheet: $oWkS->{Name}" );
      next;
    }
    progress( "ExtremeSports: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          $columns{norm($oWkS->{Cells}[$iR][$iC]->Value)} = $iC;
        }
        next;
      }

      # date - column 0 ('schedule_date')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'schedule_date'}];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      # starttime - column ('start_time')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'start_time'}];
      next if( ! $oWkC );
      my $starttime = create_dt( $date , $oWkC->Value ) if( $oWkC->Value );
      next if( ! $starttime );

      # duration - column ('duration')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'duration'}];
      next if( ! $oWkC );
      my $endtime = create_dt_addduration( $starttime , $oWkC->Value ) if( $oWkC->Value );
      next if( ! $endtime );

      # title - column ('event_title')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'event_title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      next if( ! $title );

      my $episodetitle = $oWkS->{Cells}[$iR][$columns{'event_episode_title'}]->Value if $oWkS->{Cells}[$iR][$columns{'event_episode_title'}];
      my $description = $oWkS->{Cells}[$iR][$columns{'event_short_description'}]->Value if $oWkS->{Cells}[$iR][$columns{'event_short_description'}];
      my $episodenumber = $oWkS->{Cells}[$iR][$columns{'episode_number'}]->Value if $oWkS->{Cells}[$iR][$columns{'episode_number'}];

      progress("ExtremeSports: $xmltvid: $starttime - $title");

      my $ce = {
        channel_id   => $channel_id,
        start_time   => $starttime->ymd("-") . " " . $starttime->hms(":"),
        end_time     => $endtime->ymd("-") . " " . $endtime->hms(":"),
        title        => $title,
      };

      # subtitle
      if( $episodetitle ){
        $ce->{subtitle} = $episodetitle;
      }

      # description
      if( $description ){
        $ce->{description} = $description;
      }

      # episode
      if( $episodenumber ){
        $ce->{episode} = sprintf( ". %d .", $episodenumber-1 );
        $ce->{program_type} = 'series';
      }

      $ds->AddProgramme( $ce );
    }

    %columns = ();

  }

  $ds->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $text ) = @_;

  my( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );

  return undef if( ! $year);

  $year+= 2000 if $year< 100;

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
                          );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

sub create_dt
{
  my( $date, $time ) = @_;

  my( $hour, $min ) = ( $time =~ /^(\d+):(\d+)$/ );

  my $dt = $date->clone()->add( hours => $hour , minutes => $min );

  return $dt;
}

sub create_dt_addduration
{
  my( $firsttime, $duration ) = @_;

  my( $hour, $min, $sec ) = ( $duration =~ /^(\d+):(\d+):(\d+)$/ );

  my $dt = $firsttime->clone()->add( hours => $hour , minutes => $min , seconds => $sec );

  return $dt;
}

sub UpdateFiles {
  my( $self ) = @_;

  # get current month name
  my $year = DateTime->today->strftime( '%g' );

  # the url to fetch data from
  # is in the format http://newsroom.zonemedia.net/Files/Schedules/EXPE1109L01.xls
  # UrlRoot = http://newsroom.zonemedia.net/Files/Schedules/
  # GrabberInfo = <empty>

  foreach my $data ( @{$self->ListChannels()} ) {

    my $xmltvid = $data->{xmltvid};

    my $today = DateTime->today;

    # do it for MaxMonths in advance
    for(my $month=0; $month <= $self->{MaxMonths} ; $month++) {

      my $dt = $today->clone->add( months => $month );

      for( my $v=1; $v<=3; $v++ ){
        my $filename = sprintf( "EXPE%02d%02dL%02d.xls", $dt->month, $dt->strftime( '%y' ), $v );
        my $url = $self->{UrlRoot} . "/" . $filename;
        progress("ZoneReality: $xmltvid: Fetching xls file from $url");
        http_get( $url, $self->{FileStore} . '/' . $xmltvid . '/' . $filename );
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
