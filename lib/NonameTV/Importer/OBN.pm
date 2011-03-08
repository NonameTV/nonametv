package NonameTV::Importer::OBN;

use strict;
use warnings;

=pod

Channels: OBN (www.obn.ba)

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Encode qw/decode/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory MonthNumber/;
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
  
  return if( $file !~ /\.doc$/i );

  progress( "OBN: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "OBN $xmltvid: $file: Failed to parse" );
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
    error( "OBN $xmltvid: $file: No divs found." ) ;
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

        progress("OBN: $xmltvid: Date is $date");

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

      my( $time, $title, $genre, $epnum, $eptot, $rating ) = ParseShow( $text );
      next if( ! $time );
      next if( ! $title );

      #$title = decode( "iso-8859-2" , $title );

      progress("OBN: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => $title,
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'OBN', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( $epnum and $eptot ){
        $ce->{episode} = sprintf( ". %d/%d .", $epnum-1 , $eptot );
      }

      $ce->{rating} = $rating if $rating;

      $dsh->AddProgramme( $ce );

    } else {
        # skip
    }
  }

  $dsh->EndBatch( 1 );
    
  return;
}

sub isDate {
  my ( $text ) = @_;

#print ">$text<\n";

  # format 'subota, 21.studeni 2009.'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja),\s*\d+\.\s*(januar|veljače|mart|april|maj|juni|juli|august|septembar|oktobar|novembar|decembar)\s*\d+\.$/i ){
    return 1;
  } elsif( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja),\s*\d+\.\s*(januar|veljače|mart|april|maj|juni|juli|august|septembar|oktobar|novembar|decembar)$/i ){ # format 'SUBOTA, 21. studeni'
    return 1;
  } elsif( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja),\s*\d+\.\d+\.\d+\.$/i ){ # SUBOTA, 26.02.2011.
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

#print ">$text<\n";

  my( $dayname, $day, $monthname, $month, $year );

  # format 'subota, 21.studeni 2009.'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja),\s*\d+\.\s*(januar|veljače|mart|april|maj|juni|juli|august|septembar|oktobar|novembar|decembar)\s*\d+\.$/i ){
    ( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+),\s*(\d+)\.\s*(\S+)\s*(\d+)\.$/i );
    $month = MonthNumber( $monthname , 'hr' );
  } elsif( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja),\s*\d+\.\s*(januar|veljače|mart|april|maj|juni|juli|august|septembar|oktobar|novembar|decembar)$/i ){ # format 'SUBOTA, 21. studeni'
    ( $dayname, $day, $monthname ) = ( $text =~ /^(\S+),\s*(\d+)\.\s*(\S+)$/i );
    $year = DateTime->today->year();
    $month = MonthNumber( $monthname , 'hr' );
  } elsif( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja),\s*\d+\.\d+\.\d+\.$/i ){ # SUBOTA, 26.02.2011.
    ( $dayname, $day, $month, $year ) = ( $text =~ /^(\S+),\s*(\d+)\.(\d+)\.(\d+)\.$/i ); # SUBOTA, 26.02.2011.
  }


  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

#print ">$text<\n";

  # format '09:00 Nasljednici zemlje, 4/8'
  if( $text =~ /^\d+[:|.]\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

#print ">$text<\n";

  my( $hour, $min, $time, $title, $genre, $epnum, $eptot, $rating );

  ( $hour, $min, $title ) = ( $text =~ /^(\d+)[:|.](\d+)\s+(.*)$/ );
  $time = $hour . ":" . $min;

  # parse episode
  # format '22:00 - Pepper Dennis, 5/13'
  if( $title =~ /,\s*\d+\/\d+$/ ){
    ( $epnum, $eptot ) = ( $title =~ /,\s*(\d+)\/(\d+)$/ );
    $title =~ s/,\s*\d+\/\d+$//;
  }

  # parse rating
  # format '02:45 - Tequila (18)'
  if( $title =~ /\s+\(\d+\)$/ ){
    ( $rating ) = ( $title =~ /\s+\((\d+)\)$/ );
    $title =~ s/\s+\(\d+\)$//;
  }

  return( $time, $title, $genre, $epnum, $eptot, $rating );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
