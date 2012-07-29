package NonameTV::Importer::VOXTV;

#
# Import data from www.voxtv.hr in xmltv-format
#

use strict;
use warnings;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet ParseXmltv norm/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $ds = $self->{datastore};

  my $data = ParseXmltv( $cref );

  foreach my $e (@{$data})
  {
    $e->{channel_id} = $chd->{id};

    next if( ! $e->{start_dt} );
    $e->{start_dt}->set_time_zone( "UTC" );
    $e->{start_time} = $e->{start_dt}->ymd('-') . " " . 
        $e->{start_dt}->hms(':');
    delete $e->{start_dt};

    next if( ! $e->{stop_dt} );
    $e->{stop_dt}->set_time_zone( "UTC" );
    $e->{end_time} = $e->{stop_dt}->ymd('-') . " " . 
        $e->{stop_dt}->hms(':');
    delete $e->{stop_dt};

    progress("VOXTV: $chd->{xmltvid}: $e->{start_time} - $e->{title}");

    $ds->AddProgrammeRaw( $e );
  }
  
  # Success
  return 1;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my $url = $self->{UrlRoot};

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

1;
