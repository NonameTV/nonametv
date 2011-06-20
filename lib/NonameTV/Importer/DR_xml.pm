package NonameTV::Importer::DR_xml;

use strict;
use warnings;

=pod

Import data for DR in xml-format. 

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/ParseXml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  return $self;
}


sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};

  my $ds = $self->{datastore};

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse XML.";
    return 0;
  }

  my $ns = $doc->find( "//program" );

  if( $ns->size() == 0 ) {
    f "No data found";
    return 0;
  }
  
  foreach my $b ($ns->get_nodelist) {
    # Verify that there is only one program
    # Verify that there is only one pro_public.

    my $start = $b->findvalue( "pro_publish[1]/ppu_start_timestamp_announced" );
    #my $end = $b->findvalue( "pro_publish[1]/ppu_stop_timestamp_presentation_utc" );
    #      end_time => ParseDateTime( $end ),
    my $title = $b->findvalue( "pro_title" );
    my $episode = $b->findvalue( "prd_episode_number" );
    my $desc = $b->findvalue( "pro_publish[1]/ppu_description" );

    my $ce = {
      channel_id => $chd->{id},
      start_time => ParseDateTime( $start ),
      title => norm($title),
      description => norm($desc),
    };

    $ce->{episode} = ". " . ($episode-1) . " ." if $episode ne "";

    $ds->AddProgramme( $ce );
  }

  return 1;
}

# The start and end-times are in the format 2007-12-31T01:00:00
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) = 
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)$/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    second => $second,
    time_zone => "Europe/Stockholm"
      );

  $dt->set_time_zone( "UTC" );

  return $dt->ymd("-") . " " . $dt->hms(":");
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;


  my( $date ) = ( $objectname =~ /(\d+-\d+-\d+)$/ );

  my $url = sprintf( "%s%s.drxml?dato=%s",
                     $self->{UrlRoot}, $chd->{grabber_info}, 
                     $date);


  return( $url, undef );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
