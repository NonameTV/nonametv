package NonameTV::Importer::KupiTV;

use strict;
use warnings;

=pod

Importer for data from KupiTV (www.kupitv.hr) channel. 

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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
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

  progress( "KupiTV: $chd->{xmltvid}: Processing XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "KupiTV: $file: Failed to parse xls" );
    return;
  }

  if( not $oBook->{SheetCount} ){
    error( "KupiTV: $file: No worksheets found in file" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} =~ /AM(\s+|\/)PM/ ){
      progress("KupiTV: $chd->{xmltvid}: Skipping worksheet named '$oWkS->{Name}'");
      next;
    }

    progress("KupiTV: $chd->{xmltvid}: Processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
#print "CNM: >" . $oWkS->{Cells}[$iR][$iC]->Value . "<\n";
#print "COL: >$columns{$oWkS->{Cells}[$iR][$iC]->Value}<\n";

            # other possible names of the columns
            $columns{'DATE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^DATUM$/ );
            $columns{'STARTTIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^POČETAK$/ );
            $columns{'ENDTIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^KRAJ$/ );
            $columns{'TITLE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^NAZIV EMISIJE$/ );
            $columns{'LIVE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^UŽIVO\/REPRIZA$/ );
            $columns{'COMPANY'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^PODUZEĆE$/ );

            next;
          }
        }
      }
$columns{'DATE'} = 0;
$columns{'STARTTIME'} = 1;
$columns{'ENDTIME'} = 2;
$columns{'TITLE'} = 3;
$columns{'COMPANY'} = 4;
$columns{'LIVE'} = 5;

#print "CD: $columns{'DATUM'}\n";
#print "CT: $columns{'STARTTIME'}\n";

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DATUM'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
#print "$date\n";
      next if( ! $date );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batch_id , $chd->{id} );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("KupiTV: $chd->{xmltvid}: Date is: $date");
      }
      
      # start time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'STARTTIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );

      my $time = ParseTime( $oWkC->Value );
      if( not defined( $time ) ) {
        error( "Invalid start-time '$date' '" . $oWkC->Value . "'. Skipping." );
        next;
      }

      # end time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'ENDTIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $endtime = $oWkC->Value;

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TITLE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      # Company
      my $company;
      if( $columns{'COMPANY'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'COMPANY'}];
        $company = $oWkC->Value if ( $oWkC and $oWkC->Value );
      }

      # Live
      my $live;
      if( $columns{'LIVE'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'LIVE'}];
        $live = $oWkC->Value if ( $oWkC and $oWkC->Value );
      }

      progress( "KupiTV: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      $ce->{subtitle} = $live if $live;
      $ce->{subtitle} .= ": " . $company if $company;

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
  } elsif( $text =~ /^\d+\.\d+\.\d+\.$/ ){ # format '18.12.2009.'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)\.$/ );
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
    $hour = $dt->hour;
    $min = $dt->min;
  } elsif( $text =~ /^\d{2}:\d{2}:\d{2}:\d{2}$/ ){
    ( $hour, $min ) = ( $text =~ /^(\d{2}):(\d{2}):\d{2}:\d{2}$/ );
  } else {
    return undef;
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;
