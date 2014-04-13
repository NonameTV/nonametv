package NonameTV::Importer::Ginx;

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
  my $coldate = 1;
  my $coltime = 2;
  my $coltitle = 6;
  my $colepisode = 7;
  my $coldesc = 8;

my $oBook;

if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }

#my $ref = ReadData ($file);

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} !~ /EPG/ ){
      progress( "Ginx: Skipping other sheet: $oWkS->{Name}" );
      next;
    }

    progress( "Ginx: Processing worksheet: $oWkS->{Name}" );

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

        progress("Ginx: Date is $date");

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

	  # Episode
	  $oWkC = $oWkS->{Cells}[$iR][$colepisode];
	  my $episode = $oWkC->Value if( $oWkC );

      # Try to extract episode-information from the description.
		if(($episode) and ($episode ne ""))
		{
			$ce->{episode} = sprintf( ". %d .", $episode-1 );
		}

		if( defined $ce->{episode} ) {
			$ce->{program_type} = 'series';
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

	  progress("Ginx: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  $dinfo = ExcelFmt('yyyy-mm-dd', $dinfo);

  my( $day, $monthname, $year );

#print ">$dinfo<\n";

  # format '033 03 Jul 2008'
  if( $dinfo =~ /^\d+\s+\d+\s+\S+\s+\d+$/ ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^\d+\s+(\d+)\s+(\S+)\s+(\d+)$/ );

  # format '2014/Jan/19'
  } elsif( $dinfo =~ /^\d+\/(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\/\d+$/i ){
        ( $year, $monthname, $day ) = ( $dinfo =~ /^(\d+)\/(\S+)\/(\d+)$/ );

      # format 'Fri 30 Apr 2010'
  } elsif( $dinfo =~ /^\d+-(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)-\d+$/i ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^(\d+)-(\S+)-(\d+)$/ );

  # format 'Fri 30 Apr 2010'
  } elsif( $dinfo =~ /^\S+\s*\d+\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*\d+$/i ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^\S+\s*(\d+)\s*(\S+)\s*(\d+)$/ );
  } elsif( $dinfo =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $monthname, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  }

  else {
    return undef;
  }

  return undef if( ! $year);

  $year+= 2000 if $year< 100;

  my $mon = MonthNumber( $monthname, "en" );

  my $dt = DateTime->new( year   => $year,
                          month  => $mon,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          );

  #$dt->set_time_zone( "UTC" );

  return $dt->ymd();
}



1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
