package NonameTV::Importer::VisjonNorge;

use strict;
use warnings;

=pod
Importer for Visjon Norge

Every week is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use Spreadsheet::ParseExcel::Utility qw(ExcelFmt ExcelLocaltime LocaltimeExcel);

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

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "VisjonNorge: Unknown file format: $file" );
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

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main foreach
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "VisjonNorge: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

	my $foundcolumns = 0;

    # browse through rows
    for(my $iR = 6 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

			$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /tittel/ );
            $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /lang tekst/ );

            $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /dato/ );
            $columns{'StartTime'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /start/ ); # Dont set the time to EET
            $columns{'EndTime'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /slutt/ );

            $columns{'extradesc'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /kort tekst/ );

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /dato/ );
          }
        }

        %columns = () if( $foundcolumns eq 0 );

        next;
      }

      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      #print Dumper($oWkC);
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
        progress("VisjonNorge: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

	  # time
	  $oWkC = $oWkS->{Cells}[$iR][$columns{'StartTime'}];
      next if( ! $oWkC );
      my $time = $oWkC->Value if( $oWkC->Value );
      if($time eq "24:00") { $time = "00:00"}

      # end time
	  $oWkC = $oWkS->{Cells}[$iR][$columns{'EndTime'}];
      my $endtime = $oWkC->Value if( $oWkC->Value );
      if($endtime eq "24:00") { $endtime = "00:00"}

      # title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

	  # extra info
	  my $desc = $oWkS->{Cells}[$iR][$columns{'Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'Synopsis'}];
      progress("VisjonNorge: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };

      $ce->{end_time} = $endtime if defined $endtime;

      $dsh->AddProgramme( $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $monthname, $year, $month );

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+-\S*-\d+$/ ) { # format '01/11/2008'
    ( $day, $monthname, $year ) = ( $text =~ /^(\d+)-(\S*)-(\d+)$/i );
    $month = MonthNumber( $monthname, 'en' );
  }

  $year += 2000 if( $year < 100 );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;
