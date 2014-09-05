package NonameTV::Importer::GlobalListings_xls;

use strict;
use warnings;

=pod
Importer for Global Listings (globalistings.info)

Channels: E! Entertainment Germany

Every month is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use Spreadsheet::Read;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/norm MonthNumber/;
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
    error( "GlobalListings_xls: Unknown file format: $file" );
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
  my $oBook;

  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }

  # fields
  my $num_date = 0;
  my $num_time = 1;
  my $num_title_org = 2;
  my $num_title = 3;
  my $num_subtitle_org = 4;
  my $num_subtitle = 5;
  my $num_season = 6;
  my $num_episode = 7;
  my $num_type = 8;
  my $num_directors = 10;
  my $num_actors = 11;
  my $num_prodyear = 12;
  my $num_country = 13;
  my $num_desc = 14;

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "GlobalListings_xls: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][$num_date];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

	  # Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
			# save last day if we have it in memory
		#	FlushDayData( $channel_xmltvid, $dsh , @ces );
			$dsh->EndBatch( 1 );
        }

      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("GlobalListings_xls: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

	  # time
	  $oWkC = $oWkS->{Cells}[$iR][$num_time];
      next if( ! $oWkC );
      my $time = $oWkC->Value if( $oWkC->Value );
      $time =~ s/'//g;

      # title
      $oWkC = $oWkS->{Cells}[$iR][$num_title];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

	  # episode and season
      my $epino = $oWkS->{Cells}[$iR][$num_episode]->Value if $oWkS->{Cells}[$iR][$num_episode];
      my $seano = $oWkS->{Cells}[$iR][$num_season]->Value  if $oWkS->{Cells}[$iR][$num_season];

	  # extra info
	  my $desc = $oWkS->{Cells}[$iR][$num_desc]->Value if $oWkS->{Cells}[$iR][$num_desc];
	  my $year = $oWkS->{Cells}[$iR][$num_prodyear]->Value if defined($columns{'Year'}) and $oWkS->{Cells}[$iR][$num_prodyear];

      progress("GlobalListings_xls: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };

	  # Extra
	  $ce->{subtitle}        = norm($oWkS->{Cells}[$iR][$num_subtitle]->Value) if $oWkS->{Cells}[$iR][$num_subtitle];
	  $ce->{actors}          = parse_person_list(norm($oWkS->{Cells}[$iR][$num_actors]->Value))          if defined($num_actors) and $oWkS->{Cells}[$iR][$num_actors];
	  $ce->{directors}       = parse_person_list(norm($oWkS->{Cells}[$iR][$num_directors]->Value))       if defined($num_directors) and $oWkS->{Cells}[$iR][$num_directors];
      $ce->{production_date} = $year."-01-01" if defined($year) and $year ne "" and $year ne "0000";

      if( $epino ){
        if( $seano ){
          $ce->{episode} = sprintf( "%d . %d .", $seano-1, $epino-1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $epino-1 );
        }
      }

      # org title
      $ce->{original_title}    = norm($oWkS->{Cells}[$iR][$num_title_org]->Value) if defined($oWkS->{Cells}[$iR][$num_title_org]) and $ce->{title} ne norm($oWkS->{Cells}[$iR][$num_title_org]->Value) and norm($oWkS->{Cells}[$iR][$num_title_org]->Value) ne "";
      $ce->{original_subtitle} = norm($oWkS->{Cells}[$iR][$num_subtitle_org]->Value) if defined($oWkS->{Cells}[$iR][$num_subtitle_org]) and $ce->{title} ne norm($oWkS->{Cells}[$iR][$num_subtitle_org]->Value) and norm($oWkS->{Cells}[$iR][$num_subtitle_org]->Value) ne "";


      $dsh->AddProgramme( $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;

  #print("text: $text\n");

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /\s*,\s*/, $str );

  return join( ";", grep( /\S/, @persons ) );
}

1;
