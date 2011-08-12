package NonameTV::Importer::Turner_doc;

use strict;
use warnings;

=pod

Channels: Cartoon Network, Boomerang, TCM, CNN

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Encode qw/decode/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm MonthNumber/;
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

  progress( "Turner_doc: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "Turner_doc - $xmltvid: $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( '//span[@style="text-transform:uppercase"]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//p" );
  
  if( $ns->size() == 0 ) {
    error( "Turner_doc - $xmltvid: $file: No ps found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    if( isDate( $text ) ) { # the line with the date in format 'Måndag 11 Juli'

      $date = ParseDate( $text );

      if( $date ) {

        progress("Turner_doc: $xmltvid: Date is $date");

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
      next if( ! $time );
      next if( ! $title );

      progress("Turner_doc: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => $title,
      };

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


  if( $text =~ /^(M.ndag|Tisdag|Onsdag|Torsdag|Fredag|L.rdag|S.ndag)\s+\d+(st|nd|rd|th)\s+(Januari|Februari|Mars|April|Maj|Juni|Juli|Augusti|September|November|December)\s+(\d+)$/i ){ # format 'Måndag 11st Juli'
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $monthname, $month, $year, $dummy );

  if( $text =~ /^(M.ndag|Tisdag|Onsdag|Torsdag|Fredag|L.rdag|S.ndag)\s+\d+(st|nd|rd|th)\s+(Januari|Februari|Mars|April|Maj|Juni|Juli|Augusti|September|November|December)\s+(\d+)$/i ){ # format 'Måndag 11 Juli'
    ( $dayname, $day, $dummy, $monthname, $year ) = ( $text =~ /^(\S+)\s+(\d+)(st|nd|rd|th)\s+(\S+)\s+(\d+)$/i );

    $month = MonthNumber( $monthname, 'sv' );
  }

  my $dt = DateTime->new(
  				year => $year,
    			month => $month,
    			day => $day,
      		);

  return $dt->ymd("-");
}

sub isShow {
  my ( $text ) = @_;

  if( $text =~ /^CET\s+\d+\.\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $time, $title, $genre, $desc, $rating );

  ( $time, $title ) = ( $text =~ /^CET\s+(\d+\.\d+)\s+(.*)$/ );

  my ( $hour , $min ) = ( $time =~ /^(\d+).(\d+)$/ );
  
  $time = sprintf( "%02d:%02d", $hour, $min );

  return( $time, $title );
}

1;