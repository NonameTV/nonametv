package NonameTV::Importer::VH1;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Text::Capitalize qw/capitalize_title/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm/;
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

  progress( "VH1: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  
  my $doc;
  if( $file =~ /\.html$/ ) {
    $doc = Htmlfile2Xml( $file );
  }
  else {
    $doc = Wordfile2Xml( $file );
  }

  if( not defined( $doc ) ) {
    error( "VH1 $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( 
     '//span[@style="text-transform:uppercase"]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 ) {
    error( "VH1 $file: No divs found." ) ;
    return;
  }

  my $currdate = undef;

  foreach my $div ($ns->get_nodelist) {
    my( $text ) = norm( $div->findvalue( '.' ) );

    if( $text eq "" ) {
    }
    elsif( $text =~ /^\S+day \d{1,2}[stndrth]* \S+$/i ) {
      my $date = ParseDate( $text, $file  );
      if( not defined $date ) {
        error( "VH1 $file: Unknown date $text" );
        next;
      }

      $dsh->EndBatch( 1 )
        if defined $currdate;

      my $batch_id = "${xmltvid}_$date";
      $dsh->StartBatch( $batch_id, $channel_id );
      $dsh->StartDate( $date, "05:00" ); 
      $currdate = $date;
    }
    elsif( $text =~ /^\d{4} / ) {
      my( $start, $title, $description ) = ($text =~ 
        /^(\d{4}) ([A-Z0-9\'\&s\/ \-:,()\*]+) ([A-Z].*)/);

      if( not defined( $start ) ) {
	error( "Match failed for '$text'" ); 
      }
      else {
	$start =~ s/(\d\d)(\d\d)/$1:$2/;
	$title = capitalize_title( $title );
	
	$dsh->AddProgramme( {
	  start_time => $start,
	  title => $title,
	  description => $description,
	});
      }
    }
    else {
      error( "Ignoring $text" );
    }
  }

  $dsh->EndBatch( 1 );
    
  return;
}

my %months = (
              january => 1,
              february => 2,
              march => 3,
              april => 4,
              may => 5,
              june => 6,
              july => 7,
              august => 8,
              september => 9,
              october => 10,
              november => 11,
              december => 12,
              );

sub ParseDate {
  my( $text, $file ) = @_;

  my( $wday, $day, $month ) = ($text =~ /^(.*?)\s+(\d+)[stndrh]*\s+([a-z]+)\.*$/i);
  my $monthnum = $months{lc $month};

  if( not defined $monthnum ) {
    error( "$file: Unknown month '$month' in '$text'" );
    return undef;
  }
  
  my $dt = DateTime->today();
  $dt->set( month => $monthnum );
  $dt->set( day => $day );
 
  if( $dt < DateTime->today()->add( days => -180 ) ) {
    $dt->add( years => 1 );
  }

  return $dt->ymd('-');
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
