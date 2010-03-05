package NonameTV::Importer::Trace;

use strict;
use warnings;

=pod

Import data from xls files delivered via e-mail.

Channel: www.trace.tv

=cut

use utf8;

use DateTime;
use Encode qw/encode decode/;
use Spreadsheet::ParseExcel;
use DateTime::Format::Excel;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
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

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

#return if( $file !~ /AUGUST/ );

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $channel_xmltvid );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "Trace XLS: $channel_xmltvid: Processing XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "Trace XLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    if( $oWkS->{Name} !~ /^GMT \+1$/ ){
      progress("Trace XLS: $channel_xmltvid: skipping worksheet named '$oWkS->{Name}'");
      next;
    }

    progress("Trace XLS: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){

        # the column names are stored in the 5th row
        # so read them and store their column positions
        # for further findvalue() calls
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
          }
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}

        # the number of columns must be 8 or more
        if( keys( %columns ) < 8 ){
          undef %columns;
        }

        next;
      }
      
      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programmeDate DD/MM/YY'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
	  $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Trace XLS: $channel_xmltvid: Date is: $date");
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Programme Start Time'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programmeName'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      # Duration
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programme Duration'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $duration = $oWkC->Value;

      # Synopsis
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programme Synopsis Txt'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $synopsis = $oWkC->Value;

      # Rating
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programme Rating'}];
      next if( ! $oWkC );
      my $rating = $oWkC->Value;

      # Language
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programme Language'}];
      next if( ! $oWkC );
      my $language = $oWkC->Value;

      progress( "Trace XLS: $channel_xmltvid: $time - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $time,
      };

      $ce->{description} = $synopsis if $synopsis;

      $dsh->AddProgramme( $ce );

    } # next row

    undef %columns;

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my( $text ) = @_;

  return undef if not $text;
#print ">$text<\n";

  my( $day, $month, $year );

  # Format 'DD/MM/YY'
  if( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ ){
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  # Format 'MM-DD-YY'
  } elsif( $text =~ /^(\d+)-(\d+)-(\d+)$/ ){
    ( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  # Format '40179' - Excel date format
  } elsif( $text =~ /^\d{5}$/ ){
    my $dt = DateTime::Format::Excel->parse_datetime( $text );
    $year = $dt->year;
    $month = $dt->month;
    $day = $dt->day;
  }

  $year += 2000 if $year < 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime
{
  my( $text ) = @_;

  return undef if not $text;
#print ">$text<\n";

  my( $hour, $min, $sec );

  # Format '21:00'
  if( $text =~ /^\d+:\d+$/ ){
    ( $hour, $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  } elsif( $text =~ /^0\.\d+$/){ # format '0.377962962962964'
    my $daysecs = int( 86400 * $text );
    $hour = int( $daysecs / 3600 );
    $min =  int( ( $daysecs - ( $hour * 3600 ) ) / 60 );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

sub UpdateFiles {
  my( $self ) = @_;

#return;

  # get current month name
  my $year = DateTime->today->strftime( '%g' );

  # the url to fetch data from
  # is in the format http://tracemovies.com/communication/EPG/INTERNATIONAL/TRACE_INTL_EPG_APR09.xls
  # UrlRoot = http://tracemovies.com/communication/EPG/INTERNATIONAL/
  # GrabberInfo = <empty>

  foreach my $data ( @{$self->ListChannels()} ) {

    my $xmltvid = $data->{xmltvid};

    my $today = DateTime->today;

    # do it for MaxMonths in advance
    for(my $month=0; $month <= $self->{MaxMonths} ; $month++) {

      my $dt = $today->clone->add( months => $month );

      my ( $filename, $url );

      # format: 'TRACE_INTL_EPG_APR09.xls'
      $filename = "TRACE_INTL_EPG_" . uc( $dt->strftime( '%b' ) ) . uc( $dt->strftime( '%g' ) ) . ".xls";
      $url = $self->{UrlRoot} . "/" . $filename;
      progress("Trace: $xmltvid: Fetching xls file from $url");
#      url_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );

      # format: 'TRACE_INTL_EPG_APR_09.xls'
#      $filename = "TRACE_INTL_EPG_" . uc( $dt->strftime( '%b' ) ) . "_" . uc( $dt->strftime( '%g' ) ) . ".xls";
#      $url = $self->{UrlRoot} . "/" . $filename;
#      progress("Trace: $xmltvid: Fetching xls file from $url");
#      url_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );

      # format: 'TRACE_INTL_EPG_APRIL09.xls'
#      $filename = "TRACE_INTL_EPG_" . uc( $dt->strftime( '%B' ) ) . uc( $dt->strftime( '%g' ) ) . ".xls";
#      $url = $self->{UrlRoot} . "/" . $filename;
#      progress("Trace: $xmltvid: Fetching xls file from $url");
#      url_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );

      # format: 'TRACE_INTL_EPG_APRIL_09.xls'
#      $filename = "TRACE_INTL_EPG_" . uc( $dt->strftime( '%B' ) ) . "_" . uc( $dt->strftime( '%g' ) ) . ".xls";
#      $url = $self->{UrlRoot} . "/" . $filename;
#      progress("Trace: $xmltvid: Fetching xls file from $url");
#      url_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );

    }
  }
}

sub url_get {
  my( $url, $file ) = @_;
#print "URL: $url\n";
#print "FILE: $file\n";

  qx[curl -S -s -z "$file" -o "$file" "$url"];
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
