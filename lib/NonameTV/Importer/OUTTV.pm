package NonameTV::Importer::OUTTV;

use strict;
use warnings;

=pod
Importer for OUTTV Sweden

The excel files is sent via mail

Every week is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;

use NonameTV qw/norm AddCategory ParseDescCatSwe/;
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

    $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "OUTTV: Unknown file format: $file" );
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
  
  progress( "OUTTV: $chd->{xmltvid}: Processing flat XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    #progress( "BBCWW: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

	my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {


      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

						$columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/ );
						$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Titel/ );
						$columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Time/ );

          	$columns{'Genre'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Genre/ );
          	$columns{'Season'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Säsong/ );
          	$columns{'Episode'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Avsnitt/ );
          	
          	$columns{'Year'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Year/ );
          	$columns{'Movie'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Movie Genre/ );
          	
          	$columns{'Description'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Program info/ );

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/ );
          }
        }
#foreach my $cl (%columns) {
#	print "$cl\n";
#}
        %columns = () if( $foundcolumns eq 0 );

        next;
      }



      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
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
        progress("OUTTV: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" ); 
        $currdate = $date;
      }

	  	# time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      my $time = ParseTime($oWkC->Value) if( $oWkC->Value );

      # title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      
      # Remove (N) from title
      $title =~ s/ \(N\)//g; 

			my ( $dummy, $episode, $season );

	  	# Season
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Season'}] if $columns{'Season'};
      $season = $oWkC->Value if $columns{'Season'};
      
      # Episode
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Episode'}] if $columns{'Episode'};
      $episode = $oWkC->Value if $columns{'Episode'};
      
      # genre (column 5)
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Genre'}] if $columns{'Genre'};
      my $genre = $oWkC->Value if $columns{'Genre'};
      
      # movie genre
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Movie'}] if $columns{'Movie'};
      my $moviegenre = $oWkC->Value if $columns{'Movie'};
      
      # Year
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Year'}] if $columns{'Year'};
      my $year = $oWkC->Value if $columns{'Year'};

	  	# descr (column 7)
	  	my $desc = $oWkS->{Cells}[$iR][$columns{'Description'}]->Value if $oWkS->{Cells}[$iR][$columns{'Description'}];

			# empty last day array
     	undef @ces;

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };
      
      		my $film = 0;
      
      		# Get genre
						my($program_type, $category ) = $ds->LookupCat( 'OUTTV', $genre );
						AddCategory( $ce, $program_type, $category );

				# Try to extract episode-information from the description.
				if(($season) and ($season ne "") and ($film eq 0)) {

  				# Episode info in xmltv-format
  				if(($episode) and ($episode ne "") and ($season ne "") )
   				{
        		$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
   				}
  
  				if( defined $ce->{episode} ) {
    				$ce->{program_type} = 'series';
					}
				}

				extract_extra_info( $dsh, $ce );

			progress("OUTTV: $chd->{xmltvid}: $time - $title");
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
  
  # Empty string
  unless( $text ) {
		return 0;
	}
	
	if($text eq "") {
		return 0;
	}
	
	if($text eq "Date") {
		return 0;
	}

  # format '2011-04-13'
  if( $text =~ /^\d{4}\-\d{2}\-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\-(\d{2})\-(\d{2})$/i );

  # format '2011/05/16'
  } elsif( $text =~ /^\d{4}\/\d{2}\/\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\/(\d{2})\/(\d{2})$/i );
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

# From Kanal5_Util
# Hopefully they will add more info into desc

sub extract_extra_info
{
  my( $dsh, $ce ) = @_;

  my $ds = $dsh->{ds};

  my @sentences = (split_text( $ce->{description} ), "");
  for( my $i=0; $i<scalar(@sentences); $i++ )
  {
    $sentences[$i] =~ tr/\n\r\t /    /s;
		
		if( my( $seaso, $episod ) = ($sentences[$i] =~ /^S(\d+)E(\d+)/ ) )
    {
    	$ce->{episode} = sprintf( " %d . %d . ", $seaso-1, $episod-1 ) if $episod;
    	$ce->{program_type} = 'series';
    	
    	# Remove from description
      $sentences[$i] = "";
    }

  }

  $ce->{description} = join_text( @sentences );
  
  
}

sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./;

  # Replace newlines followed by a capital with space and make sure that there is a dot
  # to mark the end of the sentence. 
  $t =~ s/\.*\s*\n\s*([A-Z���])/. $1/g;

  # Turn all whitespace into pure spaces and compress multiple whitespace to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # Split on a dot and whitespace followed by a capital letter,
  # but the capital letter is included in the output string and
  # is not removed by split. (?=X) is called a look-ahead.
#  my @sent = grep( /\S/, split( /\.\s+(?=[A-Z���])/, $t ) );

  # Mark sentences ending with a dot for splitting.
  $t =~ s/\.\s+([A-Z���])/;;$1/g;

  # Mark sentences ending with ! or ? for split, but preserve the "!?".
  $t =~ s/([\!\?])\s+([A-Z���])/$1;;$2/g;
  
  my @sent = grep( /\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    $sent[-1] =~ s/\.*\s*$//;
  }

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( ". ", grep( /\S/, @_ ) );
  $t .= "." if $t =~ /\S/;
  $t =~ s/::/../g;

  # The join above adds dots after sentences ending in ! or ?. Remove them.
  $t =~ s/([\!\?])\./$1/g;

  return $t;
}

1;