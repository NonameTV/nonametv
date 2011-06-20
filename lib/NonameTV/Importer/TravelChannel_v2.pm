package NonameTV::Importer::TravelChannel_v2;

use strict;
use warnings;

=pod

Import data for TravelChannel.
Version 2 - Mail - Working.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
#use Data::Dumper;

use NonameTV qw/MyGet norm AddCategory MonthNumber/;
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

  $self->{MinMonths} = 1 unless defined $self->{MinMonths};
  $self->{MaxMonths} = 2 unless defined $self->{MaxMonths};
	  
  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
  
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
    error( "TC: Unknown file format: $file" );
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

  progress( "TC FlatXLS: $chd->{xmltvid}: Processing flat XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

    my($iR, $oWkS, $oWkC);
	
	  my( $time, $episode );
  my( $program_title , $program_description );
    my @ces;
  
  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
  
    progress("--------- SHEET: $oWkS->{Name}");

    # start from row 2
    # the first row looks like one cell saying like "EPG DECEMBER 2007  (Yamal - HotBird)"
    # the 2nd row contains column names Date, Time (local), Progran, Description
    #for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # date (column 1)
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
		$date = ParseDate( $oWkC->Value );
		#$date = $oWkC->Value;
      next if( ! $date );

	  unless( $date ) {
		progress("SKIPPING :D");
	  next;
	  }
	  
	  if($date ne $currdate ) {
        if( $currdate ne "x" ) {
			# save last day if we have it in memory
		#	FlushDayData( $channel_xmltvid, $dsh , @ces );
			$dsh->EndBatch( 1 );
        }



        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("TC: Date is: $date");
      }
	  
	  	#if($iR == 28) { next; }
	  
	# time (column 1)
	 #  print "hejhejhej";
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if( ! $oWkC );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );
	  
	  #use Data::Dumper; print Dumper($oWkS->{Cells}[28]);

	  
	  my $title;
	  my $test;
	  my $season;
	  my $episode;
	  #my $epg;
	  
	  # print "hejhej";
      # program_title (column 3)
      $oWkC = $oWkS->{Cells}[$iR][3];

      # Here's where the magic happends.
	  # Love goes out to DrForr.
	  $title = $oWkC->Value;
	  

	  # EPG is actually listing.
          $oWkC = $oWkS->{Cells}[$iR][8];
          my $epg = $oWkC->Value;
	  
	  $oWkC = $oWkS->{Cells}[$iR][6];
      my $subtitle = $oWkC->Value;
	  
	  $oWkC = $oWkS->{Cells}[$iR][4];
      my $sea = $oWkC->Value;
	  
	  $oWkC = $oWkS->{Cells}[$iR][5];
      my $epi = $oWkC->Value;
	  
	  # Episode info in xmltv-format
      if( ($epi > 0) and ($sea > 0) )
      {
        $episode = sprintf( "%d . %d .", $sea-1, $epi-1 );
      }
      elsif( $epi > 0 )
      {
        $episode = sprintf( ". %d .", $epi-1 );
      }

      if( $time and $title ){
	  
	  # empty last day array
      undef @ces;
	  
        progress("$time $title");

        my $ce = {
          channel_id   => $chd->{id},
		  title		   => norm($title),
          start_time   => $time,
		  subtitle     => norm($subtitle),
          episode      => $episode,
	description	=> $epg,
        };

		## Episodes and so on ( Doesn't seem to work, fix this later. )

		## END
		
        $dsh->AddProgramme( $ce );
		
		push( @ces , $ce );
      }

    } # next row
	
  } # next worksheet

  $dsh->EndBatch( 1 );
  
  return;
}

sub ParseDate {
  my ( $text ) = @_;

#print ">$text<\n";

  my( $year, $day, $month );

  # format '2011-04-13'
#  if( $text =~ /^(\d+)\/(\d+)\/(\d+)$/i ){
#    ( $month, $day, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d{2})$/i );

  # format '2011-05-16'
#  } elsif( $text =~ /^\d{4}-\d{2}-\d{2}$/i ){
#    ( $year, $month, $day ) = ( $text =~ /^(\d{4})-(\d{2})-(\d{2})$/i );
#  }

  #if( $text =~ /^(\d+)-(\w)-(\d+)$/ ){
  #  ( $day, $month, $year ) = ( $text =~ /^(\d+)-(\w)-(\d+)$/ );
  #}
    if( $text =~ /^(\d+)-Jan-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Jan-(\d+)$/ );
    $month = "01";
  } elsif( $text =~ /^(\d+)-Feb-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Feb-(\d+)$/ );
    $month = "02";
  } elsif( $text =~ /^(\d+)-Mar-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Mar-(\d+)$/ );
    $month = "03";
  } elsif( $text =~ /^(\d+)-Apr-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Apr-(\d+)$/ );
    $month = "04";
  } elsif( $text =~ /^(\d+)-May-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-May-(\d+)$/ );
    $month = "05";
  } elsif( $text =~ /^(\d+)-Jun-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Jun-(\d+)$/ );
    $month = "06";
  } elsif( $text =~ /^(\d+)-Jul-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Jul-(\d+)$/ );
    $month = "07";
  } elsif( $text =~ /^(\d+)-Aug-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Aug-(\d+)$/ );
    $month = "08";
  } else {
    return undef;
  }
  
  my %mon2num = qw(
	jan 1  feb 2  mar 3  apr 4  maj 5  jun 6
	jul 7  aug 8  sep 9  okt 10 nov 11 dec 12
  );
  
  #print ">$month<";
  
  #$month = $mon2num{ lc substr($month, 0, 3) };

  $year += 2000 if $year < 100;

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    time_zone => "Europe/Stockholm"
      );

  $dt->set_time_zone( "UTC" );


	return $dt->ymd("-");
#return $year."-".$month."-".$day;
}

sub ParseTime {
  my( $text ) = @_;

#print "ParseTime: >$text<\n";

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
