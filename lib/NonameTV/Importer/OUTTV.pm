package NonameTV::Importer::OUTTV;

use strict;
use warnings;


=pod

Import data from XLS or XLSX files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Spreadsheet::Read;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");


use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm normUtf8 AddCategory/;
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

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xls|.xlsx$/i ){
    $self->ImportXLS( $file, $chd );
  }elsif( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  }


  return;
}

sub ImportXML {
	my $self = shift;
  my( $file, $chd ) = @_;
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $self->{fileerror} = 1;
  
	# Do something beautiful here later on. 
	
	error("From now on you need to convert XML files to XLS files.");
	
	return 0;
}

sub ImportXLS {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls or .xlsx files.
  progress( "OUTTV: $xmltvid: Processing $file" );

	my %columns = ();
  my $date;
  my $currdate = "x";
  my $coldate = 0;
  my $coltime = 1;
  my $coltitle = 4;
  my $colepisode = 9;
  my $coldesc = 11;
  my $colseason = 8;
  my $colyear = 6;
  my $colgenre = 5;

my $oBook;

if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }   #  staro, za .xls
#elsif ( $file =~ /\.xml$/i ){ $oBook = Spreadsheet::ParseExcel::Workbook->Parse($file); progress( "using .xml" );    }   #  staro, za .xls
#print Dumper($oBook);
my $ref = ReadData ($file);

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} !~ /1/ ){
      progress( "OUTTV: Skipping other sheet: $oWkS->{Name}" );
      next;
    }

    progress( "OUTTV: Processing worksheet: $oWkS->{Name}" );

	my $foundcolumns = 0;
    # browse through rows
    my $i = 0;
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    $i++;

      my $oWkC;

      # date
      $oWkC = $oWkS->{Cells}[$iR][$coldate];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("OUTTV: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC );



      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );

	  #Convert Excel Time -> localtime
      $time = ExcelFmt('hh:mm', $time);
      $time =~ s/_/:/g; # They fail sometimes


      # title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      
      $title =~ s/\(N\)//g if $title;

      

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };
      
      # Desc (only works on XLS files)
      	my $field = "L".$i;
      	my $desc = $ref->[1]{$field};
      	$ce->{description} = normUtf8($desc) if( $desc );
      	$desc = '';


		# Genre
		$oWkC = $oWkS->{Cells}[$iR][5];
		if( $oWkC and $oWkC->Value ne "" ) {
	      	my $genre = $oWkC->Value;
			my($program_type, $category ) = $ds->LookupCat( 'OUTTV', $genre );
			AddCategory( $ce, $program_type, $category );
		}
			
	  # Episode
	  $oWkC = $oWkS->{Cells}[$iR][$colepisode];
	  my $episode = $oWkC->Value if( $oWkC );
	  $oWkC = $oWkS->{Cells}[$iR][$colseason];
	  my $season = $oWkC->Value if( $oWkC );
	  
	  # Prod year
	  $oWkC = $oWkS->{Cells}[$iR][$colyear];
	  my $year = $oWkC->Value if( $oWkC );
	  
	  if(($year) and $year ne "" and $year =~ /(\d\d\d\d)/) {
	  	$ce->{production_date} = "$1-01-01";
	  	$ce->{program_type} = 'movie'; # Only movies and documentary movies got year.
	  }
      
      # Try to extract episode-information from the description.
	  if(($season) and ($season ne "")) {
		# Episode info in xmltv-format
		if(($episode) and ($episode ne "") and ($season ne "") )
		{
			$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
		}
  
		if( defined $ce->{episode} ) {
			$ce->{program_type} = 'series';
		}
	  }
      
	  progress("OUTTV: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;
  
  #print Dumper($dinfo);

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

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
