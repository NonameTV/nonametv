package NonameTV::Importer::ProTV;

use strict;
use warnings;

=pod
Importer for Pro TV Romania

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use Spreadsheet::Read;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/norm MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  $self->{datastorehelper} = $dsh;

  #$self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "ProTV: Unknown file format: $file" );
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
  my $oBook;

  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    # date - column 0 ('Date')
      $date = ParseDate( $oWkS->{Name} );
      next if( ! $date );

	  # Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			# save last day if we have it in memory
		#	FlushDayData( $channel_xmltvid, $dsh , @ces );
			$dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("ProTV: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    #progress( "BBCWW: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

	my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # time
      my $oWkC = $oWkS->{Cells}[$iR][2];
      next if( ! $oWkC );

      my $time;
      if($oWkC->Value =~ /^(\d\d\:\d\d)/) {
        $time = $1;
      } else {
        next;
      }

      $oWkC = $oWkS->{Cells}[$iR][4];
      next if( ! $oWkC );
      my $romaniantitle = $oWkC->Value if( $oWkC->Value );

      $oWkC = $oWkS->{Cells}[$iR][7];
      next if( ! $oWkC );
      my $engtitle = $oWkC->Value if( $oWkC->Value );

      $romaniantitle =~ s/\((.*?)\)//g;
      $engtitle =~ s/\((.*?)\)//g;

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $romaniantitle ),
        start_time => $time,
        original_title => norm($engtitle),
      };

      $oWkC = $oWkS->{Cells}[$iR][8];
      if($oWkC and $oWkC->Value and $oWkC->Value eq "live") {
        $ce->{live} = "1";
      } else {
        $ce->{live} = "0";
      }


      progress("ProTV: $chd->{xmltvid}: $time - " .norm($romaniantitle));

      $dsh->AddProgramme( $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+,\d+,\d+/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+),(\d+),(\d\d\d\d)/ );
  }

  return if not defined $year;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;
