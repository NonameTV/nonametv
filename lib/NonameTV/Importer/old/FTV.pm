package NonameTV::Importer::FTV;

use strict;
use warnings;

=pod

Importer for data from FTV. 
One file per month downloaded from www.ftv.com site
or received via email.
The downloaded file is in xls-format.

Features:

=cut

use POSIX qw/strftime/;
use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/progress error/;
use NonameTV::DataStore::Helper;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
  if( $self->{grabber_info} ){
    progress( "FTV: grabber_info defined '" . $self->{grabber_info} . "'-> downloading" );
  }

  $self->{MinMonths} = 1 unless defined $self->{MinMonths};
  $self->{MaxMonths} = 12 unless defined $self->{MaxMonths};

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

#return if( $channel_xmltvid !~ /fmen\.tv\.gonix\.net/ );

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

  if( $file !~ /HOTBIRD/i and $file !~ /SEE/i and $file !~ /FTV-HD/i and $file !~ /F-MEN/i ){
    progress( "FTV: $channel_xmltvid: Skipping file $file" );
    return 1;
  }

  progress( "FTV: $channel_xmltvid: Processing XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "FTV: $file: Failed to parse xls" );
    return;
  }

  my $date;
  my $currdate = "x";

  # There are few Worksheets in the xls file
  # the epg data can be found in the one which name begins with 'EPG'

  # The columns in the xls file are:
  # --------------------------------
  # date, time, program, description

  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    if( $oWkS->{Name} !~ /EPG/ ){
      progress("FTV: $channel_xmltvid: Skipping worksheet $oWkS->{Name}");
      next;
    }

    progress("FTV: $channel_xmltvid: Processing worksheet named '$oWkS->{Name}'");

    # start from row 2
    # the first row looks like one cell saying like "EPG DECEMBER 2007 (Yamal - HotBird)"
    # the 2nd row contains column names Date, Time (local), Progran, Description
    #for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      my $oWkC;

      # date (column 0)
      $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("FTV: $channel_xmltvid: Date is: $date");
      }

      # time (column 1)
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );

      # title (column 2)
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if( ! $oWkC );
      my $title = $oWkC->Value;
      next if( ! $title );

      my $genre;
      if( $title =~ /Midnight Hot/i ){ $genre = "erotic"; }
      elsif( $title =~ /F Hot/i ){ $genre = "erotic"; }
      elsif( $title =~ /Lingerie/i ){ $genre = "erotic"; }
      elsif( $title =~ /F Party/i ){ $genre = "magazine"; }

      # description (column 3)
      $oWkC = $oWkS->{Cells}[$iR][3];
      next if( ! $oWkC );
      my $description = $oWkC->Value;

      progress("FTV: $channel_xmltvid: $time - $title");

      my $ce = {
        channel_id   => $channel_id,
        title        => $title,
        start_time   => $time,
      };

      $ce->{description} = $description if $description;

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( "FTV", $genre );
        AddCategory( $ce, $program_type, $category );
      }

      $dsh->AddProgramme( $ce );

    } # next row

  } # next worksheet

  $dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate
{
  my( $dateinfo ) = @_;

#print "$dateinfo\n";

  my( $month, $day, $year );

  if( $dateinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){
    ( $year, $month, $day ) = ( $dateinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dateinfo =~ /^\d+-\d+-\d+$/ ){
    ( $month, $day, $year ) = ( $dateinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  }

  $year += 2000 if( $year lt 100 );

  sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime
{
  my( $tinfo ) = @_;

  # the date information in format '14:30'
  if( $tinfo !~ /^\d+:\d+$/ ){
    return undef;
  }

  my( $hour, $min ) = ( $tinfo =~ /^(\d+):(\d+)$/ );

  sprintf( "%02d:%02d", $hour, $min );
}

sub UpdateFilessssssss
{
  my $self = @_;

  foreach my $data ( @{$self->ListChannels()} ) {

    my $xmltvid = $data->{xmltvid};

    my $today = DateTime->today;

    # do it for MaxMonths in advance
    for(my $month=0; $month <= $self->{MaxMonths} ; $month++) {

      my $dt = $today->clone->add( months => $month );

      # the url to fetch data from
      # is in the format http://www.ftv.com/bilder/d17/EPG_HotBird3-Yamal_December2007.xls
      # UrlRoot = http://www.ftv.com/bilder/
      # GrabberInfo = EPG_HotBird3-Yamal_
      my $filename = "Mezzo_Schedule_" . $dt->month_name . "_" . $dt->strftime( '%g' ) . ".xls";

      my $url = $self->{UrlRoot} . "/" . $filename;
      progress("FTV: Fetching xls file from $url");

      ftp_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );
      my( $content, $code ) = MyGet( $url );
      open (FILE,">$filename");
      print FILE $content;
      close (FILE);
    }
  }
}

#  my( $year, $week ) = ($batch_id =~ /_(\d+)-(\d+)/);

  # the url to fetch data from
  # is in the format http://www.ftv.com/bilder/d17/EPG_HotBird3-Yamal_December2007.xls
  # UrlRoot = http://www.ftv.com/bilder/d17/
  # GrabberInfo = EPG_HotBird3-Yamal_

#  my $nowmonth = DateTime->today->month_name();
#  my $nowyear = DateTime->today->year();

  #my $url = $self->{UrlRoot} . "/" . $data->{grabber_info} .  $nowmonth . "_" . $nowyear .  ".xls";
  #my $url = $self->{UrlRoot} . "/d18/" . "Grid_EPG_April_2008_HotBird-Yamal.xls";
  #my $url = $self->{UrlRoot} . "/d18/" . "Grid-EPGMay_2008Hotbird-Yamal.xls";
  #my $url = $self->{UrlRoot} . "/d19/Grid-_EPG_June_2008_Hotbird-Yamal.xls";
  #my $url = $self->{UrlRoot} . "/d20/GRID-EPG_July_2008_HotBird-Yamal1.xls";
  #my $url = $self->{UrlRoot} . "/d20/GRID-EPG-AUGUST2008HotBird-Yamal.xls";
  #my $url = $self->{UrlRoot} . "/d21/Grid_EPG_September_2008_HotBird-ABS1-UK.xls";
  #my $url = $self->{UrlRoot} . "/d21/Grid_EPG_October_2008_HotBird.xls";
  #my $url = $self->{UrlRoot} . "/d22/November_2008_HotBird3t.xls";


  #progress("Fetching xls file from $url");


  #############################################
  # temporary only !!!
  # todo: avoid using temp file
  #############################################
#  my $filename = "/tmp/ftv.xls";
#  open (FILE,">$filename");
#  print FILE $content;
#  close (FILE);

#  return( $content, $code );
#}

1;
