package NonameTV::Importer::TravelChannel_v2;

use strict;
use warnings;

=pod
Importer for BBC Worldwide

Channels: BBC Entertainment, BBC Knowledge, BBC HD, BBC Lifestyle, CBeebies

The excel files is downloaded from TravelChannels.com

Every month is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use Data::Dumper;

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

    $self->ImportXLS( $file, $chd );

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
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }   #  staro, za .xls
  my $ref = ReadData ($file);

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Travel: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

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

			$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Series Title/ );

          $columns{'Episode Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode Title/ );
          
          $columns{'Ser No'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Series$/ );
          $columns{'Ep No'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Episode$/ );
          
          $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Epg/ );
          $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Listing/ );
          
          $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/ );
          $columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Plan Time/ );

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
			# save last day if we have it in memory
		#	FlushDayData( $channel_xmltvid, $dsh , @ces );
			$dsh->EndBatch( 1 );
        }
      
      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("Travel: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" ); 
        $currdate = $date;
      }

	  # time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );

      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );

	  #Convert Excel Time -> localtime
      $time = ExcelFmt('hh:mm', $time);
      $time =~ s/_/:/g; # They fail sometimes

      # title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

	  # episode and season
      my $epino = $oWkS->{Cells}[$iR][$columns{'Ep No'}]->Value if $oWkS->{Cells}[$iR][$columns{'Ep No'}];
      my $seano = $oWkS->{Cells}[$iR][$columns{'Ser No'}]->Value if $oWkS->{Cells}[$iR][$columns{'Ser No'}];

	  # extra info
	  my $desc = $oWkS->{Cells}[$iR][$columns{'Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'Synopsis'}];
	  my $subtitle = $oWkS->{Cells}[$iR][$columns{'Episode Title'}]->Value if $oWkS->{Cells}[$iR][$columns{'Episode Title'}];

      progress("Travel: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };

	  # Subtitle
	  $ce->{subtitle} = norm( $subtitle ) if $subtitle;

      if( $epino ){
        if( $seano ){
          $ce->{episode} = sprintf( "%d . %d .", $seano-1, $epino-1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $epino-1 );
        }
      }

      $dsh->AddProgramme( $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;
  print("Text: \"$text\"\n");

  $text =~ s/^\s+//;

  my( $dayname, $day, $monthname, $year, $month );

  if( $text =~ /^\d+\/(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\/\d+$/i ){
    ( $day, $monthname, $year ) = ( $text =~ /^(\d+)\/(\S+)\/(\d+)$/ );
    $month = MonthNumber( lc($monthname), "en" );
  }
  
  $year+= 2000 if $year< 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;
