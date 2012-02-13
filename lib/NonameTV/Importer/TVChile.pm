package NonameTV::Importer::TVChile;

use strict;
use warnings;

=pod

Import data from XLS files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);

use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/normUtf8 AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;
  
  $self->{datastore}->{augment} = 1;

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

  # Only process .xls or .xlsx files.
  return if( $file !~ /\.xls$/i );
  progress( "TVChile: $xmltvid: Processing $file" );

	my %columns = ();
  my $date;
  my $currdate = "x";
  my $coldate = 0;
  my $coltime = 1;
  my $coltitle = 2;
  my $coldesc = 4;
  my $colgenre = 3;

	my $oBook;
	$oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );


  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    #if( $oWkS->{Name} !~ /1/ ){
    #  progress( "OUTTV: Skipping other sheet: $oWkS->{Name}" );
    #  next;
    #}

    progress( "TVChile: Processing worksheet: $oWkS->{Name}" );

		my $foundcolumns = 0;
    # browse through rows
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      my $oWkC;

      # date
      $oWkC = $oWkS->{Cells}[$iR][$coldate];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      # time
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;

      # title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      # desc
      $oWkC = $oWkS->{Cells}[$iR][$coldesc];
      next if( ! $oWkC );
      my $desc = $oWkC->Value if( $oWkC->Value );
      my $start = create_dt($date." ".$time);
      
      if($time =~ /PROGRAMACI/) {
      	next;
      }

			if( $date ne $currdate ){

        progress("TVChile: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $start->ymd("-");
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $start->ymd("-") , "00:00" );
        $currdate = $start->ymd("-");
      }

      my $ce = {
        channel_id => $channel_id,
        start_time => $start->hms(":"),
        title => normUtf8($title),
        description => normUtf8($desc),
      };


			# Genre
			$oWkC = $oWkS->{Cells}[$iR][$colgenre];
			if( $oWkC and $oWkC->Value ne "" ) {
      	my $genre = $oWkC->Value;
				my($program_type, $category ) = $ds->LookupCat( 'TVChile', $genre );
				AddCategory( $ce, $program_type, $category );
			}
      
			progress("TVChile: $start - $title");
      $dsh->AddProgramme( $ce );
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $month, $day, $year );
#      progress("Mdatum $dinfo");
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22' 
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{2}.\d{2}.\d{4}$/ ){ # format '11/18/2011'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}\/\d{1,2}\/\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

sub create_dt
{
  my( $str ) = shift;
  my( $year, $month, $day, $hour, $minute );

  if( $str =~ /^\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}$/ ){
  	( $year, $month, $day, $hour, $minute ) = 
      ($str =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+)$/ );
  } elsif( $str =~ /^\d{4}-\d{2}-\d{2}  \d{1,2}:\d{2}$/ ){
  	( $year, $month, $day, $hour, $minute ) = 
      ($str =~ /(\d+)-(\d+)-(\d+)  (\d+):(\d+)$/ );
  } elsif( $str =~ /^\d{4}-\d{2}-\d{2} \d{1,2}:\d{2} $/ ){
  	( $year, $month, $day, $hour, $minute ) = 
      ($str =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+) $/ );
  }else {
  	return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'America/Santiago',
                          );
  # somehow it fails, (one hour off)
  $dt->add( hours => 1 );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
