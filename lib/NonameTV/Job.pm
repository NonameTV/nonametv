package NonameTV::Job;

use strict;
use warnings;

=pod

StartJob( $type, $name, $deleteafter );

EndJob( $fail );  # Fail is optional. If fail is not supplied, it is set based on whether there was any output on stderr from the job.

DeleteJob( $type, $name ); # Used to expire old jobs.

Keep the following info about a job:

type
name
starttime (datetime)
duration (int seconds)
lastok (datetime)
lastfail (datetime)
message
success (0,1)
deleteafter

type+name must be unique.

Between StartJob and EndJob, N::L::error is logged
and subsequently stored in the message field. This is true regardless
of the use of --verbose parameters. If any errors are logged,
the job is regarded as failed (success=0)

=cut

BEGIN 
{
  use Exporter   ();
  our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  
  @ISA         = qw(Exporter);
  @EXPORT      = qw( );
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
  @EXPORT_OK   = qw/StartJob EndJob/;
  
}
our @EXPORT_OK;

use NonameTV::Factory qw/CreateDataStore/;
use NonameTV::Log qw/StartLogSection EndLogSection/;

use DateTime;

my $curr = undef;

sub StartJob {
  my( $type, $name, $deleteafter ) = @_;

  die "StartJob called twice" if defined $curr;

  my $ddt = DateTime->now()->add( days => $deleteafter );

  $curr = {
    type => $type,
    name => $name,
    starttime => DateTime->now(),
    deleteafter => $ddt->ymd() . " " . $ddt->hms(),
  };
  
  StartLogSection( $name, 1 );
}

sub EndJob {
  die if not defined $curr;

  my $message = EndLogSection( $curr->{name} );
  
  delete $curr->{h};

  $curr->{success} = $message eq "";
  $curr->{message} = $message;

  my $duration = DateTime->now()->subtract_datetime_absolute(
		   $curr->{starttime} );

  $curr->{duration} = $duration->delta_seconds();
  $curr->{starttime} = $curr->{starttime}->ymd() . " " . 
      $curr->{starttime}->hms();

  if( $curr->{success} ) {
    $curr->{lastok} = $curr->{starttime};
  }
  else {
    $curr->{lastfail} = $curr->{starttime};
  }

  my $ds = CreateDataStore();

  if( $ds->sa->Update( "jobs", { type => $curr->{type}, 
				 name => $curr->{name} },
		       $curr ) != 1 ) {
    $ds->sa->Add( "jobs", $curr );
  }

  $curr = undef;
}

=pod

Notes while trying to capture STDERR

The perl-module Filter::Handle lets you define a sub that will be
called each time anything is written to stderr. Unfortunately the
Filter::Handle tests in version 0.03 of the module eats up all
available memory and dies...

The perl-module Tie::STDERR allows you to do the same thing.  See
test/tie-stderr for an example. However, Tie::STDERR will also catch
errors inside an eval, which is not desired. evals are used to try
things that may fail and still be ok, and we don't want to hear about
errors in these blocks. Sigh.

The only sane option is probably to wrap each job in an eval and catch
the output from the eval. Is this possible?

=cut

1;
