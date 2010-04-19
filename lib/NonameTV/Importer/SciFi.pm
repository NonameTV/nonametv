package NonameTV::Importer::SciFi;

use strict;
use warnings;

=pod

Importer for data from SciFi (www.kupitv.hr) channel. 

Features:

=cut

use POSIX qw/strftime/;
use DateTime;
use Spreadsheet::ParseExcel;
use DateTime::Format::Excel;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Zagreb" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "SciFi: $chd->{xmltvid}: Processing XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "SciFi: $file: Failed to parse xls" );
    return;
  }

  if( not $oBook->{SheetCount} ){
    error( "SciFi: $file: No worksheets found in file" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} =~ /AM(\s+|\/)PM/ ){
      progress("SciFi: $chd->{xmltvid}: Skipping worksheet named '$oWkS->{Name}'");
      next;
    }

    progress("SciFi: $chd->{xmltvid}: Processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

            # other possible names of the columns
            #$columns{'DATE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^DATUM$/ );

            next;
          }
        }
      }

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'date'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batch_id , $chd->{id} );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("SciFi: $chd->{xmltvid}: Date is: $date");
      }
      
      # start time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'start_time'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );

      my $time = ParseTime( $oWkC->Value );
      if( not defined( $time ) ) {
        error( "Invalid start-time '$date' '" . $oWkC->Value . "'. Skipping." );
        next;
      }

      # duration
      $oWkC = $oWkS->{Cells}[$iR][$columns{'duration'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $duration = $oWkC->Value;

      # channel name
      $oWkC = $oWkS->{Cells}[$iR][$columns{'channel_name'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $channelname = $oWkC->Value;

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'original_title'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      # summary
      $oWkC = $oWkS->{Cells}[$iR][$columns{'summary'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $summary = $oWkC->Value;

      progress( "SciFi: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      $ce->{subtitle} = $duration . " minutes" if $duration;
      $ce->{description} .= ": " . $summary if $summary;

      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next sheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my( $text ) = @_;

#print "DATE >$text<\n";

  my( $day, $month, $year );

  if( $text =~ /^\d{5}$/ ){
    my $dt = DateTime::Format::Excel->parse_datetime( $text );
    $year = $dt->year;
    $month = $dt->month;
    $day = $dt->day;
  } elsif( $text =~ /^\d+\.\d+\.\d+$/ ){ # format '18.12.2009'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)$/ );
  } else {
    return undef;
  }

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime
{
  my( $text ) = @_;

#print "TIME >$text<\n";

  my( $hour, $min, $sec );

  if( $text =~ /^\d+$/ ){ # Excel time
    my $dt = DateTime::Format::Excel->parse_datetime( $text );
    $hour = $dt->year;
    $min = $dt->month;
  } elsif( $text =~ /^\d{2}:\d{2}$/ ){
    ( $hour, $min ) = ( $text =~ /^(\d{2}):(\d{2})$/ );
  } else {
    return undef;
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;
