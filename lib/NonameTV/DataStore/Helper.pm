package NonameTV::DataStore::Helper;

use strict;
use warnings;

use Carp;
use NonameTV::Log qw/d p w f/;

=head1 NAME

NonameTV::DataStore::Helper

=head1 DESCRIPTION

Alternative interface to the datastore for NonameTV. Usable for Importers
that receive data where each programme entry does not contain a stop-time
and a date.

The typical calling-sequence is

  StartBatch

  StartDate
  AddProgramme
  AddProgramme

  StartDate
  AddProgramme
  AddProgramme

  EndBatch

=head1 METHODS

=over 4

=cut

=item new

The constructor for the object. Called with a NonameTV::DataStore object
and a timezone-string as parameters. If the timezone is omitted, 
"Europe/Stockholm" is used.

After creating the object, you can set DETECT_SEGMENTS:

    $dsh->{DETECT_SEGMENTS} = 1;

This means that the Datastore::Helper will look for programs that seem
to belong together, i.e. they have been split into two with another
program in between. The algorithm looks for two identical (same title,
description and episode) programs with another program between them.
If such programs are found, they will be marked with the last part
of the episode number as 0/2 and 1/2.

=cut

sub new
{
  my $class = ref( $_[0] ) || $_[0];
  
  my $self = { }; 
  bless $self, $class;
  
  $self->{ds} = $_[1];
  $self->{timezone} = $_[2] || "Europe/Stockholm";

  $self->{DETECT_SEGMENTS} = 0;

  return $self;
}

sub DESTROY
{
  my $self = shift;
  
}

=item StartBatch
  
Called by an importer to signal the start of a batch of updates.
Takes two parameters: one containing a string that uniquely identifies
a set of programmes (a batch_id) and the channel_id for the channel
that this data is for. The channel_id is a numeric index into the
channels-table.

=cut

sub StartBatch
{
  my $self = shift;
  my( $batch_id, $channel_id ) = @_;
  
  $self->{batch_id} = $batch_id;
  $self->{channel_id} = $channel_id;

  $self->{lasttime} = undef;
  $self->{save_ce} = undef;
  $self->{curr_date} = undef;

  $self->{programs} = [];
  $self->{ds}->StartBatch( $batch_id );
}

=item EndBatch

Called by an importer to signal the end of a batch of updates.
Takes two parameters: 

An integer containing 1 if the batch was processed
successfully, 0 if the batch failed and the database should
be rolled back to the contents as they were before StartBatch was called.
and -1 if the batch should be rolled back because it has not changed.

A string containing a log-message to add to the batchrecord. If success==1,
then the log-message is stored in the field 'message'. If success==0, then
the log-message is stored in abort_message. If success==-1, the log message
is not stored. The log-message can be undef.

=cut

sub EndBatch
{
  my( $self, $success, $log ) = @_;

  if( scalar( @{$self->{programs}} ) > 0 ) {
    $self->CommitPrograms();
  }

  $self->{ds}->EndBatch( $success, $log );
}

=item StartDate

Signal the start of a new day. Takes two parameters, a date in the
format "yyyy-mm-dd" and an optional time in the format "hh:mm".

The time is used to signal the earliest possible starttime of the
first programme of the day. If the first programme added via
AddProgramme after StartDate has a time that is earlier than the time
in StartDate, then it is assumed that the programme actually starts a
day later. E.g.:

    $dsh->StartDate( "2008-01-01", "06:00" );
    $dsh->AddProgramme( {  
      start_time => "01:45", 
      ...
    } );

The program in the example will get start-time "2008-01-02 01:45".

=cut

sub StartDate
{
  my $self = shift;
  my( $date, $time ) = @_;

  if( scalar( @{$self->{programs}} ) > 0 ) {
    $self->CommitPrograms();
  }

  d "StartDate: $date";
  my( $year, $month, $day ) = split( '-', $date );
  $self->{curr_date} = DateTime->new( 
                                      year   => $year,
                                      month  => $month,
                                      day    => $day,
                                      hour   => 0,
                                      minute => 0,
                                      second => 0,
                                      time_zone => $self->{timezone} );

  if( $self->{curr_date} < DateTime->today->subtract( days => 31 ) )
  {
    w "StartDate called with old date, " .
           $self->{curr_date}->ymd("-") . ".";
  }
  if( defined( $time ) )
  {
    $self->{lasttime} = $self->create_dt( $self->{curr_date}, $time );
  }
  else
  {
    $self->{lasttime} = undef;
  }

  $self->{programs} = [];
}

=item AddProgramme

Called by an importer to add a programme for the current batch.
Takes a single parameter containing a hashref with information
about the programme. The hashref does NOT need to contain an end_time.

  $dsh->AddProgramme( {
    start_time  => "08:00",
    title       => "Morgon-tv",
    description => "Morgon i TV-soffan",
  } );

If the start_time is less than the end_time of the last programme (or
the start_time if no end_time was specified), AddProgramme assumes that
the date should be increased by one day.

=cut

sub AddProgramme
{
  my $self = shift;
  my( $ce ) = @_;

#  print "AddProgramme: $ce->{start_time} $ce->{title}\n";

  if( not defined( $self->{curr_date} ) )
  {
    confess "Helper $self->{batch_id}: You must call StartDate before AddProgramme";
  }

  my $start_time = $self->create_dt( $self->{curr_date}, 
                                     $ce->{start_time} );
  if( defined( $self->{lasttime} ) and ($start_time < $self->{lasttime}) )
  {
    my $new_start_time;

    # Have to wrap add days => 1 in an eval, since the resulting time
    # may not exist (due to daylight savings).
    eval {
      $new_start_time = $start_time->clone()->add( days => 1 );
    };

    if( not defined $new_start_time ) {
      w "Failed to add one day to start_time, adding 24h instead.";
      $new_start_time = $start_time->clone()->add( hours => 24 );
    }

    my $dur =  $new_start_time - $self->{lasttime};
    my( $days, $hours ) = $dur->in_units( 'days', 'hours' );
    $hours += $days*24;
    if( $hours < 20 )
    {
      # By adding one day to the start_time, we ended up with a time
      # that is less than 20 hours after the lasttime. We assume that
      # this means that adding a day is the right thing to do.
      $self->{curr_date}->add( days => 1 );
      $start_time = $new_start_time;
    }
    else 
    {
      # By adding one day to the start_time, we ended up with a time
      # that is more than 20 hours after the lasttime. This probably means
      # that the start_time hasn't wrapped into a new day, but that 
      # there is something wrong with the source-data and the time actually
      # moves backwards in the schedule.
      if( not $self->{ds}->{SILENCE_END_START_OVERLAP} ) 
      {
        w "Improbable program start " . 
               $start_time->ymd . " " . $start_time->hms . " skipped";
        return;
      }
    }
  }
  $ce->{start_time} = $start_time->clone();

  $self->{lasttime} = $start_time->clone();

  if( defined( $ce->{end_time} ) )
  {
    my $stop_time = $self->create_dt( $self->{curr_date}, 
                                      $ce->{end_time} );
    if( $stop_time < $self->{lasttime} )
    {
      $stop_time->add( days => 1 );
      $self->{curr_date}->add( days => 1 );
    }
    $ce->{end_time} = $stop_time->clone();
    $self->{lasttime} = $stop_time->clone(); 
  }

  $self->AddCE( $ce );
}

sub AddCE
{
  my $self = shift;
  my( $ce ) = @_;

  $ce->{start_time}->set_time_zone( "UTC" );
  $ce->{start_time} = $ce->{start_time}->ymd('-') . " " . 
    $ce->{start_time}->hms(':');

  if( defined( $ce->{end_time} ) )
  {
    $ce->{end_time}->set_time_zone( "UTC" );
    $ce->{end_time} = $ce->{end_time}->ymd('-') . " " . 
	$ce->{end_time}->hms(':');
  }

  $ce->{channel_id} = $self->{channel_id};

  push @{$self->{programs}}, $ce;
}

sub CommitPrograms {
  my $self = shift;

  # Max Programs Between
  my $MPB = 1;

  if( $self->{DETECT_SEGMENTS} ) {
    my $p = $self->{programs};
    for( my $i=0; $i < scalar(@{$p}) - 2; $i++ ) {
      for( my $j=$i+2; $j<$i+2+$MPB && $j < scalar( @{$p} ); $j++ ) {
	if( programs_equal( $p->[$i], $p->[$j] ) ) {
#	  print "Segments found: $p->[$i]->{title}\n";
	  $p->[$i]->{episode} = defined( $p->[$i]->{episode} ) ?
	      $p->[$i]->{episode} . " 0/2" : ". . 0/2";
	  $p->[$j]->{episode} = defined( $p->[$j]->{episode} ) ?
	      $p->[$j]->{episode} . " 1/2" : ". . 1/2";
	}
      }
    }
  }

  foreach my $ce (@{$self->{programs}}) {
    $self->{ds}->AddProgramme( $ce );
  }
  
  $self->{programs} = [];
}

sub create_dt
{
  my $self = shift;
  my( $date, $time ) = @_;
  
#  print $date->ymd('-') . " $time\n";

  my $dt = $date->clone();
  
  my( $hour, $minute, $second ) = split( ":", $time );

  # Don't die for invalid times during shift to DST.
  my $res = eval {
    $dt->set( hour   => $hour,
              minute => $minute,
              );
  };

  if( not defined $res )
  {
    w $dt->ymd('-') . " $hour:$minute: $@";
    $hour++;
    w "Adjusting to $hour:$minute";
    $dt->set( hour   => $hour,
              minute => $minute,
              );
  }    
  
  return $dt;
}

sub str_eq {
  my( $s1, $s2 ) = @_;

  return 1 if (not defined($s1)) and (not defined($s2));
  return 0 if not defined( $s1 );
  return 0 if not defined( $s2 );
  return $s1 eq $s2;
}

sub programs_equal {
  my( $ce1, $ce2 ) = @_;

  return 0 unless str_eq($ce1->{title}, $ce2->{title});
  return 0 unless str_eq($ce1->{description}, $ce2->{description});
  return 0 unless str_eq($ce1->{episode}, $ce2->{episode});

  return 1;
}

1;
