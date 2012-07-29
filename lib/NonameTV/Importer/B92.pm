package NonameTV::Importer::B92;

use strict;
use warnings;

=pod

Channels: B92 (www.b92.net)

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

  progress( "B92: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "B92 $xmltvid: $file: Failed to parse" );
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
    error( "B92 $xmltvid: $file: No divs found." ) ;
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

        progress("B92: $xmltvid: Date is $date");

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

      my( $time, $title, $epnum, $eptot ) = ParseShow( $text );
      next if( ! $time );
      next if( ! $title );

      #$title = decode( "iso-8859-2" , $title );

      progress("B92: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => $title,
      };

      if( $epnum and $eptot ){
        $ce->{episode} = sprintf( ". %d/%d .", $epnum-1 , $eptot );
      }

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

  # format 'PONEDELJAK 30.11.2009.'
  if( $text =~ /^(ponedeljak|utorak|sreda|ČETVRTAK|petak|subota|nedelja)\s+\d+\.\d+\.\d+\.$/i ){
    return 1;
  } elsif( $text =~ /^(ponedeljak|utorak|sreda|ČETVRTAK|petak|subota|nedelja)\s+\d+\.(I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII)\s+\d+\.\s+.*$/i ){ # format 'Petak 4.XII 2009. INFO KANAL'
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

#print ">$text<\n";

  my( $dayname, $day, $monthname, $month, $year );

  # format 'PONEDELJAK 30.11.2009.'
  if( $text =~ /^(ponedeljak|utorak|sreda|ČETVRTAK|petak|subota|nedelja)\s+\d+\.\d+\.\d+\.$/i ){
    ( $dayname, $day, $month, $year ) = ( $text =~ /^(\S+)\s+(\d+)\.(\d+)\.(\d+)\.$/ );
  } elsif( $text =~ /^(ponedeljak|utorak|sreda|ČETVRTAK|petak|subota|nedelja)\s+\d+\.(I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII)\s+\d+\.\s+.*$/i ){ # format 'Petak 4.XII 2009. INFO KANAL'
    ( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+)\s+(\d+)\.(\S+)\s+(\d+)\.\s+.*$/i );

    $month = 1 if ( $monthname =~ /^I$/ );
    $month = 2 if ( $monthname =~ /^II$/ );
    $month = 3 if ( $monthname =~ /^III$/ );
    $month = 4 if ( $monthname =~ /^IV$/ );
    $month = 5 if ( $monthname =~ /^V$/ );
    $month = 6 if ( $monthname =~ /^VI$/ );
    $month = 7 if ( $monthname =~ /^VII$/ );
    $month = 8 if ( $monthname =~ /^VIII$/ );
    $month = 9 if ( $monthname =~ /^IX$/ );
    $month = 10 if ( $monthname =~ /^X$/ );
    $month = 11 if ( $monthname =~ /^XI$/ );
    $month = 12 if ( $monthname =~ /^XII$/ );
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '14:00 Film: Longinovo koplje 2/3'
  if( $text =~ /^\d+\:\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $time, $title, $genre, $epnum, $eptot, $rating );

  ( $time, $title ) = ( $text =~ /^(\d+\:\d+)\s+(.*)$/ );

  # parse episode
  # format '14:00 Film: Longinovo koplje 2/3'
  if( $title =~ /\s*\d+\/\d+$/ ){
    ( $epnum, $eptot ) = ( $title =~ /\s*(\d+)\/(\d+)$/ );
    $title =~ s/\s*\d+\/\d+$//;
  }

  return( $time, $title, $epnum, $eptot );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
