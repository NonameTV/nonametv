package NonameTV::Importer::MusicBoxIT;

use strict;
use warnings;

=pod

Import data from MusicBox.IT (GIGLIO GROUP - http://www.giglio.org/)
Channels: Y&S (They bought them in Sep 2011).

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

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
    error( "YaS: Unknown file format: $file" );
  }

  return;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "YaS: $chd->{xmltvid}: Processing $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

    my($iR, $oWkS, $oWkC);
	
	  my( $time, $episode );
  my( $program_title , $program_description );
    my @ces;
  
  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

		$oWkC = $oWkS->{Cells}[$iR][0]->Value;

		if( isDate( $oWkC ) ) { # the line with the date in format '01/10/2011'

      $date = ParseDate( $oWkC );

      if( $date ) {

        progress("MusicBoxIT: $xmltvid: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
          	# save last day if we have it in memory
  					FlushDayData( $xmltvid, $dsh , @ces );
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
        }
      }

      # empty last day array
      undef @ces;

    } elsif( isTime( $oWkC ) ) {
    	my $time = ParseTime( $oWkC );
			my $title = norm($oWkS->{Cells}[$iR][1]->Value);
			my $subtitle = norm($oWkS->{Cells}[$iR][15]->Value);
			if((defined $subtitle) and ($subtitle ne "")) {
				if( $subtitle =~ /Ep.\s*\d+$/i ) {
  					my ( $epi ) = ( $subtitle =~ /Ep.\s*(\d+)$/ );
  					$episode = sprintf( " . %d . ", $epi-1 ) if defined $epi;
  					# Remove it from title
  					$subtitle =~ s/Ep.\s*(\d+)$//; 
  					
  					# norm it
  					$subtitle = norm($subtitle);
  					
  					# Remove ending dot
  					$subtitle =~ s/.$//; 
  			}
			}
			
			#my $genre = norm($oWkS->{Cells}[$iR][6]); # Not used as of yet
			my $desc = norm($oWkS->{Cells}[$iR][16]->Value);
			
			my $ce = {
          channel_id   => $chd->{id},
          title        => $title,
          start_time   => $time,
          description  => $desc,
        };
		
			$ce->{subtitle} = $subtitle if $subtitle;
			$ce->{episode} = $episode if $episode;
		
			push( @ces , $ce );

    } else {
        # skip
    }
   } # next row
	
  } # next worksheet

  # save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
  
  return;
}

sub isDate {
  my ( $text ) = @_;

	unless( $text ) {
		next;
	}

  # format '2011-04-13'
  if( $text =~ /^\d{4}\-\d{2}\-\d{2}$/i ){
    return 1;

  # format '2011/05/12'
  } elsif( $text =~ /^\d{2}\/\d{2}\/\d{4}$/i ){
    return 1;
  }
}

sub ParseDate {
  my ( $text ) = @_;

  my( $year, $day, $month );

  # format '2011-04-13'
  if( $text =~ /^\d{4}\-\d{2}\-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\-(\d{2})\-(\d{2})$/i );

  # format '201'
  } elsif( $text =~ /^\d{2}\/\d{2}\/\d{4}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2})\/(\d{2})\/(\d{4})$/i );
  }

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    time_zone => "Europe/Stockholm"
      );

  $dt->set_time_zone( "UTC" );


	return $dt->ymd("-");
}

sub isTime {
  my ( $text ) = @_;

	unless( $text ) {
		next;
	}

  # format '2011-04-13'
  if( $text =~ /^\d{2}.\d{2}.\d{2}$/i ){
    return 1;
  }
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min, $sec );

  if( $text =~ /^\d+.\d+.\d+$/ ){
    ( $hour , $min, $sec ) = ( $text =~ /^(\d+).(\d+).(\d+)$/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("MusicBoxIT: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

1;
