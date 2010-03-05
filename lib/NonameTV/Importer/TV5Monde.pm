package NonameTV::Importer::TV5Monde;

#use strict;
#use warnings;

=pod

Import data from xls files delivered via e-mail.  Each
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


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Paris" );
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

  my $date;
  my $currdate = "x";

  progress( "TV5Monde: $channel_xmltvid: Processing $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "TV5Monde: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("TV5Monde: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Date or Time is stored in the column 0
      $oWkC = $oWkS->{Cells}[$iR][0];
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
          $dsh->StartDate( $date , "04:00" );
          $currdate = $date;

          progress("TV5Monde: $channel_xmltvid: Date is: $date");
        }

        next;
      }

      if( isTime( $oWkC->Value ) ){

        my $time = $oWkC->Value;

        if( not defined( $time ) ) {
          error( "Invalid start-time '$date' '$time'. Skipping." );
          next;
        }

        # Title - stored in column 1
        $oWkC = $oWkS->{Cells}[$iR][1];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );

        my $showinfo;
        # don't die on wrong encoding
        eval{ $showinfo = decode( "iso-8859-1", $oWkC->Value ); };
        if( $@ ne "" ){
          error( "Failed to decode $@" );
        }

        my( $title, $subtitle, $genre, $episode ) = ParseShow( $showinfo );

        progress( "TV5Monde: $channel_xmltvid: $time - $title" );

        my $ce = {
          channel_id => $channel_id,
          title => norm($title),
          start_time => $time,
        };

        $ce->{subtitle} = norm($subtitle) if $subtitle;

        if( $genre ){
          my($program_type, $category ) = $ds->LookupCat( "TV5Monde", norm($genre) );
          AddCategory( $ce, $program_type, $category );
        }

        if( $episode ){
          $ce->{episode} = sprintf( ". %d .", norm($episode)-1 );
        }

        $dsh->AddProgramme( $ce );
      }

    } # next row

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate
{
  my ( $text ) = @_;

#print ">$text<\n";

  # the format is 'Samedi 1er novembre 2008'
  if( $text =~ /^(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\s+\d+\S*\s+(janvier|Février|mars|avril|mai|juin|juillet|aout|septembre|octobre|novembre|décembre)\s+\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  # the format is 'Samedi 1er novembre 2008'
  my( $dayname, $day, $monthname, $year ) = ( $dinfo =~ /^(\S+)\s+(\d+)\S*\s+(\S+)\s+(\d+)$/i );
  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $month = MonthNumber( $monthname, 'fr' );

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub isTime
{
  my ( $text ) = @_;

  # the format is '12:05 or 3:45'
  if( $text =~ /^\d+:\d+$/ ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $showinfo ) = @_;

  my( $title, $subtitle, $genre, $episode );

  my @lines = split( /\n/, $showinfo);
  my $numlines = scalar(@lines);

  # extract genre
  if( $lines[0] =~ /\// ){
    ( $title, $genre ) = ( $lines[0] =~ /^(.*)\/(.*)$/ );
  } else {
    $title = $lines[0];
  }

  # the episode and subtitle might be in the 2nd line
  if( $numlines eq 2 ){

    # extract episode
    if( $lines[1] =~ /^Episode\s+\d+/ ){
      ( $episode ) = ( $lines[1] =~ /^Episode\s+(\d+)/ );
    }

    # extract subtitle
#    if( $lines[1] =~ /:/ ){
#      ( $subtitle ) = ( $lines[1] =~ /:(.*)$/ );
#    }

  }

  return( $title, $subtitle, $genre, $episode );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
