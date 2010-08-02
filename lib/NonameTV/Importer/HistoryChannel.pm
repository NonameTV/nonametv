package NonameTV::Importer::HistoryChannel;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.
The files are received in zip archives.

Features:

=cut

use utf8;

use DateTime;
use Archive::Zip;
use Archive::Zip qw( :ERROR_CODES );
use File::Basename;
use Spreadsheet::ParseExcel;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
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

  my $channel_id = $chd->{id};
  my $xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.zip$/i ){
    $self->UnzipArchive( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "HistoryChannel: $xmltvid: Unknown file format: $file" );
  }

  return;
}

sub UnzipArchive {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  # Only process .zip files.
  return if( $file !~ /\.zip$/i );

  progress( "HistoryChannel: $xmltvid: Processing $file" );

  # Unzip files
  progress( "HistoryChannel: $xmltvid: Extracting files from zip file $file" );

  my $dirname = dirname( $file );
  chdir $dirname;

  my $zip = Archive::Zip->new();
  unless ( $zip->read( $file ) == AZ_OK ) {
    error( "HistoryChannel: $xmltvid: Error while reading $file" );
  }

  my @members = $zip->memberNames();
  foreach my $member (@members) {
    progress( "HistoryChannel: $xmltvid: Extracting $member" );
    $zip->extractMemberWithoutPaths( $member );
  }

  my $res = $zip->Extract( -quiet );
  error( "HistoryChannel: $xmltvid: Error $res while extracting from $file" ) if ( $res );

  return;
}

sub ImportXLS {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );

  progress( "HistoryChannel: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $batch_id = $xmltvid . "_" . $file;
  $ds->StartBatch( $batch_id , $channel_id );

  my $fileyear;
  if( $file =~ /\s+2\d{3}\s+/ ){
    ( $fileyear ) = ( $file =~ /\s+(2\d{3})\s+/ );
  }

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    next if( $oWkS->{Name} !~ /Croatian/i );
    progress( "HistoryChannel: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          $columns{norm($oWkS->{Cells}[$iR][$iC]->Value)} = $iC;
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}
        next;
      }

      # date - column 0 ('DATE')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'DATE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $fileyear, $oWkC->Value );
      next if( ! $date );

      # starttime - column ('START TIME')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'START TIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $starttime = create_dt( $date , $oWkC->Value );
      next if( ! $starttime );

      # endtime - column ('END TIME')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'END TIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $endtime = create_dt( $date , $oWkC->Value );
      next if( ! $endtime );

      if( $endtime < $starttime ){
        $endtime = $endtime->add( days => 1 );
      }

      # duration - column ('DURATION')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DURATION'}];
      next if( ! $oWkC );
      my $duration = $oWkC->Value if( $oWkC->Value );

      # title - column ('PROGRAMME TITLE (max 40 characters)')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'PROGRAMME TITLE (max 40 characters)'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      # short description - column ('Short Description (max 100 characters)')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Short Description (max 100 characters)'}];
      next if( ! $oWkC );
      my $shortdesc = $oWkC->Value;

      # long description - column ('Long Description (max 235 characters)')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Long Description (max 235 characters)'}];
      next if( ! $oWkC );
      my $longdesc = $oWkC->Value;

      # rating - column ('RATING')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'RATING'}];
      next if( ! $oWkC );
      my $rating = $oWkC->Value if( $oWkC->Value );

      # crotitle - column ('Croatian Titles (max 40)')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Croatian Titles (max 40)'}];
      next if( ! $oWkC );
      my $crotitle = $oWkC->Value if( $oWkC->Value );
      next if( ! $crotitle );

      # croatian description - column ('Croatian description (max 120)')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Croatian description (max 120)'}];
      next if( ! $oWkC );
      my $crodesc = $oWkC->Value;

      progress("HistoryChannel: $xmltvid: $starttime - $title");

      my $ce = {
        channel_id   => $channel_id,
        start_time   => $starttime->ymd("-") . " " . $starttime->hms(":"),
        end_time     => $endtime->ymd("-") . " " . $endtime->hms(":"),
        title        => $crotitle || $title,
      };

      $ce->{subtitle} = $title if $title;

      $ce->{description} = $crodesc if $crodesc;
      $ce->{description} .= "\n\n" if $ce->{description};
      $ce->{description} .= $longdesc if $longdesc;

      $ds->AddProgramme( $ce );
    }

    %columns = ();

  }

  $ds->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $fy, $dinfo ) = @_;

#print "$dinfo\n";

  my( $month, $day, $year, $monthname );

  if( $dinfo =~ /\d+-\d+-\d+/ ){
    ( $month, $day, $year ) = ( $dinfo =~ /(\d+)-(\d+)-(\d+)/ );
  } elsif( $dinfo =~ /\d+-\S+/ ){
    ( $day, $monthname ) = ( $dinfo =~ /(\d+)-(\S+)/ );
    $month = MonthNumber( $monthname, "hr" );
  }

  if( ! $year ){
    if( $fy ){
      $year = $fy;
    } else {
      $year = DateTime->today->year;
    }
  }

  $year+= 2000 if $year< 100;

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/London',
                          );

  #$dt->set_time_zone( "UTC" );

  return $dt;
}

sub create_dt
{
  my( $date, $time ) = @_;

  my( $hour, $min ) = ( $time =~ /(\d+):(\d+)/ );

  my $dt = $date->clone()->add( hours => $hour , minutes => $min );

  return $dt;
}

sub create_endtime
{
  my( $start, $dur ) = @_;

  my( $hour, $min, $sec, $cent ) = ( $dur =~ /^(\d+):(\d+):(\d+):(\d+)$/ );

  my $dt = $start->clone()->add( hours => $hour , minutes => $min , seconds => $sec );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
