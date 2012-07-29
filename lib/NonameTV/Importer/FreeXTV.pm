package NonameTV::Importer::FreeXTV;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.
The files are received in rar archives.

Features:

=cut

use utf8;

use DateTime;
use Archive::Rar;
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

  # Unrar files
  if( $file =~ /\.rar$/i ){
    progress( "FreeXTV: $xmltvid: Extracting files from rar file $file" );

    my $dirname = dirname( $file );
    chdir $dirname;

    my $rar = Archive::Rar->new( -archive => $file );
    $rar->List();

    my $res = $rar->Extract( -quiet );
    error( "FreeXTV: $xmltvid: Error $res while extracting from $file" ) if ( $res );

    return;
  }

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "FreeXTV: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $batch_id = $xmltvid . "_" . $file;
  $ds->StartBatch( $batch_id , $channel_id );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "FreeXTV: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

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

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      # starttime - column ('HEURE DIF')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'HEURE DIF'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $starttime = create_dt( $date , $oWkC->Value ) if( $oWkC->Value );
      next if( ! $starttime );

      # title - column ('TITRE')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TITRE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value if( $oWkC->Value );

      # duration - column ('DUREE')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DUREE'}];
      #next if( ! $oWkC );
      #next if( ! $oWkC->Value );
      my $duration = $oWkC->Value if( $oWkC->Value );

      my $endtime = create_endtime( $starttime , $duration );
      next if( ! $endtime );

      # genre - column ('GENRE')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'GENRE'}];
      #next if( ! $oWkC );
      #next if( ! $oWkC->Value );
      my $genre = $oWkC->Value if( $oWkC->Value );

      # language - column ('LANGUE')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'LANGUE'}];
      #next if( ! $oWkC );
      my $language = $oWkC->Value if( $oWkC->Value );

      progress("FreeXTV: $xmltvid: $starttime - $title");

      my $ce = {
        channel_id   => $channel_id,
        start_time   => $starttime->ymd("-") . " " . $starttime->hms(":"),
        end_time     => $endtime->ymd("-") . " " . $endtime->hms(":"),
        title        => $title,
      };

      # genre
      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( "FreeXTV", $genre );
        AddCategory( $ce, $program_type, $category );
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
  my ( $dinfo ) = @_;

#print "ParseDate >$dinfo<\n";

  my( $month, $day, $year );

  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d{4})-(\d{2})-(\d{2})$/ );
  } else {
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
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
