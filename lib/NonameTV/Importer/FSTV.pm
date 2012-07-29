package NonameTV::Importer::FSTV;

use strict;
use warnings;

=pod

Import data from FSTV (Footschool) Excel files delivered via e-mail.
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

use NonameTV qw/norm AddCategory/;
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

  # Unzip files
  if( $file =~ /\.zip$/i ){
    progress( "FSTV: $xmltvid: Extracting files from zip file $file" );

    my $dirname = dirname( $file );
    chdir $dirname;

    my $zip = Archive::Zip->new();
    unless ( $zip->read( $file ) == AZ_OK ) {
      error( "FSTV: $xmltvid: Error while reading $file" );
    }

    my @members = $zip->memberNames();
    foreach my $member (@members) {
      progress( "FSTV: $xmltvid: Extracting $member" );
      $zip->extractMemberWithoutPaths( $member );
    }

    my $res = $zip->Extract( -quiet );
    error( "FSTV: $xmltvid: Error $res while extracting from $file" ) if ( $res );

    return;
  }

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "FSTV: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $batch_id = $xmltvid . "_" . $file;
  $ds->StartBatch( $batch_id , $channel_id );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "FSTV: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # get the names of the columns from the 4th row
    if( not %columns ){
      for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
	my $oWkC = $oWkS->{Cells}[3][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        $columns{ $oWkC->Value } = $iC;
      }
    }
#foreach my $cl (%columns) {
#print "$cl\n";
#}

    # browse through rows
    # start at row #5
    for(my $iR = 4 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # skip empty lines
      # or the line with the title in format 'FSTV 2008 November 01st'
      my $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      next if( $oWkC->Value =~ /^FSTV\s+\d{4}/ );

      # date - column 0 ('Date')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      # starttime - column ('Start Time')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Start Time'}];
      next if( ! $oWkC );
      my $starttime = create_dt( $date , $oWkC->Value ) if( $oWkC->Value );
      next if( ! $starttime );

      # title - column ('Event title')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Event title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      # duration - column ('Duration')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Duration'}];
      #next if( ! $oWkC );
      my $duration = $oWkC->Value if( $oWkC->Value );

      my $endtime = create_endtime( $starttime , $duration );
      next if( ! $endtime );

      # subtitle - column ('Serie')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Serie'}];
      my $subtitle = $oWkC->Value if( $oWkC->Value );

      progress("FSTV: $xmltvid: $starttime - $title");

      my $ce = {
        channel_id   => $channel_id,
        start_time   => $starttime->ymd("-") . " " . $starttime->hms(":"),
        end_time     => $endtime->ymd("-") . " " . $endtime->hms(":"),
        title        => $title,
      };

      $ce->{subtitle} = $subtitle if $subtitle;

      $ds->AddProgramme( $ce );
    }

    %columns = ();

  }

  $ds->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $month, $day, $year );

  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d+-\d+-\d+$/ ){
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  }

  return undef if( ! $year);

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

  my( $hour, $min, $sec, $frame ) = ( $time =~ /^(\d+):(\d+):(\d+):(\d+)$/ );

  my $dt = $date->clone()->add( hours => $hour , minutes => $min, seconds => $sec );

  return $dt;
}

sub create_endtime
{
  my( $start, $dur ) = @_;

  my( $hour, $min, $sec, $frame ) = ( $dur =~ /^(\d+):(\d+):(\d+):(\d+)$/ );

  my $dt = $start->clone()->add( hours => $hour , minutes => $min , seconds => $sec );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
