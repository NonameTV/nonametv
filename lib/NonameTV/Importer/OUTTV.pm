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
          	$columns{'Episode'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode number/ );
          
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

	  	# Episode info (column 6)
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Episode'}] if $columns{'Episode'};
      my $episode = $oWkC->Value;
      
      # genre (column 5)
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Genre'}];
      my $genre = $oWkC->Value;

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
      		if( $genre ){
						my($program_type, $category ) = $ds->LookupCat( 'OUTTV', $genre );
						AddCategory( $ce, $program_type, $category );
					}
      
      		# Get production date and category
					if(($genre =~ /film/) and (defined $episode)) {
						# Find production year from description.
  					if( $episode =~ /\((\d\d\d\d)\)/ )
  					{
    					$ce->{production_date} = "$1-01-01";
  					}
						
						# Check description after categories.
      			my ( $program_type, $category ) = ParseDescCatSwe( $episode );
  					AddCategory( $ce, $program_type, $category );
  					
  					$ce->{program_type} = 'movies';
  					
  					$film = 1;
					}

				# Try to extract episode-information from the description.
				if((defined $episode) and ($film eq 0)) {
  				my( $ep, $eps, $sea, $dummy );

  				# Säsong 2
  				( $dummy, $sea ) = ($episode =~ /\b(S.song)\s+(\d+)/ );

  				# Avsnitt 2
					( $dummy, $ep ) = ($episode =~ /\b(Avsnitt)\s+(\d+)/ );

  				# Episode info in xmltv-format
  				if( (defined $ep) and (defined $sea) )
   				{
        		$ce->{episode} = sprintf( "%d . %d .", $sea-1, $ep-1 );
   				}

  				# Avsnitt/Del 2 av 3
  				( $dummy, $ep, $eps ) = ($episode =~ /\b(Del|Avsnitt)\s+(\d+)\s*av\s*(\d+)/ );
					$ce->{episode} = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    			if defined $eps;
  
  				if( defined $ce->{episode} ) {
    				$ce->{program_type} = 'series';
					}
				}


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

1;