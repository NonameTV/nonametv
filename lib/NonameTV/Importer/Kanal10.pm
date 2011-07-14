package NonameTV::Importer::Kanal10;

use strict;
use warnings;

=pod

Channels: Kanal10 (http://kanal10.se/)

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

  progress( "Kanal10: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "Kanal10 $xmltvid: $file: Failed to parse" );
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
    error( "Kanal10 $xmltvid: $file: No ps found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    if( isDate( $text ) ) { # the line with the date in format 'Måndag 11 juli'

      $date = ParseDate( $text );

      if( $date ) {

        progress("Kanal10: $xmltvid: Date is $date");

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

      my( $time, $title, $desc ) = ParseShow( $text );
      next if( ! $time );
      next if( ! $title );

      #$title = decode( "iso-8859-2" , $title );

      progress("Kanal10: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => $title,
      };

      if( $desc ){
        $ce->{description} = norm($desc);
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

  # format 'Måndag 11 06'
  if( $text =~ /^(M.ndag|Tisdag|Onsdag|Torsdag|Fredag|L.rdag|S.ndag)\s+\d+\s+\d+\$/i ){
    return 1;
  } elsif( $text =~ /^(M.ndag|Tisdag|Onsdag|Torsdag|Fredag|L.rdag|S.ndag)\s+\d+\s+(januari|februari|mars|april|maj|juni|juli|augusti|september|november|december)$/i ){ # format 'Måndag 11 juli'
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $monthname, $month, $year );

  # format 'Måndag 11 06'
  if( $text =~ /^(Måndag|Tisdag|Onsdag|Torsdag|Fredag|Lördag|Söndag)\s+\d+\.\d+\.\d+\.$/i ){
    ( $dayname, $day, $month, $year ) = ( $text =~ /^(\S+)\s+(\d+)\.(\d+)\.(\d+)\.$/ );
  } elsif( $text =~ /^(M.ndag|Tisdag|Onsdag|Torsdag|Fredag|L.rdag|S.ndag)\s+\d+\s+(januari|februari|mars|april|maj|juni|juli|augusti|september|november|december)$/i ){ # format 'Måndag 11 Juli'
    ( $dayname, $day, $monthname ) = ( $text =~ /^(\S+)\s+(\d+)\s+(\S+)$/i );

    $month = MonthNumber( $monthname, 'sv' );
    
    
  }
	
my $dt_now = DateTime->now();


  my $dt = DateTime->new(
  				year => $dt_now->year,
    			month => $month,
    			day => $day,
    			time_zone => "Europe/Stockholm"
      		);
  
  # Add a year if the month is January
  if($month eq 1) {
    	$dt->add( year => 1 );
  }

  #return sprintf( '%d-%02d-%02d', $year, $month, $day );
  return $dt->ymd("-");
}

sub isShow {
  my ( $text ) = @_;

  # format '14.00 Gudstjänst med LArs Larsson - detta är texten'
  if( $text =~ /^\d+\.\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $time, $title, $genre, $desc, $rating );

  ( $time, $title ) = ( $text =~ /^(\d+\.\d+)\s+(.*)$/ );

  # parse description
  # format '14.00 Gudstjänst med LArs Larsson - detta är texten'
  if( $title =~ /\s+-\s+(.*)$/ ){
    ( $desc ) = ( $title =~ /\s+-\s+(.*)$/ );
    $title =~ s/\s+-\s+(.*)$//;
  }

  my ( $hour , $min ) = ( $time =~ /^(\d+).(\d+)$/ );
  
  $time = sprintf( "%02d:%02d", $hour, $min );

  return( $time, $title, $desc );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
