package NonameTV::Importer::CMC;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

use constant {
  N_TITLE => 1,
  N_DESCRIPTION => 2,
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

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "CMC: $xmltvid: Processing $file" );

  my $date;
  my $currdate = "x";

  # the time is in the 1st column
  my $coltime = 0;


  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "CMC: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through columns
    # the schedules information
    # is in columns 1-7
    for(my $iC = 1 ; $iC <= 7 ; $iC++) {

      # the date information
      # is in the 1st row
      my $oWkC = $oWkS->{Cells}[0][$iC];
      next if( ! $oWkC );
      my $dateinfo = $oWkC->Value;

      $date = ParseDate( $dateinfo );
      if( $date ) {

        progress( "CMC: $chd->{xmltvid}: Date is $date" );

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

      my $nexttarget = N_TITLE;
      my $title;
      my $description;

      # browse through rows
      # start at row 1
      for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        my $text = $oWkC->Value;
        next if( ! $text );
#print ">$iC $iR $text<\n";

        # if the top border is visible -> this is title
        # else this is description
        my $topCol = $oWkC->{Format}->{BdrColor}[2];
#print "TOP $topCol\n";
        if( $topCol ){
          $nexttarget = N_TITLE;
        }

        if( $nexttarget eq N_TITLE ){
          $title = $text;
          $description = undef;
          $nexttarget = N_DESCRIPTION;
        } elsif ( $nexttarget eq N_DESCRIPTION ){
          $description .= $text
        } else {
          next;
        }

#print "TITL $title\n";
#print "DESC $description\n" if $description;

        # if we have title
        # read the time
        if( $title ){

          $oWkC = $oWkS->{Cells}[$iR][$coltime];
          next if( ! $oWkC );
          my $time = ParseTime( $oWkC->Value );
          next if( ! $time );

          progress( "CMC: $chd->{xmltvid}: $time - $title" );

          # save the last cell
          my $ce = {
            channel_id => $channel_id,
            start_time => $time,
            title => $title,
          };

          $dsh->AddProgramme( $ce );

          $title = undef;
        }

        # if the bottom border is visible -> this is title
        # else this is description
        my $botCol = $oWkC->{Format}->{BdrColor}[3];
#print "BOTTOM $botCol\n";
        if( $botCol ){
          $nexttarget = N_TITLE;
        }

      } # next row

      $date = undef;

    } # next column





  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $text ) = @_;

  my( $dayname, $day, $month );

  # format 'Ètvrtak, 23.10.'

  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja),\s*\d+\.\s*\d+\.*$/i ){
    ( $dayname, $day, $month ) = ( $text =~ /^(\S+),\s*(\d+)\.\s*(\d+)\.*$/ );
  } else {
    return undef;
  }

  return undef if( ! $day );

  my $year = DateTime->today->year();

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

sub ParseTime
{
  my ( $text ) = @_;

  my( $hour, $min ) = ( $text =~ /(\d+):(\d+)/ );

  return undef if( ! $hour or ! $min );

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
