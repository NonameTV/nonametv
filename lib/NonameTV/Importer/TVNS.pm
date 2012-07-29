package NonameTV::Importer::TVNS;

use strict;
use warnings;

=pod

Channels: Gradska TV Zadar

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Encode;

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

  if( ! $chd->{grabber_info} ){
    error( "TVNS: $xmltvid: You must specify the section search pattern (grabber_info)" );
    return;
  }

  return if( $file !~ /\.doc$/i );

#return if( $file !~ /18\.JUL 2009/i );

  progress( "TVNS: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "TVNS $xmltvid: $file: Failed to parse" );
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
    error( "TVNS $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  # States
  use constant {
    ST_START  => 0,
    ST_OKSECT => 1,   # Found header of the day section we want
    ST_OTSECT => 2,   # Found header but of the other day section
    ST_EPILOG => 3,   # After END-marker
  };

  my $state = ST_START;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

print ">$text<\n";

    if( isHeader( $text ) ){ # the header in format 'PRVI PROGRAM RTV ZA 7. OKTOBAR 2008. - UTORAK'
#print "HEADER\n";

      if( $text =~ /$chd->{grabber_info}/i ){
#print "ST_OKSECT\n";

        $state = ST_OKSECT;
        progress("TVNS: $xmltvid: Processing section '$text'");

        $date = ParseDate( $text );

        if( $date ) {

          progress("TVNS: $xmltvid: Date is $date");

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
      } else { # we are in some day section other that we nead
        $state = ST_OTSECT;
        progress("TVNS: $xmltvid: Skipping section '$text'");
      }

      # empty last day array
      undef @ces;
      undef $description;

    }

    next if( $state != ST_OKSECT );

    if( isShow( $text ) ) {

      my( $time, $title ) = ParseShow( $text );

      progress("TVNS: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      $dsh->AddProgramme( $ce );
    }

  }

  $dsh->EndBatch( 1 );
    
  return;
}

sub isHeader {
  my ( $text ) = @_;

  # format 'PRVI PROGRAM RTV ZA 7. OKTOBAR 2008. - UTORAK'
  if( $text =~ /\d+\.\s+(januar|februar|mart|april|maj|jun|jul|juli|avgust|septembar|oktobar|novembar|decembar)\s+\d+/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $day, $monthname, $year ) = ( $text =~ /(\d+)\.\s+(\S+)\s+(\d+)/ );

  my $month = MonthNumber( $monthname , 'sr' );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '21.40 Journal, emisija o modi (18)'
  if( $text =~ /^\d+\.\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my ( $hour, $min, $title ) = ( $text =~ /^(\d+)\.(\d+)\s+(.*)$/ );

  #$title = decode( "iso-8859-5", $title );

  return( $hour . ":" . $min , $title );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
