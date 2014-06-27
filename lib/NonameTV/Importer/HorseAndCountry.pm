package NonameTV::Importer::HorseAndCountry;

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
  }


  return;
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
  progress( "Euronews: $xmltvid: Processing $file" );

	my %columns = ();
  my $date;
  my $currdate = "x";
  my $coldate = 1;
  my $coltime = 2;
  my $coltitle = 3;
  my $coldesc = 5;
  my $colsubtitle = 4;

my $oBook;

if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }   #  staro, za .xls
#elsif ( $file =~ /\.xml$/i ){ $oBook = Spreadsheet::ParseExcel::Workbook->Parse($file); progress( "using .xml" );    }   #  staro, za .xls
#print Dumper($oBook);
my $ref = ReadData ($file);

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "Euronews: Processing worksheet: $oWkS->{Name}" );

	my $foundcolumns = 0;
    # browse through rows
    my $i = 2;
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    $i++;

      my $oWkC;

      # date
      $oWkC = $oWkS->{Cells}[$iR][$coldate];
      #next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value ) if defined($oWkC);

      if(defined($date) and $date ne $currdate ){

        progress("HaC: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;
      }

      next if( $currdate eq "x" );

      # time
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC );

      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );

	  #Convert Excel Time -> localtime
      $time = ExcelFmt('hh:mm', $time);

      # title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      my $title = norm($oWkC->Value) if( $oWkC->Value );

      # subtitle
      $oWkC = $oWkS->{Cells}[$iR][$colsubtitle];
      my $subtitle = norm($oWkC->Value);

      my $ce = {
        channel_id  => $channel_id,
        start_time  => $time,
        title       => $title,
        subtitle    => $subtitle,
      };


      my ($season, $episode, $eps);
      $oWkC = $oWkS->{Cells}[$iR][$coldesc];
      if(defined($oWkC) and $oWkC->Value) {
        $ce->{description} = norm($oWkC->Value);

        # Clean it
        $ce->{description} =~ s/\(.*\)$//g;
        $ce->{description} = norm($ce->{description});

        # Episode
        ( $season )            = ($ce->{description} =~ /S(\d+)/ );
        ( $episode, $eps )     = ($ce->{description} =~ /Ep\s+(\d+)\/(\d+)/ );
      }

      my ( $dummy, $episode2 )  = ($subtitle =~ /^(Ep|Episode)\s+(\d+)$/ );

      # Episode
      if(defined($episode) and $episode) {
      	if(defined($season) and $season) {
      		if(defined($eps)) {
      			$ce->{episode} = sprintf( "%d . %d/%d . ", $season-1, $episode-1, $eps );
      		} else {
      			$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      		}
      	}elsif(defined($eps)) {
      		$ce->{episode} = sprintf( " . %d/%d . ", $episode-1, $eps );
      	} else {
      		$ce->{episode} = sprintf( " . %d . ", $episode-1 );
      	}
      } elsif(defined($episode2) and $episode2 > 0) {
      	if($season) {
      		$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode2-1 );
      	} else {
      		$ce->{episode} = sprintf( " . %d . ", $episode2-1 );
      	}
      }

      # remove "episode" subtitls, dummy.
      if(defined($episode2)) {
        $ce->{subtitle} = undef;
      }

	  progress("HaC: $time - $title") if $title;
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
