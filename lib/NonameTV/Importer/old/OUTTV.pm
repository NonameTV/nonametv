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
use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);

use Text::Iconv;
 my $converter = Text::Iconv -> new ("utf-8", "windows-1251");
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

  if( $file =~ /\.xls|.xlsx$/i ){
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
  
  progress( "OUTTV: $chd->{xmltvid}: Processing $file" );

  #my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  my $oBook;
 	if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
 	else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }   #  staro, za .xls

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

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
						$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ );
						$columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Time/ );

          	$columns{'Genre'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Type and Genre/ );
          	$columns{'Season'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Season/ );
          	$columns{'Episode'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode/ );
          	
          	$columns{'Year'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Year/ );
          	
          	# Intro
          	$columns{'Intro'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Intro/ );
          	
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
      my $time = 0;
    	#$time = ParseTime($oWkC->{Val}) if( $oWkC->Value );
    	#if($time eq 0) {
    	#	$time = ParseTime($oWkC->Value) if( $oWkC->Value );
    	#}
    	
      #my $time = 0;  # fix for  12:00AM  ->Value
 	 		$time = $oWkC->{Val};
 	 		##Convert Excel Time -> localtime
 	 		$time = ExcelFmt('hh:mm', $time);

      # title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->{Val} if( $oWkC->Value );
      
      # Remove (N) from title
      $title =~ s/ \(N\)//g; 

			my ( $dummy, $episode, $season );

	  	# Season
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Season'}] if $columns{'Season'};
      $season = $oWkC->{Val} if $columns{'Season'};
      
      # Episode
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Episode'}] if $columns{'Episode'};
      $episode = $oWkC->{Val} if $columns{'Episode'};
      
      # genre (column 5)
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Genre'}] if $columns{'Genre'};
      my $genre = $oWkC->{Val} if $columns{'Genre'};
      
      # Year
	  	$oWkC = $oWkS->{Cells}[$iR][$columns{'Year'}] if $columns{'Year'};
      my $year = $oWkC->{Val} if $columns{'Year'};

	  	# descr (column 7)
	  	my $desc2 = $oWkS->{Cells}[$iR][$columns{'Description'}]->Value if $oWkS->{Cells}[$iR][$columns{'Description'}];

			my $desc;
			my $intro = $oWkS->{Cells}[$iR][$columns{'Intro'}]->Value if $columns{'Intro'}; 
			if(($intro) and $intro ne "") {
				$desc = $intro." ".$desc2;
			} else {
				$desc = $desc2;
			}

			# empty last day array
     	undef @ces;

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };
      
      if($year) {
      	$ce->{production_date} = "$year-01-01";
    	}
      
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
  } elsif( $text =~ /^\d{2}.\d{2}.\d{4}$/ ){ # format '11/18/2011'
    ( $month, $day, $year ) = ( $text =~ /^(\d+).(\d+).(\d+)$/ );
  }  elsif( $text =~ /^\d{4}\/\d{2}\/\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\/(\d{2})\/(\d{2})$/i );
  } elsif( $text =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
 		( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
 	}

  $year += 2000 if $year < 100;


return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;
  $text = ExcelFmt('hh:mm', $text);
  #print("text: $text");

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;