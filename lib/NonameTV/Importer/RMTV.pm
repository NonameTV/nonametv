package NonameTV::Importer::RMTV;

use strict;
use warnings;

=pod

Import data from Xls files delivered via e-mail.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use Encode qw/encode decode/;
use Spreadsheet::ParseExcel;
use Archive::Zip;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/London" );
  $self->{datastorehelper} = $dsh;

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

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $channel_xmltvid );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $dayoff = 0;
  my $year = DateTime->today->year();

  my $date;
  my $currdate = "x";

  progress( "RMTV: $channel_xmltvid: Processing XLS $file" );

#return if( $file !~ /28-03 Abril\.xls/ );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "RMTV: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("RMTV: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      my $oWkC;

      # check the 1st and 2nd column for the date
      for( my $iC = 0 ; $iC <= 1 ; $iC++ ){

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );

        if( isDate( $oWkC->Value ) ){

          $date = ParseDate( $oWkC->Value );

          if( $date ne $currdate ) {
            if( $currdate ne "x" ) {
              $dsh->EndBatch( 1 );
            }

            my $batch_id = $channel_xmltvid . "_" . $date;
            $dsh->StartBatch( $batch_id , $channel_id );
            $dsh->StartDate( $date , "00:00" );
            $currdate = $date;

            progress("RMTV: $channel_xmltvid: Date is: $date");
          }
        }
      }

      # check the 2nd column for the time
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;

      my( $hour, $min );
      if( $time =~ /^\d{2}:\d{2}$/ ){
        ( $hour, $min ) = ( $time =~ /^(\d{2}):(\d{2})$/ );
      } elsif( $time =~ /^\d{2}:\d{2}:\d{2}$/ ){
        ( $hour, $min ) = ( $time =~ /^(\d{2}):(\d{2}):\d{2}$/ );
      } else {
        next;
      }

      if( $hour gt 23 ){
        $hour -= 24;
        $time = sprintf( "%02d:%02d", $hour, $min );
      }

      # check the 5rd column for the title
      $oWkC = $oWkS->{Cells}[$iR][4];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;

      # check the 6th column for the description
      $oWkC = $oWkS->{Cells}[$iR][5];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $description = $oWkC->Value;

      # check the 7th column for the duration
      $oWkC = $oWkS->{Cells}[$iR][6];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $duration = $oWkC->Value;

      # check the 8th column for the reference
      $oWkC = $oWkS->{Cells}[$iR][7];
      my $ref = $oWkC->Value if $oWkC->Value;

      progress( "RMTV: $channel_xmltvid: $time - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $time,
      };

      $ce->{description} = $description if $description;
    
      $dsh->AddProgramme( $ce );

    } # next row

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my( $text ) = @_;

#print "isDate: $text\n";

  # the format is 'Saturday, 29th November 2008'
  # or 'Saturday, 11th Abril 2009'
  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\,*\s*\d+(st|nd|rd|th)\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+$/i ){
    return 1;
  }

  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\,*\s*\d+(st|nd|rd|th)\s+(january|february|marzo|abril|may|june|july|august|september|october|november|december)\s+\d+$/i ){
    return 1;
  }

  return 0;
}


sub ParseDate {
  my( $text ) = @_;

  # the format is 'Saturday, 29th November 2008'
  # or 'Saturday, 11th Abril 2009'
  my( $dayname, $day, $sufix, $monthname, $year ) = ( $text =~ /^(\S+)\,*\s*(\d+)(st|nd|rd|th)\s+(\S+)\s+(\d+)$/ );
#print "DN $dayname\n";
#print "DY $day\n";
#print "MN $monthname\n";
#print "YR $year\n";

  $dayname =~ s/\,//;

  $year += 2000 if $year lt 100;

  my $month;

  $month = MonthNumber( $monthname, "en" );
#print "MONTH $month\n";

  $month = 3 if( ! $month and ( $monthname =~ /Marzo/ ) );
  $month = 4 if( ! $month and ( $monthname =~ /Abril/ ) );
#print "MONTH $month\n";

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ExtractDate {
  my( $fn ) = @_;
  my $month;

  # format of the file name could be
  # 'FOX Crime schedule 28 Apr - 04 May CRO.xml'
  # or
  # 'Life Programa 05 - 11 May 08 CRO.xml'

  my( $day , $monthname );

  # format: 'Programa 29 Sept - 05 Oct CRO.xls'
  if( $fn =~ m/.*\s+\d+\s+\S+\s*-\s*\d+\s+\S+.*/ ){
    ( $day , $monthname ) = ($fn =~ m/.*\s+(\d+)\s+(\S+)\s*-\s*\d+\s+\S+.*/ );

  # format: 'Programa 15 - 21 Sep 08 CRO.xls'
  } elsif( $fn =~ m/.*\s+\d+\s*-\s*\d+\s+\S+.*/ ){
    ( $day , $monthname ) = ($fn =~ m/.*\s+(\d+)\s*-\s*\d+\s+(\S+).*/ );
  }

  # try the first format
  ###my( $day , $monthname ) = ($fn =~ m/\s(\d\d)\s(\S+)\s/ );
  
  # try the second if the first failed
  ###if( not defined( $monthname ) or ( $monthname eq '-' ) ) {
    ###( $day , $monthname ) = ($fn =~ m/\s(\d\d)\s\-\s\d\d\s(\S+)\s/ );
  ###}

  if( not defined( $day ) ) {
    return undef;
  }

  $month = MonthNumber( $monthname, 'en' );

  return ($month,$day);
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
