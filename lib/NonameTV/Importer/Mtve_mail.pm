package NonameTV::Importer::Mtve_mail;

use strict;
use warnings;

=pod
Importer for MTVNHD

The excel files is sent via mail

Every day is runned as a seperate batch.

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

  if( $file =~ /\.xlsx|.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "Mtve_mail: Unknown file format: $file" );
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
  
  progress( "Mtve_mail: $chd->{xmltvid}: Processing $file" );

	my $oBook;
	if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
	else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }   #  staro, za .xls

  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
  	
		my $foundcolumns = 0;
		
    # browse through rows
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {


      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

						$columns{'Start'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Start/ );
						$columns{'End'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /End/ );
						$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ );
          
          	
          
          	$columns{'Description'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Description/ );

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Start/ );
          }
        }
#foreach my $cl (%columns) {
#	print "$cl\n";
#}
        %columns = () if( $foundcolumns eq 0 );

        next;
      }

	  my $oWkDate = $oWkS->{Cells}[$iR][$columns{'Start'}];
      next if( ! $oWkDate );

      # date & Time - column 1 ('Date')
      my( $date, $time ) = split( ' ', $oWkDate->Value );
      
      $date = ParseDate( $date );
      next if( ! $date );

	  #Convert Excel Time -> localtime
 	  $time = ExcelFmt('hh:mm', $time);
      
      my $enddate = $oWkS->{Cells}[$iR][$columns{'End'}]->Value;
      my( $enddate2, $endtime ) = split( ' ', $enddate );
	  # Convert Excel Time -> localtime
	  $endtime = ExcelFmt('hh:mm', $endtime);

	  	# Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
					$dsh->EndBatch( 1 );
        }
      
      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("Mtve_mail: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" ); 
        $currdate = $date;
      }

      # title
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      
      # Remove *** Premiere *** 
      $title =~ s/\*\*\* premiere \*\*\* //g; 
      $title =~ s/\*\*\* premiere\*\*\* //g; 
      $title =~ s/\*\*\* PREMIERE \*\*\* //g; 
      
      # Uppercase the first letter
      $title = ucfirst($title);
      
      # Replace and upstring
      $title =~ s/Hd/HD/;  #replace hd with HD
      $title =~ s/Mtv/MTV/;  #replace mtv with MTV

	  	# descr (column 7)
	  	my $desc = $oWkS->{Cells}[$iR][$columns{'Description'}]->Value if $oWkS->{Cells}[$iR][$columns{'Description'}];

			# empty last day array
     	undef @ces;

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        end_time => $endtime,
        description => norm( $desc ),
      };
      
      # Seperate :
      my ( $subtitle ) = ($ce->{title} =~ /:\s*(.+)$/);
  		$ce->{title} =~ s/:\s*(.+)//;
      
      
      # Uc First it
      ( $ce->{subtitle} ) = (ucfirst($subtitle)) if $subtitle;

			progress("Mtve_mail: $chd->{xmltvid}: $time - $title");
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
  #print("text: $text");

  # format '2011-04-13'
  if( $text =~ /^\d{4}\-\d{2}\-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\-(\d{2})\-(\d{2})$/i );

  # format '2011/05/16'
  } elsif( $text =~ /^\d{4}\/\d{2}\/\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\/(\d{2})\/(\d{2})$/i );
  } elsif( $text =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
     ( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
   }

  $year += 2000 if $year < 100;


	return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;