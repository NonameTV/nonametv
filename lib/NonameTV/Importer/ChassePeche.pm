package NonameTV::Importer::ChassePeche;

use strict;
use warnings;

=pod

Channels: Chasse et Peche (www.chasseetpechetv.fr)

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

  progress( "ChassePeche: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "ChassePeche $xmltvid: $file: Failed to parse" );
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
    error( "ChassePeche $xmltvid: $file: No divs found." ) ;
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

        progress("ChassePeche: $xmltvid: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            FlushDayData( $xmltvid, $dsh , @ces );
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "07:00" ); 
          $currdate = $date;
        }
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isShow( $text ) ) {

      my( $time, $title, $subtitle, $genre ) = ParseShow( $text );
      #$title = decode( "iso-8859-2" , $title );

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      $ce->{subtitle} = $subtitle if $subtitle;

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'ChassePeche', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      # add the programme to the array
      # as we have to add description later
      push( @ces , $ce );

    } else {

        # the last element is the one to which
        # this description belongs to
        my $element = $ces[$#ces];

        $element->{description} .= $text;

    }
  }

  # save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
    
  return;
}

sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("ChassePeche: $xmltvid: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

sub isDate {
  my ( $text ) = @_;

print ">$text<\n";

  # format 'jeudi 2 Avril 2009', 'mercredi 1er Avril 2009'
  if( $text =~ /^(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\s+\d+(er)*\s+(Avril|Mai|Juin|Juillet|Août)\s+\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  # format 'jeudi 2 Avril 2009', 'mercredi 1er Avril 2009'
  my( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+)\s+(\d+)\S*\s+(\S+)\s+(\d+)$/ );
#print "$dayname\n";
#print "$day\n";
#print "$monthname\n";
#print "$year\n";

  my $month = MonthNumber( $monthname , 'fr' );
#print "$month\n";

  return sprintf( '%04d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '20:50 Gibier de France : Chevreuil (Nature, animaux)'
  if( $text =~ /^\d+:\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title, $subtitle, $genre );

  if( $text =~ /\(.*\)\s*\(.*\)$/ ){ # format: '16:30 Le cerf des PyrA©nA©es (1A¨re partie) (Nature, animaux)'
    ( $hour, $min, $title, $subtitle, $genre ) = ( $text =~ /^(\d+):(\d+)\s+(.*)\s*\((.*)\)\s*\((.*)\)$/ );
  } elsif( $text =~ /\(.*\)$/ ){
    ( $hour, $min, $title, $subtitle, $genre ) = ( $text =~ /^(\d+):(\d+)\s+(.*)\s*:\s*(.*)\s*\((.*)\)$/ );
  }

  return( $hour . ":" . $min , $title , $subtitle , $genre );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
