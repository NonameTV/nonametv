package NonameTV::Importer::SverigesRadio;

use strict;
use warnings;

=pod

Import data from Sveriges Radio. They publish data in xmltv-format
with one file per day containing all channels.

TODO:

Make sure that all available info is included. URL to programme!

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Encode qw/encode/;

use NonameTV qw/ParseXml ParseXmltv/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  push @{$self->{OptionSpec}}, "list-channels";
  $self->{OptionDefaults}->{'list-channels'} = 0;

  return $self;
}

sub InitiateDownload {
  my $self = shift;
  my( $p ) = @_;

  if( $p->{'list-channels'} ) {
    $self->PrintChannelList();
    exit;
  }

  return undef;
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $doc = ParseXml( $cref );
  
  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  my $fdoc = XML::LibXML::Document->new( "1.0", "UTF-8" );

  my $root = $fdoc->createElement( 'tv' );
  $fdoc->setDocumentElement( $root );

#  my $ns = $doc->find( '//programme[@channel="' . $chd->{xmltvid} . '"]' );
my $ns = $doc->find( '//programme[@channel="' . $chd->{grabber_info} . '"]' );

  foreach my $node ($ns->get_nodelist()) {
    $fdoc->adoptNode( $node );
    $root->appendChild( $node );
  }
 
  # Stringify

  my $str = $fdoc->toString( 1 );
  return( \$str, undef );
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};

  my $data = ParseXmltv( $cref );

  foreach my $e (@{$data})
  {
    $e->{start_dt}->set_time_zone( "UTC" );

    $e->{stop_dt}->set_time_zone( "UTC" );

    # The stop-time for programmes is one day off if the
    # program ends on midnight.
    if( $e->{stop_dt} < $e->{start_dt} ) {
	$e->{stop_dt}->add( days => 1 );
    }

    $e->{start_time} = $e->{start_dt}->ymd('-') . " " . 
        $e->{start_dt}->hms(':');
    delete $e->{start_dt};
    $e->{end_time} = $e->{stop_dt}->ymd('-') . " " . 
        $e->{stop_dt}->hms(':');
    delete $e->{stop_dt};

    # SR uses zero-length programmes to signal the start of a
    # block of programmes.
    next if $e->{start_time} eq $e->{end_time};

    $e->{title} =~ tr/\n /  /s;

    $e->{channel_id} = $chd->{id};

    $ds->AddProgrammeRaw( $e );
  }

  return 1;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ( $objectname =~ /(\d+-\d+-\d+)$/ );
 
  my $url = sprintf( "%s%s.xml", $self->{UrlRoot}, $date );
  
  return( $url, undef );
}

sub PrintChannelList {
  my $self = shift;

  my $cc = $self->{cc};
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
      localtime(time);

  my $date = sprintf("%d-%02d-%02d", $year+1900, $mon+1, $mday );

  my( $cref, $error ) = $cc->GetUrl( $self->{UrlRoot} . $date . ".xml" );

  die "Failed to download data: $error" if not defined $cref;

  my $doc = ParseXml( $cref );

  my $channelname = {};
  my $programs = {};

  my $ns = $doc->find( "//channel" );
  foreach my $node ($ns->get_nodelist()) {
    my $id = $node->findvalue( '@id' );
    my $name = $node->findvalue( 'display-name' );

    $channelname->{$id} = $name;
  }

  foreach my $id (sort keys %{$channelname}) {
    my $count = $doc->findvalue( "count(//programme[\@channel='$id'])" );
    next if $count == 0;

    print encode( "utf-8", 
      "        '$id' => [ '$channelname->{$id}', '', 'sv', 0],\n" );
  }
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
