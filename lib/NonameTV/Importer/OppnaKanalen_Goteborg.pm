package NonameTV::Importer::OppnaKanalen_Goteborg;

use strict;
use warnings;

=pod

Import data from Y&S

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use Spreadsheet::ParseExcel::Utility qw(ExcelFmt ExcelLocaltime LocaltimeExcel);

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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xls$/i ){
    $self->ImportFlatXLS( $file, $chd );
  } else {
    error( "OKGoteborg: Unknown file format: $file" );
  }

  return;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "OKGoteborg: $chd->{xmltvid}: Processing $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

    my($iR, $oWkS, $oWkC);
	
	  my( $time, $episode );
  my( $program_title , $program_description );
    my @ces;


  $dsh->StartBatch( $file , $chd->{id} );
  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # date (column 1)
      $oWkC = $oWkS->{Cells}[$iR][0];
      if($oWkC->Value ne "") {
        $date = ParseDate( $oWkC->Value );
        #print Dumper($date, $oWkC->Value);

      }
	  	if($date ne $currdate ) {
    		if( $currdate ne "x" ) {
					$dsh->EndBatch( 1 );
    		}

        my $batchid = $chd->{xmltvid} . "_" . $date;

        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("OKGoteborg: Date is: $date");
      }

      $oWkC = $oWkS->{Cells}[$iR][4];
      my $title =  norm( $oWkC->Value );

      $oWkC = $oWkS->{Cells}[$iR][1];
      #next if( ! $oWkC );
      my $time = ParseTime( $oWkC->Value );
      #next if( ! $time );

      $oWkC = $oWkS->{Cells}[$iR][2];
      my $endtime = $oWkC->Value;

      if( $time and $title ){

        progress("$time - $title");

        my $ce = {
          channel_id   => $chd->{id},
          title        => $title,
          start_time   => $date." ".$time,
        };
		
		#$ce->{end_time} = ParseTime($endtime) if $endtime ne "";
        $ds->AddProgramme( $ce );
      } else {
        print Dumper($time);
        print Dumper($title);
      }

    } # next row
	
  } # next worksheet

  $dsh->EndBatch( 1 );
  
  return;
}


sub ParseDate {
  my ( $text ) = @_;

  my( $year, $day, $month );

  # format '2011-04-13'
  if( $text =~ /^\d{4}\-\d{2}\-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\-(\d{2})\-(\d{2})$/i );

  # format '201'
  } elsif( $text =~ /^\d{4}\/\d{2}\/\d{2}$/i ){
    ( $year, $month, $day  ) = ( $text =~ /^(\d{4})\/(\d{2})\/(\d{2})$/i );
  } else {
    print(">$text<");
    $text = ExcelFmt('yyyy-mm-dd', $text );
    return $text;
  }
  
  #my $dt2 = DateTime->now;
  #$year   = $dt2->year;

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day
  );

  return $dt->ymd("-");
}

sub ParseTime {
  my( $text ) = @_;

	if($text ne "") {
  	my( $hour , $min );

  	if( $text =~ /^\d+:\d+$/ ){
  	  ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  	} else {
  	    print("$text");
        return ExcelFmt('hh:mm', $text);
  	}

  	return sprintf( "%02d:%02d", $hour, $min );
  } else {
  	return 0;
  }
}

1;
