package NonameTV::Importer::Timeshifter;

=pod

Import data from xmltv-format and timeshift it to create a new channel.
The batch $date will fetch data for $date 00:00 UTC until $date+1 00:00 UTC and
output it with the specified offset.
e.g. +24 will output $date+1 00:00 UTC to $date+2 00:00 UTC and appear one day off

=cut

use strict;
use warnings;

use DateTime;

use NonameTV qw/MyGet ParseXmltv norm/;
use NonameTV::Log qw/progress w error/;

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

  my( $orig_channel, $delta ) = split( /,\s*/, $chd->{grabber_info} );
  my( $date ) = ($batch_id =~ /_(.*)/);

  my $data = $ds->ParsePrograms( $orig_channel . '_' . $date );

  if( !defined( $data ) ) {
    w( 'no data found in source batch ' . $orig_channel . '_' . $date );
    return 1;
  }

  foreach my $e (@{$data})
  {
    $e->{start_dt}->set_time_zone( 'UTC' );
    $e->{start_dt}->add( minutes => $delta );

    $e->{stop_dt}->set_time_zone( 'UTC' );
    $e->{stop_dt}->add( minutes => $delta );
    
    $e->{start_time} = $e->{start_dt}->ymd('-') . ' ' . 
        $e->{start_dt}->hms(':');
    delete $e->{start_dt};
    $e->{end_time} = $e->{stop_dt}->ymd('-') . ' ' . 
        $e->{stop_dt}->hms(':');
    delete $e->{stop_dt};
    $e->{channel_id} = $chd->{id};
    
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
