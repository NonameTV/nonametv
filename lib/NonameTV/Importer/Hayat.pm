package NonameTV::Importer::Hayat;

use strict;
use warnings;

=pod

Import data from Hayat

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use XML::LibXML;

use NonameTV qw/norm Wordfile2Xml Htmlfile2Xml AddCategory MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Zagreb" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.doc$/i ){
    $self->ImportDOC( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportFlatXLS( $file, $chd );
  } else {
    error( "Hayat: Unknown file format: $file" );
  }

  return;
}

sub ImportDOC
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  return if( $file !~ /\.doc$/i );

  progress( "Hayat: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "Hayat $xmltvid: $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( '//span[@style="text-transform:uppercase"]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 ) {
    error( "Hayat $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

#print ">$text<\n";

    if( isDate( $text ) ) { # the line with the date in format 'Friday 1st August 2008'

      $date = ParseDate( $text );
      if( $date ) {

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
          progress("Hayat: $xmltvid: Date is $date");

        }
      }
      next;
    }

    my( $time, $title, $genre, $episode );

    if( isShow( $text ) ){
      ( $time, $title, $genre, $episode ) = ParseShow( $text );
    }

    next if( ! $time );
    next if( ! $title );

    progress("Hayat: $xmltvid: $time - $title");

    my $ce = {
      channel_id => $chd->{id},
      start_time => $time,
      title => norm($title),
    };

    if( $genre ){
      my($program_type, $category ) = $ds->LookupCat( 'Hayat', $genre );
      AddCategory( $ce, $program_type, $category );
    }

    if( $episode ){
      $ce->{episode} = sprintf( ". %d .", $episode-1 );
    }

    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );
    
  return;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();

  my $coldate = 0;
  my $coltime = 0;
  my $coltitle = 1;

  my $date;
  my $currdate = "x";

  progress( "Hayat FlatXLS: $chd->{xmltvid}: Processing flat XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "Hayat FlatXLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("Hayat FlatXLS: $chd->{xmltvid}: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$coldate];
      if( $oWkC and $oWkC->Value ){

        if( isDate( $oWkC->Value ) ){
          $date = ParseDate( $oWkC->Value );
        }

        if( $date ne $currdate ) {
          if( $currdate ne "x" ) {
	    $dsh->EndBatch( 1 );
          }

          my $batch_id = $chd->{xmltvid} . "_" . $date;
          $dsh->StartBatch( $batch_id , $chd->{id} );
          $dsh->StartDate( $date , "06:00" );
          $currdate = $date;

          progress("Hayat FlatXLS: $chd->{xmltvid}: Date is: $date");
        }
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;
      $time =~ s/\s//;
      next if( $time !~ /^\d+:\d+$/ );

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;

      progress( "Hayat FlatXLS: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my ( $text ) = @_;

#print ">$text<\n";

  # format 'PROGRAMSKA SHEMA ZA PETAK, 24.09.2010.'
  if( $text =~ /^PROGRAMSKA SHEMA ZA.*\d{2}\.\d{2}\.\d{4}\.$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my ( $text ) = @_;

#print ">$text<\n";

  my( $year, $day, $month );

  # format '01.09.10'
  if( $text =~ /^PROGRAMSKA SHEMA ZA.*\d{2}\.\d{2}\.\d{4}\.$/i ){
    ( $day, $month, $year ) = ( $text =~ /^PROGRAMSKA SHEMA ZA.*(\d{2})\.(\d{2})\.(\d{4})\.$/i );
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

#print ">$text<\n";

  # format '12:00 Indija, igrana serija, 51. epizoda'
  if( $text =~ /^\d{2}:\d{2} \S+.*$/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my ( $text ) = @_;

print ">$text<\n";

  my( $time, $title, $genre, $episode );

  # format '12:00 Indija, igrana serija, 51. epizoda'
  if( $text =~ /^\d{2}:\d{2} \S+.*$/i ){
    ( $time, $title ) = ( $text =~ /^(\d{2}:\d{2}) (\S+.*)$/i );
  }

  $time =~ s/\s//;

  return( $time, $title, undef, undef );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
