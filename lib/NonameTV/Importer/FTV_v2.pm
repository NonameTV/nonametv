package NonameTV::Importer::FTV_v2;

use strict;
use warnings;

=pod

Import data for FTV.
Version 2 - Web - Working.

Notes:
FTV changes the names for the EPG files, like every month.
So, this is the best way to do it.
Download the epg files (EXCEL!) to the channel's "files (where all the files is)"
and the channel automaticly puts it in the database.

Until FTV does this good, you will have to get the files every month, manually.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

#use Data::Dumper;

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

  if( $file =~ /\.xls|.xlsx$/i ){
    $self->ImportFlatXLS( $file, $chd );
  } else {
    error( "FTV: Unknown file format: $file" );
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

  progress( "FTV FlatXLS: $chd->{xmltvid}: Processing flat XLS $file" );
  
  my $oBook;
  
  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }   #  staro, za .xls

  my($iR, $oWkS, $oWkC);
	
  my( $time, $episode );
  my( $program_title , $program_description );
  my @ces;
  
  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
	# Not using this yet.
	my $oWkS = $oBook->{Worksheet}[$iSheet];
	if( $oWkS->{Name} !~ /EPG/ ){
      progress( "FTV: $chd->{xmltvid}: Skipping (Not epg): $oWkS->{Name}" );
      next;
    }
  
    progress( "FTV: Processing worksheet: $oWkS->{Name}" );

    # start from row 2
    # the first row looks like one cell saying like "EPG DECEMBER 2007  (Yamal - HotBird)"
    # the 2nd row contains column names Date, Time (local), Progran, Description
    #for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    my $i = 0;
    for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      $i++;

      # date (column 1)
      $oWkC = $oWkS->{Cells}[$iR][0];
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

        progress("FTV: Date is: $date");
      }
	  
	  	#if($iR == 28) { next; }
	  
	# time (column 1)
	 #  print "hejhejhej";
      $oWkC = $oWkS->{Cells}[$iR][1];
      
      next if( ! $oWkC );
      #my $time = ParseTime( $oWkC->Value );
      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );

	  #Convert Excel Time -> localtime
      $time = ExcelFmt('hh:mm', $time);
      next if( ! $time );
	  
	  #use Data::Dumper; print Dumper($oWkS->{Cells}[28]);

	  
	  my $title;
	  my $test;
	  
	  # print "hejhej";
      # program_title (column 3)
      $oWkC = $oWkS->{Cells}[$iR][2];

      # Here's where the magic happends.
	  # Love goes out to DrForr.
	  $test = $oWkC->Value;
	  
	  $title = norm($test) if $test ne "";
	  # If no series title, get it from episode name.
	  
	  # description
	  $oWkC = $oWkS->{Cells}[$iR][3];
	  my $desc = $oWkC->Value;
	  
      if( $time and $title ){
	  
	  # empty last day array
      undef @ces;
	  
        progress("$time $title");

        my $ce = {
          channel_id   => $chd->{id},
		  title		   => norm($title),
          start_time   => $time,
          description  => norm($desc),
        };

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
  if( $text =~ /^\d{2}\/\d{2}\/\d{4}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2})\/(\d{2})\/(\d{4})$/i );

  # format '2011-05-16'
  } elsif( $text =~ /^\d{4}-\d{2}-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})-(\d{2})-(\d{2})$/i );
    
  # format '03-11-2012'
  } elsif( $text =~ /^\d{1,2}-\d{1,2}-\d{4}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d{4})$/i );
  # format '03/11/2012'
  } elsif( $text =~ /^\d{1,2}-\d{1,2}-\d{2}$/i ){
     ( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d{2})$/i );
     # format '12-31-13'
  } elsif( $text =~ /^(\d+)\/(\d+)\/(\d+)$/i ){
    ( $month, $day, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d{2})$/i );
  }

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

  my( $hour , $min, $secs );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  } elsif( $text =~ /^\d+:\d+:\d+$/ ){
    ( $hour , $min, $secs ) = ( $text =~ /^(\d+):(\d+):(\d+)$/ );
  } elsif( $text =~ /^\d+:\d+/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
