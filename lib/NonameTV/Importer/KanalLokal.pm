package NonameTV::Importer::KanalLokal;

use strict;
use warnings;

=pod

Import data from Xml-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Text::Capitalize qw/capitalize_title/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "KanalLokal";

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  progress( "KanalLokal: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "KanalLokal $file: Failed to parse" );
    return;
  }
  
  my $ns = $doc->find( "//Event" );
  
  if( $ns->size() == 0 ) {
    error( "KanalLokal $file: No Events found." ) ;
    return;
  }

  my $batch_id;

  foreach my $div ($ns->get_nodelist) {
    my $date = norm( $div->findvalue( 'StartDate' ) );
    my $starttime = norm( $div->findvalue( 'StartTime' ) );
    my $endtime = norm( $div->findvalue( 'EndTime' ) );
    my $title = norm( $div->findvalue( 'Title1' ) );
    my $synopsis = norm( $div->findvalue( 'Synopsis1' ) );

    if( not defined( $batch_id ) ) {
      $batch_id = $xmltvid . "_" . FindWeek( $date );
      $ds->StartBatch( $batch_id );
    }

    $starttime =~ s/^(\d+:\d+).*/$1/;
    $endtime =~ s/^(\d+:\d+).*/$1/;

    my $ce = {
      channel_id => $channel_id,
      title => $title,
      description => $synopsis,
      start_time => "$date $starttime",
    };

    if( $starttime gt $endtime ) {
      $ce->{end_time} = IncreaseDate( $date ) . " $endtime";
    }
    else {
      $ce->{end_time} = "$date $endtime";
    }

    $ds->AddProgramme( $ce );
  }

  $ds->EndBatch( 1 );
    
  return;
}

sub ParseDate {
  my( $text ) = @_;

  my( $year, $month, $day ) = split( '-', $text );

  my $dt = DateTime->new(
			 year => $year,
			 month => $month,
			 day => $day );

  return $dt;
}

sub IncreaseDate {
  my( $text ) = @_;

  my $dt = ParseDate( $text );

  return $dt->add( days => 1 )->ymd( '-' );
}

sub FindWeek {
  my( $text ) = @_;

  my $dt = ParseDate( $text );

  my( $week_year, $week_num ) = $dt->week;

  return "$week_year-$week_num";
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
