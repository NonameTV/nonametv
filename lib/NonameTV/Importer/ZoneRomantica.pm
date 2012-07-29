package NonameTV::Importer::ZoneRomantica;

use strict;
use warnings;

=pod

Import data from XLS files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory/;
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
  progress( "ZoneRomantica: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "ZoneRomantica: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    # schedules are starting after that
    # valid schedule row must have date, time and title set
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}
        next;
      }

      my $oWkC;

      # date - column 'Tx Date'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Tx Date'}];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("ZoneRomantica: $xmltvid: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;
      }

      # time - column 'Billed Start'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Billed Start'}];
      next if( ! $oWkC );
      my $time = $oWkC->Value if( $oWkC->Value );

      # title - column 'Title'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      # slot - column 'Slot'
      my $slot;
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Slot'}] if $columns{'Slot'};
      if( $oWkC ){
        $slot = $oWkC->Value if( $oWkC->Value );
      }

      # episode_title - column 'Episode Title'
      my $episode_title;
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Episode Title'}] if $columns{'Episode Title'};
      if( $oWkC ){
        $episode_title = $oWkC->Value if( $oWkC->Value );
      }

      # episode_number - column 'Episode number'
      my $episode_number;
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Episode number'}] if $columns{'Episode number'};
      if( $oWkC ){
        $episode_number = $oWkC->Value if( $oWkC->Value );
      }

      progress("ZoneRomantica: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      $ce->{subtitle} = $episode_title if $episode_title;
      $ce->{subtitle} .= " ($slot)" if $slot;

      if( $episode_number > 0 )
      {
        $ce->{episode} = sprintf( ". %d .", $episode_number-1 );
      }

      $dsh->AddProgramme( $ce );
    }

    %columns = ();

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $day, $month, $year ) = ( $dinfo =~ /(\d+)\/(\d+)\/(\d+)/ );

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

sub UpdateFiles {
  my( $self ) = @_;

  # get current month name
  my $year = DateTime->today->strftime( '%g' );

  # the url to fetch data from
  # is in the format http://newsroom.zonemedia.net/Files/Schedules/RMT21009L01.xls
  # UrlRoot = http://newsroom.zonemedia.net/Files/Schedules/
  # GrabberInfo = <empty>

  foreach my $data ( @{$self->ListChannels()} ) {

    my $xmltvid = $data->{xmltvid};

    my $today = DateTime->today;

    # do it for MaxMonths in advance
    for(my $month=0; $month <= $self->{MaxMonths} ; $month++) {

      my $dt = $today->clone->add( months => $month );

      for( my $v=1; $v<=3; $v++ ){
        my $filename = sprintf( "RMT2%02d%02dL%02d.xls", $dt->month, $dt->strftime( '%y' ), $v );
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
