package NonameTV::Importer::Downconverter;

#
# Import data from xmltv-format and downconvert it to create a new channel.
# Based on Timeshifter
#
# grabber_info is: original channel id, [<flag>][, <flag>]
# flag can be:
#   quality - to set or delete the quality parameter
#             -quality - delete the quality value
#             quality=HDTV - set the quality value to HDTV
#   aspect - set or delete the aspect parameter
#             -aspect - delete the aspect value
#             aspect=16:9 - set the aspect value to 16:9
#

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Compress::Zlib;

use NonameTV qw/MyGet ParseXmltv norm/;
use NonameTV::Log qw/progress error/;

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

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( undef, @flags ) = split( /,\s*/, $chd->{grabber_info} );

  my $xmldata = Compress::Zlib::memGunzip( $cref );
  my $data = ParseXmltv( \$xmldata );

  foreach my $e (@{$data})
  {
    $e->{channel_id} = $chd->{id};

    $e->{start_dt}->set_time_zone( "UTC" );
    $e->{start_time} = $e->{start_dt}->ymd('-') . " " . 
        $e->{start_dt}->hms(':');
    delete $e->{start_dt};

    $e->{stop_dt}->set_time_zone( "UTC" );
    $e->{end_time} = $e->{stop_dt}->ymd('-') . " " . 
        $e->{stop_dt}->hms(':');
    delete $e->{stop_dt};

    foreach my $flag (@flags) {
      # quality
      if( $flag eq '-quality' ) {
        delete $e->{quality};
      } elsif( $flag =~ /^quality=/ ) {
        my @flagvalue = split(/=/, $flag );
        $e->{quality} = $flagvalue[1];
      }
      # aspect
      if( $flag eq '-aspect' ) {
        delete $e->{aspect};
      } elsif( $flag =~ /^aspect=/ ) {
        my @flagvalue = split(/=/, $flag );
        $e->{aspect} = $flagvalue[1];
      }
    }

    $ds->AddProgrammeRaw( $e );
  }
  
  # Success
  return 1;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $date ) = ($batch_id =~ /_(.*)/);

  my( $org_channel ) = split( /,\s*/, $data->{grabber_info} );

  my $url = $self->{UrlRoot} . $org_channel . "_" . $date . ".xml.gz";
  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

1;
