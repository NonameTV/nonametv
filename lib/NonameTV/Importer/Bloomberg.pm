package NonameTV::Importer::Bloomberg;

use strict;
use warnings;

=pod

Imports data from XLSX files for the Bloomberg station.

The importer is hard coded for Pan Europe.
Numbers for different countries:
UK Title: 0
UK Time: 1
Pan EU and Africa: 3
CET: 4
Middle East: 5
ME Time: 6
Asia: 7
HK Time: 8
US: 9
Eastern Time: 10

Notes: 11 (not used)

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;

use NonameTV qw/norm/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "High: Unknown file format: $file" );
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
  my @ces;
  
  progress( "High: Processing flat XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

		my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

	  # Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
					$dsh->EndBatch( 1 );
        }
      
      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("High: Date is $date");
        $dsh->StartDate( $date , "00:00" ); 
        $currdate = $date;
      }

	  	# time
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      my $time = ParseTime($oWkC->Value) if( $oWkC->Value );

      # title
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      
      $title =~ s/- In 3D//g; 
      $title =~ s/In 3D//g; 
      
      # season, episode, episode title
      my($ep, $season, $episode);
      ( $season, $ep ) = ($title =~ /\bSeason\s+(\d+)\s+EP\s+(\d+)/ );
      if(defined($season)) {
  	  	$episode = sprintf( "%d . %d . ", $season-1, $ep-1 );
  	  	$title =~ s/- Season (.*) EP (.*)\)//g;
  	  	$title =~ s/Season (.*) EP (.*)\)//g;
      }
      
      ( $ep ) = ($title =~ /\bEP\s+(\d+)/ );
      if(defined($ep) && !defined($episode)) {
      	$episode = sprintf( " . %d .", $ep-1 );
      	$title =~ s/- EP (.*)\)//g;
  	  	$title =~ s/EP (.*)\)//g;
      }
      
      my ($new_title, $episode_title) = split(/-/, $title);
      if(defined($new_title) and $new_title ne "") {
      	$title = $new_title;
      }
  	  

	  # empty last day array
      undef @ces;

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
      };
      
      if(defined($episode) && $episode ne "") {
      	$ce->{episode} = $episode;
      }
      
      if(defined($episode_title) && $episode_title ne "") {
      	$ce->{subtitle} = norm($episode_title);
      }
      
	  progress("High: $time - $title");
      $dsh->AddProgramme( $ce );

	  push( @ces , $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my ( $text ) = @_;

  my( $year, $day, $month );

  # format '2011-04-13'
  if( $text =~ /^\d{4}\-\d{2}\-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\-(\d{2})\-(\d{2})$/i );

  # format '2011/05/16'
  } elsif( $text =~ /^\d{4}\/\d{2}\/\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\/(\d{2})\/(\d{2})$/i );
   
  # format '1/14/2012'
  } elsif( $text =~ /^\d+\/\d+\/\d{4}$/i ){
    ( $month, $day, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/i );
  }
  

  $year += 2000 if $year < 100;


return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;
