package NonameTV::Importer::MTVAdria;

use strict;
use warnings;

=pod

Channels: Slavonska TV Osijek

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use Encode;
use Spreadsheet::ParseExcel;
use DateTime::Format::Excel;


use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory/;
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

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.txt$/i ){
    $self->ImportTXT( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  }

  return;
}

sub ImportTXT
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  return if( $file !~ /\.txt$/i );

  progress( "MTVAdria TXT: $xmltvid: Processing $file" );
  
  open(TXTFILE, $file);
  my @lines = <TXTFILE>;

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $text (@lines){

    $text = decode( "utf8", $text );

    if( isDate( $text ) ) { # the line with the date in format 'Friday 1st August 2008'

      $date = ParseDate( $text );

      if( $date ) {

        progress("MTVAdria TXT: $xmltvid: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
        }
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isShow( $text ) ) {

      my( $time, $title ) = ParseShow( $text );

      # skip on error
      next if not $time;
      next if not $title;

      progress("MTVAdria TXT: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      $dsh->AddProgramme( $ce );

    } else {
        # skip
    }
  }

  $dsh->EndBatch( 1 );

  close(TXTFILE);
    
  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.xls$/i );

  progress( "MTVAdria XLS: $xmltvid: Processing $file" );

  my $coltime = 0;
  my $date;
  my $currdate = "x";

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  if( not defined( $oBook ) ) {
    error( "MTVAdria XLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("MTVAdria XLS: $xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the columns
    for(my $iC = 1 ; $iC <= 7 ; $iC++) {

      for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        my $title;
        my $episode;
        my $time;

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );

        if( isDate( $oWkC->Value ) ){

          $date = ParseDate( $oWkC->Value );

          if( $date ne $currdate ) {

            if( $currdate ne "x" ){
              $dsh->EndBatch( 1 );
            }

            my $batch_id = "${xmltvid}_" . $date;
            $dsh->StartBatch( $batch_id, $channel_id );
            $dsh->StartDate( $date , "06:00" );
            $currdate = $date;

            progress("MTVAdria TXT: $xmltvid: Date is $date");
          }

        } else {

          if( $oWkC->Value =~ /^#\d+$/ ){
            ( $episode ) = ( $oWkC->Value =~ /^#(\d+)$/ );
          } else {
            $title = $oWkC->Value;

            # check the $coltime column
            my $toWkC = $oWkS->{Cells}[$iR][$coltime];
            if( ! $toWkC or ! $toWkC->Value ){
              for(my $tiR = $iR ; $tiR >= 0 ; $tiR--) {
                $toWkC = $oWkS->{Cells}[$tiR][$coltime];
                if( $toWkC and $toWkC->Value ){
                  $time = ParseTime( $toWkC->Value );
                  last;
                }
              }
            } else {
              $time = ParseTime( $toWkC->Value );
            }
          }

        }

        next if( ! $time );
        next if( ! $title );

        progress("MTVAdria XLS: $xmltvid: $time - $title");

        my $ce = {
          channel_id => $chd->{id},
          start_time => $time,
          title => norm($title),
        };

        $dsh->AddProgramme( $ce );

      } # next row

    } # next column
  } # next sheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my ( $text ) = @_;

#print "$text\n";

  # format '2008-06-26 Thursday'
  if( $text =~ /^\s*\d+-\d+-\d+\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*$/i ){
    return 1;

  # format '40081'
  } elsif( $text =~ /^\d{5}$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $year, $month, $day, $dayname );

  if( $text =~ /^\s*\d+-\d+-\d+\s+\S+\s*$/ ){
    ( $year, $month, $day, $dayname ) = ( $text =~ /^\s*(\d+)-(\d+)-(\d+)\s+(\S+)\s*$/ );
    $year += 2000 if $year lt 2000;
  } elsif( $text =~ /^\d{5}$/ ){
    my $dt = DateTime::Format::Excel->parse_datetime( $text );
    $year = $dt->year;
    $month = $dt->month;
    $day = $dt->day;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour, $min );

  if( $text =~ /^\d{4}$/ ){
    ( $hour, $min ) = ( $text =~ /^(\d{2})(\d{2})$/ );
  } else {
    return undef;
  }

  return sprintf( '%02d:%02d', $hour, $min );
}

sub isShow {
  my ( $text ) = @_;

  # format '21.40 Journal, emisija o modi (18)'
  if( $text =~ /^\d+\:\d+\s+.*$/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title );

  ( $hour, $min, $title ) = ( $text =~ /^(\d+)\:(\d+)\s+(.*)$/ );

  my $time = $hour . ":" . $min;
  $time = undef if( $min gt 59 );

  # do some changes
  $title =~ s/®/(R)/;

  return( $time , $title );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
