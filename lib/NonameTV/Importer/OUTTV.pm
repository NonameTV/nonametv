package NonameTV::Importer::OUTTV;

use strict;
use warnings;

=pod

Import data from OUTTV

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
  
  $self->{datastore}->{augment} = 1;

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

  progress( "OUTTV FlatXLS: $chd->{xmltvid}: Processing flat XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

    my($iR, $oWkS, $oWkC);
	
	  my( $time, $episode );
  my( $program_title , $program_description );
    my @ces;
  
  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

   # progress("--------- SHEET: $oWkS->{Name}");

    # start from row 2
    # the first row looks like one cell saying like "EPG DECEMBER 2007  (Yamal - HotBird)"
    # the 2nd row contains column names Date, Time (local), Progran, Description
    #for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # date (column 1)
      $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
	  if( isDate( $oWkC->Value ) ){
		$date = ParseDate( $oWkC->Value );
	  }
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
	  
	  # desc (column 4)
	  $oWkC = $oWkS->{Cells}[$iR][4];
      my $desc = $oWkC->Value;

      if( $time and $program_title ){
	  
	  # empty last day array
      undef @ces;
	  
        progress("$time $program_title");

        my $ce = {
          channel_id   => $chd->{id},
          title        => norm($program_title),
          start_time   => $time,
		  description  => $desc,
        };
        
          my ( $program_type, $category ) = ParseDescCatSwe( $ce->{description} );
  			AddCategory( $ce, $program_type, $category );
    
		if( $genre ){
			my($program_type, $category ) = $ds->LookupCat( 'OUTTV', $genre );
			AddCategory( $ce, $program_type, $category );
		}
		
		$self->extract_extra_info( $ce );
		
		# Make it readable
		$ce->{description} = norm($desc);
		
        $dsh->AddProgramme( $ce );
		
		push( @ces , $ce );
      }

    } # next row
	
  } # next worksheet

  $dsh->EndBatch( 1 );
  
  return;
}

## Extra thingies from Svt_web

sub extract_extra_info
{
  my $self = shift;
  my( $ce ) = shift;

  my( $ds ) = $self->{datastore};

  my( $program_type, $category );

  #
  # Try to extract category and program_type by matching strings
  # in the description. The empty entry is to make sure that there
  # is always at least one entry in @sentences.
  #

  my @sentences = (split_text( $ce->{description} ), "");
  
  ( $program_type, $category ) = ParseDescCatSwe( $sentences[0] );

  # If this is a movie we already know it from the svt_cat.
  if( defined($program_type) and ($program_type eq "movie") )
  {
    $program_type = undef; 
  }

  AddCategory( $ce, $program_type, $category );

  $ce->{title} =~ s/^\(N\)\s*//;
  
  $ce->{description} = join_text( @sentences );

  extract_episode( $ce );
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

  # Lines ending with a comma is not the end of a sentence
#  $t =~ s/,\s*\n+\s*/, /g;

# newlines have already been removed by norm() 
  # Replace newlines followed by a capital with space and make sure that there 
  # is a dot to mark the end of the sentence. 
#  $t =~ s/([\!\?])\s*\n+\s*([A-Z���])/$1 $2/g;
#  $t =~ s/\.*\s*\n+\s*([A-Z���])/. $1/g;

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
    # If this program has an episode-number, it is by definition
    # a series (?). Svt often miscategorize series as movie.
    $ce->{program_type} = 'series';
  }
}

##END##

sub isDate {
  my ( $text ) = @_;

#print ">$text<\n";

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

#print ">$text<\n";

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
