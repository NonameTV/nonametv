package NonameTV::Importer::GOD_Channel;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use File::Temp qw/tempfile/;
use Data::Dumper;

use NonameTV qw/norm MonthNumber/;
use NonameTV::Log qw/progress error/;
use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

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

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "GOD_Channel: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    
    if( $oWkS->{Name} !~ /GMT/ ){
      progress( "GOD_Channel: Skipping other sheet: $oWkS->{Name}" );
      next;
    }
    
    progress( "GOD_Channel: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = 6 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          $columns{norm($oWkS->{Cells}[$iR][$iC]->Value)} = $iC;

          # columns alternate names
          $columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Programme Title/i );
          $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/i );
          $columns{'Start'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Start/i );
          $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis/i );
        }
        next;
      }

      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );
      
      if( $date ne $currdate ){

        progress("GOD_Channel: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }
      
      

      # starttime - column ('Start')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Start'}];
      next if( ! $oWkC );
      my $starttime = create_dt( $date , $oWkC->Value ) if( $oWkC->Value );

      # title - column ('Title')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}+1];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      
      $title =~ s/-.*//g if $title;
      
      my $synopsis = $oWkS->{Cells}[$iR][$columns{'Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'Synopsis'}];

      progress("$xmltvid: $starttime - $title");

      my $ce = {
        channel_id   => $channel_id,
        start_time   => $starttime,
        title        => norm($title),
      };

      $ce->{description} = norm($synopsis) if $synopsis;

	 # print Dumper($ce);

      $dsh->AddProgramme( $ce );
    }

    %columns = ();

  }

  $ds->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $day, $monthname, $year );

#print ">$dinfo<\n";

  # format '033 03 Jul 2008'
  if( $dinfo =~ /^\d+\s+\d+\s+\S+\s+\d+$/ ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^\d+\s+(\d+)\s+(\S+)\s+(\d+)$/ );

  # format '05-sep-08'
  } elsif( $dinfo =~ /^\d+-(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)-\d+$/i ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^(\d+)-(\S+)-(\d+)$/ );

  # format 'Fri 30 Apr 2010'
  } elsif( $dinfo =~ /^\S+\s*\d+\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*\d+$/i ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^\S+\s*(\d+)\s*(\S+)\s*(\d+)$/ );
  }

  else {
    return undef;
  }

#print "DAY: $day\n";
#print "MON: $monthname\n";
#print "YEA: $year\n";

  return undef if( ! $year);

  $year+= 2000 if $year< 100;

  my $mon = MonthNumber( $monthname, "en" );

#print "DAY: $day\n";
#print "MON: $mon\n";

  my $dt = DateTime->new( year   => $year,
                          month  => $mon,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          );

  $dt->set_time_zone( "UTC" );

  return $dt->ymd();
}

sub create_dt
{
  my( $date, $time ) = @_;

  my( $hour, $min ) = ( $time =~ /(\d+).(\d{2})/ );

  return sprintf( "%02d:%02d:00", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
