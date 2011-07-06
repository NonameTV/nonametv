package NonameTV::Importer::OUTTV;

use strict;
use warnings;

=pod

Import data from OUTTV
Every week is handled as a seperate batch.
The files is sent by OUTTV as mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/norm AddCategory ParseDescCatSwe MonthNumber/;
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
    error( "OUTTV: Unknown file format: $file" );
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

  progress( "OUTTV: $chd->{xmltvid}: Processing flat XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  my($iR, $oWkS, $oWkC);
	
  my( $time, $episode );
  my( $program_title , $program_description );
  my @ces;
  
  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # date (column 1)
      $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
	  if( isDate( $oWkC->Value ) ){
		$date = ParseDate( $oWkC->Value );
	  }
      next if( ! $date );

	  # No date? Skip.
	  unless( $date ) {
	  	next;
	  }
	  
	  if($date ne $currdate ) {
        if( $currdate ne "x" ) {
			$dsh->EndBatch( 1 );
        }



        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("OUTTV: Date is: $date");
      }

	  # time (column 1)
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );

      # program_title (column 2)
      $oWkC = $oWkS->{Cells}[$iR][2];
      $program_title = $oWkC->Value;
	  
	  # genre (column 3)
	  $oWkC = $oWkS->{Cells}[$iR][3];
      my $genre = $oWkC->Value;
	  
	  # description (column 4)
	  $oWkC = $oWkS->{Cells}[$iR][4];
      my $desc = $oWkC->Value;

      if( $time and $program_title ){
	  
	  	# empty last day array
     	undef @ces;
	  
        

        my $ce = {
          channel_id   => $chd->{id},
          title        => norm($program_title),
          start_time   => $time,
		  description  => $desc,
        };
    
    	# Check description after categories.
      	my ( $program_type, $category ) = ParseDescCatSwe( $desc );
  		AddCategory( $ce, $program_type, $category );
    
		if( $genre ){
			my($program_type, $category ) = $ds->LookupCat( 'OUTTV', $genre );
			AddCategory( $ce, $program_type, $category );
		}
		
		# Extract episode info, categories in description
		$self->extract_extra_info( $ce );
		
		progress("$time $program_title");
		
		# Add programme
        $dsh->AddProgramme( $ce );
		
		push( @ces , $ce );
      }

    } # next row
	
  } # next worksheet

  $dsh->EndBatch( 1 );
  
  # Success
  return 1;
}

sub extract_extra_info
{
  my $self = shift;
  my( $ce ) = shift;

  my( $ds ) = $self->{datastore};

  my( $program_type, $category );

  my @sentences = (split_text( $ce->{description} ), "");

  # Remove (N) from title
  $ce->{title} =~ s/ \(N\)//g;
  
  $ce->{description} = join_text( @sentences );

  extract_episode( $ce );
  
  # Make it readable.
  $ce->{description} = norm($ce->{description});
}

# Split a string into individual sentences.
sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # We might have introduced some errors above. Fix them.
  $t =~ s/([\?\!])\./$1/g;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./g;

  # Turn all whitespace into pure spaces and compress multiple whitespace 
  # to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Mark sentences ending with '.', '!', or '?' for split, but preserve the 
  # ".!?".
  $t =~ s/([\.\!\?])\s+([A-Z���])/$1;;$2/g;
  
  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
    $sent[-1] .= "." 
      unless $sent[-1] =~ /[\.\!\?]$/;
  }

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( " ", grep( /\S/, @_ ) );
  $t =~ s/::/../g;

  return $t;
}

sub extract_episode
{
  my( $ce ) = @_;

  return if not defined( $ce->{description} );

  my $d = $ce->{description};

  # Try to extract episode-information from the description.
  my( $ep, $eps, $sea );
  my $episode;

  my $dummy;

  # Säsong 2
  ( $dummy, $sea ) = ($d =~ /\b(S.song)\s+(\d+)/ );

  # Avsnitt 2
  ( $dummy, $ep ) = ($d =~ /\b(Avsnitt)\s+(\d+)/ );

  # Episode info in xmltv-format
  if( (defined $ep) and (defined $sea) )
   {
        $episode = sprintf( "%d . %d .", $sea-1, $ep-1 );
   }

  # Avsnitt/Del 2 av 3
  ( $dummy, $ep, $eps ) = ($d =~ /\b(Del|Avsnitt)\s+(\d+)\s*av\s*(\d+)/ );
  $episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    if defined $eps;
  
  if( defined $episode ) {
    $ce->{episode} = $episode;
    $ce->{program_type} = 'series';
  }
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
  } elsif( $text =~ /^\d{4}\/\d{2}\/\d{2}$/i ){
    return 1;
  }

  next;
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

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
