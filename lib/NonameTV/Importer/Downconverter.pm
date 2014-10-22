package NonameTV::Importer::Downconverter;

#
# Import data from xmltv-format and downconvert it to create a new channel.
# Based on Timeshifter
#
# grabber_info is: original channel id, [<flag>][, <flag>]
# flag can be:
#   quality - to set or delete the quality parameter
#             quality - delete the quality value
#             quality=HDTV - set the quality value to HDTV
#   aspect - set or delete the aspect parameter
#             aspect - delete the aspect value
#             aspect=16:9 - set the aspect value to 16:9
#

use strict;
use warnings;

use DateTime;

use NonameTV qw/MyGet ParseXmltv norm/;
use NonameTV::Log qw/d w/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    if( defined( $self->{UrlRoot} ) ) {
      w( 'UrlRoot is deprecated as we read directly from our database now.' );
    }

    return $self;
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $orig_channel, @flags ) = split( /,\s*/, $chd->{grabber_info} );
  my( $date ) = ($batch_id =~ /_(.*)/);

  my $data = $ds->ParsePrograms( $orig_channel . '_' . $date );

  foreach my $e (@{$data})
  {
    $e->{channel_id} = $chd->{id};

    $e->{start_dt}->set_time_zone( 'UTC' );
    $e->{start_time} = $e->{start_dt}->ymd('-') . ' ' . 
        $e->{start_dt}->hms(':');
    delete $e->{start_dt};

    $e->{stop_dt}->set_time_zone( 'UTC' );
    $e->{end_time} = $e->{stop_dt}->ymd('-') . ' ' . 
        $e->{stop_dt}->hms(':');
    delete $e->{stop_dt};

    foreach my $flag (@flags) {
      # quality
      if( $flag eq 'quality' ) {
        delete $e->{quality};
      } elsif( $flag =~ /^quality=/ ) {
        my @flagvalue = split(/=/, $flag );
        $e->{quality} = $flagvalue[1];
      }
      # aspect
      elsif( $flag eq 'aspect' ) {
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
  my( $self, $batch_id, $channel_data ) = @_;
  my( $orig_channel, @flags ) = split( /,\s*/, $channel_data->{'grabber_info'} );
  my( $date ) = ($batch_id =~ /_(.*)/);
  my( $year, $month, $day ) = ($date =~ m/^(\d{4})-(\d{2})-(\d{2})$/);

  my $dt = DateTime->new( 'year' => $year, 'month' => $month, 'day' => $day, 'time_zone' => 'UTC' );

  my ($res, $sth) = $self->{datastore}->{sa}->Sql (
                  'SELECT MAX(b.last_update) AS last_update
                   FROM batches b, programs p, channels c
                   WHERE c.xmltvid = ?
                   AND c.id = p.channel_id
                   AND p.start_time >= ?
                   AND p.start_time < ?
                   AND p.batch_id=b.id;',
                  [$orig_channel, $dt->datetime(), $dt->clone()->add (days => 1)->datetime()]);

  if (!$res) {
    die $sth->errstr;
  }
  my $source_last_update;
  my $row = $sth->fetchrow_hashref;
  if (defined ($row)) {
    $source_last_update = $row->{'last_update'};
  }
  my $row2 = $sth->fetchrow_hashref;
  $sth->finish();
  if (!defined ($source_last_update)) {
    $source_last_update = 0;
  }

  my $target_last_update = $self->{datastore}->{sa}->Lookup ('batches', {'name' => $batch_id}, 'last_update');
  if (!defined ($target_last_update)) {
    $target_last_update = 0;
  }

  my $thereAreChanges;
  if ($source_last_update < $target_last_update) {
    d ('Source data last changed ' . $source_last_update . ' and target data last changed ' . $target_last_update . " => nothing to do, continuing.\n");
    $thereAreChanges = 0;
  } else {
    d ('Source data last changed ' . $source_last_update . ' and target data last changed ' . $target_last_update . " => generating target batch.\n");
    $thereAreChanges = 1;
  }

  return( '', $thereAreChanges );
}

1;
