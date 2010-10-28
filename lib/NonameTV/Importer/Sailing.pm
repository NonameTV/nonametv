package NonameTV::Importer::Sailing;

use strict;
use warnings;

=pod

channel: Sailing

Import data from Excel-files delivered via e-mail.
Each file contains one sheet, one sheet per month.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV qw/AddCategory norm/;

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


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

#return if( $file !~ /palinsesto Aprile 2010/i );

  my $ft = $self->CheckFileFormat( $file, $chd );
print "FT $ft " . %{$self->{columns}} . "\n";
  if( $ft eq FT_FLATXLS ){
    $self->ImportFlatXLS( $file, $chd );
  } elsif( $ft eq FT_GRIDXLS ){
    $self->ImportGridXLS( $file, $chd );
  } else {
    error( "Sailing: $chd->{xmltvid}: Unknown file format of $file" );
    $self->ImportFlatXLS( $file, $chd );
  }

  $self->ImportFlatXLS( $file, $chd );

  return;
}

sub CheckFileFormat
{
  my $self = shift;
  my( $file, $chd ) = @_;

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  return FT_UNKNOWN if( ! $oBook );

  # the flat sheet file which sometimes uses

  progress( "Sailing: $chd->{xmltvid}: Checking file format for $file" );

  my %columns = ();

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "Sailing: $chd->{xmltvid}: Checking worksheet: $oWkS->{Name}" );

    # try to read the columns
    # if column names are present -> flat xls file

    for(my $iR = $oWkS->{MinRow} ; $iR <= 10 ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          my $oWkC = $oWkS->{Cells}[$iR][$iC];
          next if( ! $oWkC );
          next if( ! $oWkC->Value );

          $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

          # columns alternate names
          $columns{'DATE'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Date$/i );
          $columns{'DATE'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Data$/i );

          $columns{'TIME'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Time$/i );
          $columns{'TIME'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Ora$/i );

          $columns{'TITLE'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Name of the episode$/i );
          $columns{'TITLE'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Name of episode$/i );
          $columns{'TITLE'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Codice$/i );

          $columns{'DESCRIPTION'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Description$/i );
          $columns{'DESCRIPTION'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Descrizione$/i );

          $columns{'LENGTH'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Length$/i );
          $columns{'LENGTH'} = $iC if( norm($oWkS->{Cells}[$iR][$iC]->Value) =~ /^Durata$/i );

          if( ! $columns{'DATE'} and isDate( $oWkC->Value ) ){
            $columns{'DATE'} = $iC;
          } elsif( ! $columns{'TIME'} and isTime( $oWkC->Value ) ){
            $columns{'TIME'} = $iC;
          } elsif( defined $columns{'DATE'} and defined $columns{'TIME'} and ! $columns{'TITLE'} ){
            $columns{'TITLE'} = $iC;
          }
        }
      }

      if( defined $columns{'DATE'} and defined $columns{'TIME'} and defined $columns{'TITLE'} ){
        %{$self->{columns}} = %columns;
        return FT_FLATXLS;
      }

      %columns = ();
    } # next row
  }

  return FT_UNKNOWN;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = %{$self->{columns}};
#foreach my $col (%columns) {
#print "$col\n";
#}

  # Only process .xls files.
  return if $file !~  /\.xls$/i;
  progress( "Sailing FlatXLS: $xmltvid: Processing $file" );
  
  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  my $date;
  my $currdate = "x";

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "Sailing: $chd->{xmltvid}: Checking worksheet: $oWkS->{Name}" );

    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # date
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'DATE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ){
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("Sailing FlatXLS: $xmltvid: Date is: $date");
      }

      # time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;
      next if( ! $time );

      # title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TITLE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      # description
      my $description;
      if( defined $columns{'DESCRIPTION'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'DESCRIPTION'}];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        $description = $oWkC->Value;
      }

      progress("Sailing FlatXLS: $xmltvid: $time - $title");

      my $ce = {
        channel_id   => $channel_id,
        start_time   => $time,
        title        => $title,
      };

      if( $description ){

        if( $description =~ /^EP\.\d+$/i ){
          my ( $ep_nr ) = ( $description =~ /^EP\.(\d+)$/i );
          $ce->{episode} = sprintf( ". %d .", $ep_nr-1 );
        }

        $ce->{description} = $description;
      }

      $dsh->AddProgramme( $ce );

    }
  }

  $dsh->EndBatch( 1 );

  return;
}

sub ImportGridXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my( $dateinfo );
  my( $when, $starttime );
  my( $title );
  my( $oBook, $oWkS, $oWkC );

  # Only process .xls files.
  return if $file !~  /\.xls$/i;
  progress( "Sailing GridXLS: $xmltvid: Processing $file" );
  
  my $currdate = "x";

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "Sailing GridXLS: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    # check if there is data in the sheet
    # sometimes there are some hidden empty sheets
    next if( ! $oWkS->{MaxRow} );
    next if( ! $oWkS->{MaxCol} );

    # data layout in the sheet:
    # - all data for one month are in one sheet
    # - every day takes 2 columns - odd column = time, even column = title
    # - 6th row contains day names and dates (in even columns)
    # - schedules start from 7th row

    for(my $iC = 0; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC+=2) {

      # dateinfo (dayname and date) is in the 6th row
      $oWkC = $oWkS->{Cells}[5][$iC];
      if( $oWkC ){
        $dateinfo = $oWkC->Value;
      }
      next if ( ! $dateinfo );

      my $date = ParseDate( $dateinfo );
      next if ( ! $date );

      if( $date ne $currdate ){

        progress("Sailing GridXLS: $xmltvid: Date is: $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # programmes start from row 6
      for(my $iR = 5 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        # Time Slot
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        if( $oWkC ){
          $when = $oWkC->Value;
        }
        # next if when is empty
        next if ( ! $when );
        next if( $when !~ /^\d+:\d+$/ );

        # Title
        $oWkC = $oWkS->{Cells}[$iR][$iC+1];
        if( $oWkC ){
          $title = $oWkC->Value;
        }
        # next if title is empty as it spreads across more cells
        next if ( ! $title );
        next if( $title !~ /\S+/ );

        # create the time
        $starttime = create_dt( $date , $when );

        progress("Sailing GridXLS: $xmltvid: $starttime - $title");

        my $ce = {
          channel_id   => $channel_id,
          start_time   => $starttime->hms(":"),
          title        => $title,
        };

        $dsh->AddProgramme( $ce );

      } # next row (next show)

      $dateinfo = undef;
      $when = undef;
      $title = undef;
    } # next column (next day)

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate
{
  my ( $text ) = @_;

  $text = norm( $text );

  # format '01/10/2010'
  if( $text =~ /^\d{2}\/\d{2}\/\d{4}$/ ){
    return 1;
  }

  return 0;
}

sub isTime
{
  my ( $text ) = @_;

  $text = norm( $text );

  if( $text =~ /^\d{2}:\d{2}$/ ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

#print ">$dinfo<\n";

  my( $dayname, $day, $monthname, $month, $year );

  if( $dinfo =~ /^\d{2}\/\d{2}\/\d{4}$/ ){
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d{2})\/(\d{2})\/(\d{4})$/ );
  } elsif( $dinfo =~ /^\S+,\s+\d+\s+\S+\s+\d+$/ ){
    ( $dayname, $day, $monthname, $year ) = ( $dinfo =~ /(\S+),\s+(\d+)\s+(\S+)\s+(\d+)/ );
    $month = MonthNumber( $monthname, "en" );
  } else {
    return undef;
  }

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}
  
sub create_dt
{
  my ( $dinfo , $tinfo ) = @_;

  my( $year, $month, $day ) = ( $dinfo =~ /(\d+)-(\d+)-(\d+)/ );
  my( $hour, $min ) = ( $tinfo =~ /(\d+):(\d+)/ );

  my $dt = DateTime->new( year   => $year,
                           month  => $month,
                           day    => $day,
                           hour   => $hour,
                           minute => $min,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
                           );

  # times are in CET timezone in original XLS file
  #$dt->set_time_zone( "UTC" );

  return( $dt );
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
