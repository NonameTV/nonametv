package NonameTV::Importer::MezzoEN;

use strict;
use warnings;


=pod

Import data from XLSX files delivered via e-mail.

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

use NonameTV qw/norm normUtf8 AddCategory MonthNumber/;
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

  #$self->{datastore}->{augment} = 1;

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

  if( $file =~ /\.xlsx$/i ){
    $self->ImportXLS( $file, $chd );
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
  progress( "Ginx: $xmltvid: Processing $file" );

	my %columns = ();
  my $date;
  my $currdate = "x";
  my $coldate = 0;
  my $coltime = 1;
  my $coltitle = 3;
  my $colyear = 4;
  my $coldesc = 7;

my $oBook;

if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }

#my $ref = ReadData ($file);

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} !~ /1/ ){
      progress( "MezzoEN: Skipping other sheet: $oWkS->{Name}" );
      next;
    }

    progress( "MezzoEN: Processing worksheet: $oWkS->{Name}" );

	my $foundcolumns = 0;
    # browse through rows
    my $i = 0;
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    $i++;

      my $oWkC;

      # date
            $oWkC = $oWkS->{Cells}[$iR][$coldate];
            next if( ! $oWkC );

      	  $date = $oWkC->{Val} if( $oWkC->Value );
            $date = ParseDate( ExcelFmt('yyyy-mm-dd', $date) );
            next if( ! $date );

      if( $date ne $currdate ){

        progress("MezzoEN: Date is $date");

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

      $oWkC = $oWkS->{Cells}[$iR][$coldesc];
      my $desc = $oWkC->Value if( $oWkC );


      my $ce = {
        channel_id  => $channel_id,
        start_time  => $time,
        title 		=> norm($title),
        description => norm($desc),
      };

      # Prod year
	  $oWkC = $oWkS->{Cells}[$iR][$colyear];
	  my $year = $oWkC->Value if( $oWkC );

	  if(($year) and $year ne "" and $year =~ /(\d\d\d\d)/) {
	  	$ce->{production_date} = "$1-01-01";
	  }


		 my( $t, $st ) = ($ce->{title} =~ /(.*)\: (.*)/);
         if( defined( $st ) )
         {
              # This program is part of a series and it has a colon in the title.
              # Assume that the colon separates the title from the subtitle.
              $ce->{title} = $t;
              $title = $t;
              $ce->{subtitle} = $st;
         }

	  progress("MezzoEN: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $day, $month, $year );

#print ">$dinfo<\n";

  # format '033 03 Jul 2008'
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{2}.\d{2}.\d{4}$/ ){ # format '11/18/2011'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}\/\d{1,2}\/\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  else {
    return undef;
  }

  return undef if( ! $year);

  $year+= 2000 if $year< 100;

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          );

  $dt->set_time_zone( "UTC" );

  return $dt->ymd();
}



1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End: