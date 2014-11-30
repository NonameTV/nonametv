package NonameTV::Importer::Nonstop_XLS;

use strict;
use warnings;

=pod
Importer for Turner/NONSTOP

Channels: TNT Sweden, TNT Norway, TNT Denmark

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
my $converter = Text::Iconv -> new ("utf-8", "latin1");

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

  if( $file =~ /\.xlsx$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "Nonstop_XLS: Unknown file format: $file" );
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
  my $ref = ReadData ($file);

  # fields
  my $num_date = 0;
  my $num_time = 1;
  my $num_title = 2;
  my $num_subtitle = 3;
  my $num_genre = 4;
  my $num_directors = 7;
  my $num_actors = 6;
  my $num_prodyear = 5;
  my $num_country = 9;
  my $num_desc = 10;

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Nonstop_XLS: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    my $i = 0;
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      $i++;

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
        progress("Nonstop_XLS: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

	  # time
	  $oWkC = $oWkS->{Cells}[$iR][$num_time];
      next if( ! $oWkC );
      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );
      $time = ExcelFmt('hh:mm', $time);

      # title
      $oWkC = $oWkS->{Cells}[$iR][$num_title];
      next if( ! $oWkC );

      my $title = $oWkC->{Val} if( $oWkC->{Val} );
      $title =~ s/&amp;/&/ if( $oWkC->{Val} );
      next if( ! $title );

	  # extra info
	  my $desc = $oWkS->{Cells}[$iR][$num_desc]->Value if $oWkS->{Cells}[$iR][$num_desc];
	  my $year = $oWkS->{Cells}[$iR][$num_prodyear]->Value if $oWkS->{Cells}[$iR][$num_prodyear];

      progress("Nonstop_XLS: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm($desc),
      };

	  # Extra
	  $ce->{subtitle}        = norm($oWkS->{Cells}[$iR][$num_subtitle]->Value) if $oWkS->{Cells}[$iR][$num_subtitle];
	  $ce->{actors}          = parse_person_list(norm($oWkS->{Cells}[$iR][$num_actors]->Value))          if defined($num_actors) and $oWkS->{Cells}[$iR][$num_actors];
	  $ce->{directors}       = parse_person_list(norm($oWkS->{Cells}[$iR][$num_directors]->Value))       if defined($num_directors) and $oWkS->{Cells}[$iR][$num_directors];
      $ce->{production_date} = $year."-01-01" if defined($year) and $year ne "" and $year ne "0000";

      # Sometimes desc doesn't exist
      if(defined($ce->{description})) {
        # Episode info
        my ( $dummy, $season, $dummy3, $dummy2, $episode ) = ($ce->{description} =~ /\((S.song|Season|S.son)\s*(\d+)(, | )(avsnitt|episode|afsnit)\s*(\d+)\)/i );

        if(defined $season)
        {
            $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
            $ce->{program_type} = "series";
        }

        # Check subtitle
        if(!defined($season) and defined($ce->{subtitle})) {
            my ( $dummy21, $season2, $dummy23, $dummy22, $episode2 ) = ($ce->{subtitle} =~ /(S.song|Season|S.son)\s*(\d+)(, | )(avsnitt|episode|afsnit)\s*(\d+)/i );

            if(defined $season2 )
            {
                $ce->{episode} = sprintf( "%d . %d .", $season2-1, $episode2-1 );
                $ce->{program_type} = "series";
            }

            $ce->{subtitle} =~ s/(S.song|Season|S.son)\s*(\d+)(, | )(avsnitt|episode|afsnit)\s*(\d+)//i;
            $ce->{subtitle} = norm($ce->{subtitle});

            # remove subtitle if its empty
            if($ce->{subtitle} eq "") { delete($ce->{subtitle}); }
        }

        # clean
        $ce->{description} =~ s/\((S.song|Season|S.son)\s*(\d+)(, | )(avsnitt|episode|afsnit)\s*(\d+)\)//i;
        $ce->{description} = norm($ce->{description});
      }

      # It's a movie
      if(defined($ce->{directors}) and $ce->{directors} ne "") {
        # Not a director
        if($ce->{directors} =~ /^\-/) {
            delete($ce->{directors});
        } else {
            $ce->{program_type} = 'movie';
        }
      }

      # Series
      $ce->{program_type} = "series" if defined($ce->{subtitle}) and $ce->{subtitle} ne "";



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

  if( $text =~ /^(\d\d\d\d)-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  } elsif( $text =~ /^\d+-\d+-(\d\d\d\d)$/ ) { # format '2011-07-01'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
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
