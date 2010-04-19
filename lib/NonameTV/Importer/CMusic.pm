package NonameTV::Importer::CMusic;

use strict;
use warnings;

=pod

Import data from xls files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Encode qw/encode decode/;
use Spreadsheet::ParseExcel;
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

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "CMusic XLS: $channel_xmltvid: Processing XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "CMusic XLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("CMusic XLS: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
          }
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}
        next;
      }
      
      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
	  $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("CMusic XLS: $channel_xmltvid: Date is: $date");
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'GMT'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Prog Title'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $progtitle = $oWkC->Value;

      # EpTitle
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Ep Title'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $eptitle = $oWkC->Value;

      # Prog Synopsis
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Prog Synopsis'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $progsynopsis = $oWkC->Value;

      # Ep Synopsis
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Ep Synopsis'}];
      next if( ! $oWkC );
      my $epsynopsis = $oWkC->Value;

      # Genre
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Genre'}];
      next if( ! $oWkC );
      my $genre = $oWkC->Value;

      # Rating
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Rating'}];
      next if( ! $oWkC );
      my $rating = $oWkC->Value;

#      # Audio
#      $oWkC = $oWkS->{Cells}[$iR][$columns{'Audio'}];
#      next if( ! $oWkC );
#      my $audio = $oWkC->Value;

      progress( "CMusic XLS: $channel_xmltvid: $time - $eptitle" );

      my $ce = {
        channel_id => $channel_id,
        title => $eptitle || $progtitle,
        subtitle => $progtitle,
        start_time => $time,
      };

      $ce->{description} = $progsynopsis if $progsynopsis;

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'CMusic', $genre );
        AddCategory( $ce, $program_type, $category );
      }
    
      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my( $text ) = @_;

  return undef if not $text;

#print "$text\n";

  my( $month, $day, $year );

  if( $text =~ /^\d{4}-\d{2}-\d{2}$/ ){ # Format '2010-04-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+-\d+-\d+$/ ){ # Format '2-1-09'
    ( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  }

  $year += 2000 if $year < 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime
{
  my( $text ) = @_;

  return undef if not $text;

  my( $hour, $min, $sec );

  # Format '21:00:00'
  if( $text =~ /^\d+:\d+:\d+$/ ){
    ( $hour, $min, $sec ) = ( $text =~ /^(\d+):(\d+):(\d+)$/ );
  }

  # Format '1.1.1900  00:00:00'
  if( $text =~ /^\d+\.\d+\.\d+\s+\d+:\d+:\d+$/ ){
    ( $hour, $min, $sec ) = ( $text =~ /^\d+\.\d+\.\d+\s+(\d+):(\d+):\d+$/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
