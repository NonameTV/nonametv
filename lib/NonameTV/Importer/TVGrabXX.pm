package NonameTV::Importer::TVGrabXX;

use strict;
use warnings;

=pod

Importer for data from other XMLTV sources using tv_grab_xx grabbers.
The tv_grab_xx should be run before this importer. The output file
of the grabber should be the file: $self->{FileStore} . "/tv_grab/" . $tvgrabber . ".xml";

Use grabber_data to specify grabber and the channel.

Example: to grab RAI1 using Italian grabber tv_grab_it, the grabber_data
will look like 'tv_grab_it;www.raiuno.rai.it'

Features:

=cut

use DateTime;
use XML::LibXML;
use Encode qw/encode decode/;

use NonameTV qw/norm AddCategory ParseXmltv/;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  #defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $conf = ReadConfig();
  $self->{FileStore} = $conf->{FileStore};

  return $self;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $tvgrabber, $tvchannel ) = ( $data->{grabber_info} =~ /^(.*);(.*)$/ );
  $self->{tvgrabber} = $tvgrabber;
  $self->{tvchannel} = $tvchannel;

  my $xmlf = $self->{FileStore} . "/tv_grab/" . $tvgrabber . ".xml";

  open(XMLFILE, $xmlf);
  undef $/;
  my $content = <XMLFILE>;
  close(XMLFILE);

  return( $content, "" );
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $prog = ParseXmltv (\$$cref, $self->{tvchannel});
  foreach my $e (@{$prog}) {
    $e->{channel_id} = $chd->{id};

    # translate start end from DateTime to string
    $e->{start_dt}->set_time_zone ('UTC');
    $e->{start_time} = $e->{start_dt}->ymd('-') . " " . $e->{start_dt}->hms(':');
    delete $e->{start_dt};
    $e->{stop_dt}->set_time_zone ('UTC');
    $e->{end_time} = $e->{stop_dt}->ymd('-') . " " . $e->{stop_dt}->hms(':');
    delete $e->{stop_dt};

    # translate channel specific program_type and category to common ones
    my $pt = $e->{program_type};
    delete $e->{program_type};
    my $c = $e->{category};
    delete $e->{category};
    if( $pt ){
      my($program_type, $category ) = $ds->LookupCat( $chd->{xmltvid}, $pt );
      AddCategory( $e, $program_type, $category );
    }
    if( $c ){
      my($program_type, $category ) = $ds->LookupCat( $chd->{xmltvid}, $c );
      AddCategory( $e, $program_type, $category );
    }

    $ds->AddProgramme ($e);
  }

  # Success
  return 1;
}

1;
