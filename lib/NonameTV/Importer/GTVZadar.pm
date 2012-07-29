package NonameTV::Importer::GTVZadar;

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

  progress( "GTVZadar: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "GTVZadar $xmltvid: $file: Failed to parse" );
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
    error( "GTVZadar $xmltvid: $file: No divs found." ) ;
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
          progress("GTVZadar: $xmltvid: Date is $date");

        }
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isShow( $text ) ) {

      my( $time, $title, $genre, $episode ) = ParseShow( $text );
      #$title = decode( "iso-8859-2" , $title );

      progress("GTVZadar: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'GTVZadar', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( $episode ){
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
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

  # format 'PETAK: 11. srpnja 2008.god.'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja):\s*\d+\.\s*(siječnja|veljače|ozujka|travnja|svibnja|lipnja|srpnja|kolovoza|rujna|listopada|studenog\a*|prosinca)\s*\d+\.\s*god\.$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

print ">$text<\n";
  my( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+):\s*(\d+)\.\s*(\S+)\s*(\d+)\.\s*god\.$/ );

  my $month = MonthNumber( $monthname , 'hr' );

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

  my( $hour, $min, $title, $genre, $episode );

  if( $text =~ /\(\d+\)/ ){
    ( $episode ) = ( $text =~ /\((\d+)\)/ );
    $text =~ s/\(\d+\).*//;
  }

  if( $text =~ /\,.*/ ){
    ( $genre ) = ( $text =~ /\,\s*(.*)$/ );
    $text =~ s/\,.*//;
  }

  ( $hour, $min, $title ) = ( $text =~ /^(\d+)\.(\d+)\s+(.*)$/ );

  return( $hour . ":" . $min , $title , $genre , $episode );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
