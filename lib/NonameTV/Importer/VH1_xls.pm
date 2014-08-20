package NonameTV::Importer::VH1_xls;

use strict;
use warnings;

=pod

channel: VH1 Europe, VH1 Classic Europe

Import data from Excel-files delivered via e-mail.
Each file contains more sheets, one sheet per week.

Features:

=cut

use utf8;

use DateTime;
#use Time::Zone;

use Spreadsheet::ParseExcel;
use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt); # ExcelLocaltime LocaltimeExcel

use Text::Iconv;
 my $converter = Text::Iconv -> new ("utf-8", "windows-1251"); #edit

use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV qw/AddCategory norm MonthNumber/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

# File types
use constant {
  FT_UNKNOWN  => 0,  # unknown
  FT_FLATXLS  => 1,  # flat xls file
  FT_GRIDXLS  => 2,  # xls file with grid
};


sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Belgrade" ); #edit
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $ft = CheckFileFormat( $xmltvid, $file );

  if( $ft eq FT_FLATXLS ){
    $self->ImportFlatXLS( $file, $channel_id, $xmltvid );
  } elsif( $ft eq FT_GRIDXLS ){
    $self->ImportGridXLS( $file, $channel_id, $xmltvid );
  } else {
    error( "VH1_xls: $xmltvid: Unknown file format of $file" );
  }

  return;
}


sub CheckFileFormat
{
  my( $xmltvid, $file ) = @_;

  # Only process .xls files.
  return if( $file !~ /\.xlsx|.xls$/i );

  my $oBook;
  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
   else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }
  return FT_UNKNOWN if( ! $oBook );

  progress( "VH1_xls: $xmltvid: Found $oBook->{SheetCount} sheets in the file" );

  my( $oWkS, $oWkC );

  # the flat sheet file which sometimes uses
  # column names in the first row
  # check against the name of the 4th column value of the first row
  # the content of this column shoul be 'Programme Title'
  $oWkS = $oBook->{Worksheet}[0];
  $oWkC = $oWkS->{Cells}[0][3];
  if( $oWkC ){
    return FT_FLATXLS if( $oWkC->Value =~ /Title$/ );
  }

  # xls files with grid
  # which can differ from day to day or can
  # contain the schema for the whole period
  $oWkS = $oBook->{Worksheet}[0];
  return FT_GRIDXLS if( $oWkS->{Name} =~ /^Week/i );

  return FT_UNKNOWN;
}


sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  $self->{fileerror} = 0;

  #my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls(x) files.
  return if( $file !~ /\.xlsx|.xls$/i );
  progress( "VH1_xls FLAT: $xmltvid: Processing $file " );

  my %columns = ();
  my ($date, $time);
  my $currdate = "x";

  # my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  my $oBook;
  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }  #( $mesec ) = ( $file =~ /_v(\d*).xls/ ) 
   else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }   #  staro, za .xls




  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    if( norm($oWkS->{Name}) !~ /(Arkusz1|Sheet1|V1CE|VH1)/ ){ #$chd->{grabber_info}
      progress( "$xmltvid: Skipping worksheet: $oWkS->{Name}" );
      next;
    }
    progress( "VH1_xls FLAT: $xmltvid: Processing worksheet: $oWkS->{Name} " );

    # browse through rows
    # schedules are starting after that
    # valid schedule row must have date, time and title set

    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++){
          $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
        }
        foreach my $cl (%columns) {print ">$cl<\n";}
        next;
      }

      my $oWkC;

      # date - column 'TX Date'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("VH1_xls FLAT: $xmltvid: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # date - column 'TX Time'
<<<<<<< HEAD
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TX Time CET'}];
=======
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Time (UTC/GMT +1 Hour)'}]; #edit
>>>>>>> 3cf4384bed905fccf42e06bf9b6b94b8da0dc545
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $time = ParseTime($oWkC->Value);

      # date - column 'Programme Title'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;

      # date - column 'Synopsis'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Synopsis'}];
      next if( ! $oWkC );
      my $synopsis = $oWkC->Value;

      progress("VH1_xls FLAT: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => $title,
      };

      $ce->{description} = $synopsis if $synopsis;

      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next sheet

  $dsh->EndBatch( 1 );

  return;
}

sub ImportGridXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  $self->{fileerror} = 0;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my( $oBook, $oWkS, $oWkC );

  # Only process .xls files.
  return if $file !~  /\.xls$/i;
  progress( "VH1_xls GRID: $xmltvid: Processing $file" );
  
  my $currdate = "x";

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "VH1_xls GRID: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    # check if there is data in the sheet
    # sometimes there are some hidden empty sheets
    next if( ! $oWkS->{MaxRow} );
    next if( ! $oWkS->{MaxCol} );

    # Each column contains data for one day
    # starting with column 1 for monday to column 7 for sunday
    for(my $iC = 1; $iC <= 7 ; $iC++) {

      # DAYNAME is in the 3th row
      $oWkC = $oWkS->{Cells}[2][$iC];
      next if( ! $oWkC );
      my $dayname = $oWkC->Value;
      next if ( ! $dayname );

      # DATE is in the 4th row
      $oWkC = $oWkS->{Cells}[3][$iC];
      next if( ! $oWkC );
      my $dateinfo = $oWkC->Value; #print "dateinfo: $dateinfo\n";
      next if ( ! $dateinfo );
      next if( $dateinfo !~ /^\d+-\w+-\d+$/ and $dateinfo !~ /^\d+\/\w+\/\d+$/ );

      my $date = ParseDate( $dateinfo );

      progress("VH1_xls GRID: $xmltvid: Date is: $date");

      if( $date ne $currdate ){

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;
      }

      # merged_area: [ $start_row, $start_col, $end_row, $end_col]
      my $merged_areas = $oWkS->get_merged_areas();#print "merged: $merged_areas->[0][1],$merged_areas->[0][3], $merged_areas->[0][2] \n";
      my @merged_areas = grep { $_->[3] - $_->[1] > 0 and $_->[0] > 4 } @$merged_areas; # remove single column merged areas

      # programmes start from row 6
      for(my $iR = 5 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        #print "iR: $iR\n";
        # Time Slot
        $oWkC = $oWkS->{Cells}[$iR][0];
        next if( ! $oWkC );
        my $timeinfo = $oWkC->Value;
        next if ( ! $timeinfo );
        next if( $timeinfo !~ /\d\d\d\d/ );
        my $time = ParseTime( $timeinfo );

        # Title
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        #next if( ! $oWkC );
        my $title = $oWkC->Value;
        if( ! $title ) {          # if empty, check if in merged_areas
          foreach (@merged_areas){
            if ( $_->[0]=$iR and $iR<=$_->[2] and $_->[1]<=$iC and $iC<=$_->[3] ) {
              $title = $oWkS->{Cells}[$_->[0]][$_->[1]]->Value;  # from main column
              #print "$iR, $iC pripada: $_->[0],$_->[1],$_->[2],$_->[3]  $title \n" ;
              $iR = $_->[2] ;
              last;
              }
            }
          }
        next if ( ! $title );
        next if( $title !~ /\S+/ );

        # from a valid cell with the 'title'
        # the following cells up to the next row that has valid 'time'
        # the cells might contain subtitle
        my $subtitle = undef;
        for( my $r = $iR + 1 ; defined $oWkS->{MaxRow} && $r <= $oWkS->{MaxRow} ; $r++ ){

          next if( ! $oWkS->{Cells}[$r][0] );
          next if( ! $oWkS->{Cells}[$r][$iC] );

          last if( $oWkS->{Cells}[$r][0]->Value );

          if( ! $oWkS->{Cells}[$r][0]->Value and $oWkS->{Cells}[$r][$iC]->Value ){
            $subtitle .= $oWkS->{Cells}[$r][$iC]->Value;
          }
        }

        progress("VH1_xls GRID: $xmltvid: $time - $title");

        my $ce = {
          channel_id   => $channel_id,
          start_time   => $time,
          title        => $title,
        };

        $ce->{subtitle} = $subtitle if $subtitle;

        $dsh->AddProgramme( $ce );

      } # next row (next show)

    } # next column (next day)

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}


sub ParseTime
{
  my ( $tinfo ) = @_;

  my( $hour, $minute ); 
  #print "ParseTime: >$tinfo< \n";
  if( $tinfo =~ /^\d{1,2}\:\d{1,2}$/ ){ # format '13:01'  
    ( $hour, $minute ) = ( $tinfo =~ /^(\d+)\:(\d+)$/ );
  } elsif( $tinfo =~ /^\d{4}.\d{2}.\d{2}.\d\d\:\d\d$/ ){ # format '2012-01-12 10:00'
    ( $hour, $minute ) = ( $tinfo =~ /^\d{4}.\d{2}.\d{2} (\d+).(\d+)/ );
  } elsif( $tinfo =~ /\d{4}/ ){ # format '1030'
    ( $hour, $minute ) = ( $tinfo =~ /(\d{2})(\d{2})/ );
  } elsif( $tinfo eq 0 or $tinfo =~ /^0\.\d/ ){ # format '0.58'
     return ExcelFmt('hh:mm', $tinfo);
  }

#  return undef if( ! $hour );

  return sprintf( "%02d:%02d", $hour, $minute );
}


sub ParseDate
{ 
  my ( $dinfo ) = @_;

<<<<<<< HEAD
  my( $m, $d, $y );

  if( $dinfo =~ /^\d{2}-\d{2}-\d{4}$/ ){ # mm-dd-yyyy
    ( $d, $m, $y ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d+\/\d+\/\d+$/ ){ # dd/mm/yy
    ( $d, $m, $y ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  } else {
    return undef;
=======
  my( $month, $day, $year );
  #print "ParseDate: >$dinfo< \n";
  if( $dinfo =~ /^\d{2}-\d{2}-\d{4}$/ ){ # format '13-01-2012'  
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{8}$/ ){ # format '20130801'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d\d\d\d)(\d\d)(\d\d)$/ );
  }  elsif( $dinfo =~ /^\d{2}\/\d{2}\/\d{2}$/ ){ # format '21/01/12'
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)$/ );
  } elsif( $dinfo =~ /^\d{4}.\d{2}.\d{2}.\d\d\:\d\d$/ ){ # format '2012-01-12 10:00'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)/ );
  } elsif( $dinfo =~ /^\d{2}.\d{1,2}.\d{2}$/ ){ # format '10-1-13'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)/ );
  } elsif( $dinfo =~ /^\d{1,2}.\w{3}.\d{2}$/ ){ # format '9-Nov-13'
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+)-(\w+)-(\d+)/ ); $month = MonthNumber( $month, 'en' ) ; 
>>>>>>> 3cf4384bed905fccf42e06bf9b6b94b8da0dc545
  }


  return undef if( ! $year );

  $year += 2000 if $year < 100;


  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}





1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
