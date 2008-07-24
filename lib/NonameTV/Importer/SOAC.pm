package NonameTV::Importer::SOAC;

use strict;
use warnings;

=pod

channel: Smile of a child

Import data from Excel-files delivered via e-mail.
Each file is for one week.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;
use NonameTV qw/AddCategory norm MonthNumber/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "SOAC";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
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

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $xmltvid );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my( $dateinfo );
  my( $kada, $newtime, $lasttime );
  my( $title, $newtitle , $lasttitle , $newdescription , $lastdescription );
  my( $day, $month , $year , $hour , $min );
  my( $oBook, $oWkS, $oWkC );

  # Only process .xls files.
  return if $file !~  /\.xls$/i;

  my $batch_id;
  my $currdate = "x";
  my $timecol = 0;

  progress( "SOAC: $xmltvid:  Processing $file" );
  
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    # process only the sheet with the name PPxle
    #next if ( $oWkS->{Name} !~ /PPxle/ );

    progress( "SOAC: $xmltvid:  Processing worksheet: $oWkS->{Name}" );

    # browse through columns
    for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

      # browse through columns
      for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        # time column is #0
        # columns with shows are from 1 to 7
        next if( $iC lt 1 );
        next if( $iC gt 7 );

        # read the cell
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if ( ! $oWkC );

        if( isDate( $oWkC->Value ) ){

          my $date = ParseDate( $oWkC->Value );

          if( $date ne $currdate ) {
            if( $currdate ne "x" ) {
              $dsh->EndBatch( 1 );
            }

            my $batch_id = $xmltvid . "_" . $date;
            $dsh->StartBatch( $batch_id , $channel_id );
            $dsh->StartDate( $date , "06:00" );
            $currdate = $date;

            progress("SOAC: $xmltvid: Date is $date");
          }

          next;
        }

        # this is the cell with some text
        my $text = $oWkC->Value;
        if( $text ){

          # read the time from first column on the left
          $oWkC = $oWkS->{Cells}[$iR][$timecol];
          next if ( ! $oWkC );
          next if ( ! isTime( $oWkC->Value ) );
          my $time = ParseTime( $oWkC->Value );
          next if ( ! $time );

          my( $title, $subtitle ) = ParseShow( $text );

          progress( "SOAC: $xmltvid: $iR $iC $time - $title" );

          my $ce = {
            channel_id => $channel_id,
            start_time => $time,
            title => norm($title),
          };

          $ce->{subtitle} = $subtitle if $subtitle;

          $dsh->AddProgramme( $ce );
        }

      } # next row

    } # next column

    $ds->EndBatch( 1 );

  } # next worksheet

  return;
}

sub isDate {
  my ( $text ) = @_;

  # format '6-Jul'
  if( $text =~ /^\d+-(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $day, $monthname ) = ( $dinfo =~ /^(\d+)-(\S+)$/ );

  my $year = DateTime->today()->year;

  my $month = MonthNumber( $monthname , "en" );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isTime {
  my ( $text ) = @_;

  # format '18:30 AM/PM'
  if( $text =~ /^\d+:\d+\s+AM\/PM$/i ){
    return 1;
  }

  return 0;
}

sub ParseTime
{
  my ( $tinfo ) = @_;

  my( $hour, $minute ) = ( $tinfo =~ /^(\d+):(\d+)\s+/ );

  return sprintf( '%02d:%02d', $hour, $minute );
}

sub ParseShow
{
  my ( $text ) = @_;

  $text =~ s/\s+/ /g;

  my( $title, $subtitle);

  if( $text =~ /\(cc\)\s/ ){
    ( $title, $subtitle ) = ( $text =~ /(.*)\(cc\)\s(.*)/ );
  } else {
    $title = $text;
  }

  return( $title, $subtitle );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
