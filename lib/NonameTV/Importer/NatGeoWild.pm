package NonameTV::Importer::NatGeoWild;

use strict;
use warnings;

=pod

Import data for Nat. Geo. Wild.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
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

  if( $file =~ /\.xls$/i ){
    $self->ImportFlatXLS( $file, $chd );
  } else {
    error( "NatGeoWild: Unknown file format: $file" );
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

  progress( "NatGeoWild FlatXLS: $chd->{xmltvid}: Processing flat XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

    my($iR, $oWkS, $oWkC);
	
	  my( $time, $episode );
  my( $program_title , $program_description );
    my @ces;
  
  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
	# Not using this yet.
	#if( $oWkS->{Name} =~ /Amend/ ){
    #  progress( "NatGeoWild: $chd->{xmltvid}: Skipping amendment: $oWkS->{Name}" );
    #  next;
    #}
  
    progress("--------- SHEET: $oWkS->{Name}");

    # start from row 2
    # the first row looks like one cell saying like "EPG DECEMBER 2007  (Yamal - HotBird)"
    # the 2nd row contains column names Date, Time (local), Progran, Description
    #for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

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

        progress("NatGeoWild: Date is: $date");
      }
	  
	  	#if($iR == 28) { next; }
	  
	# time (column 1)
	 #  print "hejhejhej";
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );
	  
	  #use Data::Dumper; print Dumper($oWkS->{Cells}[28]);

	  
	  my $title;
	  my $test;
	  my $season;
	  my $episode;
	  
	  # print "hejhej";
      # program_title (column 4)
      $oWkC = $oWkS->{Cells}[$iR][4];

      # Here's where the magic happends.
	  # Love goes out to DrForr.
		if (defined $oWkC)
		{
			$test = $oWkC->Value;
		}
		else
		{
			my $oWkl = $oWkS->{Cells}[$iR][8];
			next if( ! $oWkl );
			$test = $oWkl->Value if $oWkl->Value;
		}
	  
	  $title = norm($test) if $test ne "";
	  # If no series title, get it from episode name.
	  
	  
	  $oWkC = $oWkS->{Cells}[$iR][12];
      my $desc = $oWkC->Value;
	  # print "hej";
	  #print ">$program_title<\n";

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
  if( $text =~ /^(\d+)\/(\d+)\/(\d+)$/i ){
    ( $month, $day, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d{2})$/i );

  # format '2011-05-16'
  } elsif( $text =~ /^\d{4}-\d{2}-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})-(\d{2})-(\d{2})$/i );
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
