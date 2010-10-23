package NonameTV::Importer::NatGeoMusic;

use strict;
use warnings;

=pod

Importer for data for NatGeo Music music channel. 
One file per month downloaded from Mediavision site.
The downloaded file is in xls format.

Features:

=cut

use POSIX qw/strftime/;
use DateTime;
use Spreadsheet::ParseExcel;
use URI::Escape;

use NonameTV qw/MyGet norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

# File types
use constant {
  FT_UNKNOWN     => 0,  # unknown
  FT_FLATXLS     => 1,  # flat xls file
  FT_GRIDXLS     => 2,  # xls file with grid
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $ff = CheckFileFormat( $file );
  if( $ff eq FT_GRIDXLS ){
    $self->ImportGRIDXLS( $file, $chd );
  } elsif( $ff eq FT_FLATXLS ){
    $self->ImportFLATXLS( $file, $chd );
  } else {
    progress( "NatGeoMusic: $chd->{xmltvid}: Unknown file format $file" );
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

  # Grid XLS
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
    my $oWkS = $oBook->{Worksheet}[$iSheet];
    my $oWkC = $oWkS->{Cells}[0][0];
    if( $oWkC and $oWkC->Value =~ /^TX/ ){
      return FT_GRIDXLS;
    }
  }

  # Flat XLS
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
    my $oWkS = $oBook->{Worksheet}[$iSheet];
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      my $oWkC = $oWkS->{Cells}[$iR][0];
      if( $oWkC and $oWkC->Value =~ /^www\.natgeomusic\.it/ ){
        return FT_FLATXLS;
      }
    }
  }

  return FT_UNKNOWN;
}

sub ImportGRIDXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $coltime = 0;
  my $currdate = "x";

  progress( "NatGeoMusic GRID: $chd->{xmltvid}: Processing XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "NatGeoMusic FLAT: $file: Failed to parse xls" );
    return;
  }

  if( not $oBook->{SheetCount} ){
    error( "NatGeoMusic FLAT: $file: No worksheets found in file" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress("NatGeoMusic FLAT: $chd->{xmltvid}: Processing worksheet named '$oWkS->{Name}'");

    my $date;

    # read the columns
    for(my $iC = 1 ; $iC <= 7 ; $iC++) {

      # read the rows with data
      for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        # date
        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );

        if( isDate( $oWkC->Value) ) {
          $date = ParseDate( $oWkC->Value );

          if( $date ne $currdate ){
            if( $currdate ne "x" ) {
              $dsh->EndBatch( 1 );
            }

            my $batch_id = $chd->{xmltvid} . "_" . $date;
            $dsh->StartBatch( $batch_id , $chd->{id} );
            $dsh->StartDate( $date , "06:00" );
            $currdate = $date;

            progress("NatGeoMusic GRID: $chd->{xmltvid}: Date is: $date");
          }

          next;
        }

        next if( ! $date );

        # title
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $title = $oWkC->Value;
        next if( ! $title );

        # time
        $oWkC = $oWkS->{Cells}[$iR][$coltime];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        my $time = ParseTime( $oWkC->Value );
        next if( ! $time );

        progress( "NatGeoMusic GRID: $chd->{xmltvid}: $time - $title" );

        my $ce = {
          channel_id => $chd->{id},
          title => $title,
          start_time => $time,
        };

        $dsh->AddProgramme( $ce );

      }
    }
  }

  $dsh->EndBatch( 1 );

  return;
}

sub ImportFLATXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $coldate = 0;
  my $coltime = 0;
  my $coltitle = 1;
  my $date;
  my $currdate = "x";

  progress( "NatGeoMusic FLAT: $chd->{xmltvid}: Processing XLS $file" );

#return if ( $file !~ /grille_en2/ );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "NatGeoMusic FLAT: $file: Failed to parse xls" );
    return;
  }

  if( not $oBook->{SheetCount} ){
    error( "NatGeoMusic FLAT: $file: No worksheets found in file" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    progress("NatGeoMusic FLAT: $chd->{xmltvid}: Processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$coldate];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      if( isDate( $oWkC->Value) ) {

        $date = ParseDate( $oWkC->Value );

        if( $date ne $currdate ){
          if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
          }

          my $batch_id = $chd->{xmltvid} . "_" . $date;
          $dsh->StartBatch( $batch_id , $chd->{id} );
          $dsh->StartDate( $date , "00:00" );
          $currdate = $date;

          progress("NatGeoMusic FLAT: $chd->{xmltvid}: Date is: $date");
          next;
        }
      }
      
      # Time
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;
      $time =~ s/\./:/;

      if( not defined( $time ) ) {
        error( "Invalid start-time '$date' '" . $oWkC->Value . "'. Skipping." );
        next;
      }

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      progress( "NatGeoMusic FLAT: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      $dsh->AddProgramme( $ce );

    } # next row

  } # next sheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate
{
  my( $dateinfo ) = @_;

#print ">$dateinfo<\n";

  # format: '31 October 2010'
  if( $dateinfo =~ /^\d+ \S+ \d+$/ ){
    return 1;
  }

  return 0;
}


sub ParseTime
{
  my( $text ) = @_;

#print ">$text<\n";

  my( $hour, $min ) = ( $text =~ /^(\d+):(\d+)$/ );

  $hour -= 12 if( $hour > 23 );

  return sprintf( "%02d:%02d", $hour, $min );
}

sub ParseDate
{
  my( $dateinfo ) = @_;

#print ">$dateinfo<\n";

  my( $month, $monthname, $day, $year );

  if( $dateinfo =~ /^\d+ \S+ \d+$/ ){
    ( $day, $monthname, $year ) = ( $dateinfo =~ /^(\d+) (\S+) (\d+)$/ );
  } else {
    return undef;
  }

  $month = MonthNumber( $monthname, "en" );

  $year += 2000 if( $year < 100);

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub UpdateFiles {
  my( $self ) = @_;

  # get current month name
  my $year = DateTime->today->strftime( '%g' );

  # the url to fetch data from
  # is in the format ftp://mediavision:mediavision93617@83.139.110.131/NatGeo%20Music/EPG%20NAT%20GEO%20MUSIC%20November%202010.xls
  # UrlRoot = ftp://mediavision:mediavision93617@83.139.110.131/
  # GrabberInfo = NatGeo Music

  foreach my $data ( @{$self->ListChannels()} ) {

    my $xmltvid = $data->{xmltvid};

    my $today = DateTime->today;

    # do it for MaxMonths in advance
    for(my $month=0; $month <= $self->{MaxMonths} ; $month++) {

      my $dt = $today->clone->add( months => $month );

      # grabber_info contains parts separateb by ;
      # 0 - path
      # 1 - filename prefix
      my @grabber_data = split(/;/, $data->{grabber_info} );

      # format: 'EPG%20NAT%20GEO%20MUSIC%20November%202010.xls'
      my $filename = $grabber_data[1] . " " . $dt->month_name . " " . $dt->strftime( '%Y' ) . ".xls";
      my $url = $self->{UrlRoot} . "/" . uri_escape( $grabber_data[0] . "/" . $filename );

      progress("NatGeoMusic: $xmltvid: Fetching xls file from $url");
      ftp_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );
    }
  }
}

sub ftp_get {
  my( $url, $file ) = @_;

  qx[curl -S -s -z "$file" -o "$file" "$url"];
}

1;
