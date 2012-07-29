package NonameTV::Importer::BaseDaily;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that downloads data in one 
file per day and channel. 

=cut

use DateTime;

use NonameTV::Importer::BasePeriodic;

use base 'NonameTV::Importer::BasePeriodic';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{MaxDays} = 32 unless defined $self->{MaxDays};
    $self->{MaxDaysShort} = 2 unless defined $self->{MaxDaysShort};

    return $self;
}

sub BatchPeriods { 
  my $self = shift;
  my( $shortgrab ) = @_;

  my $maxdays = $shortgrab ? $self->{MaxDaysShort} : $self->{MaxDays};

  my $start_dt = DateTime->today(time_zone => 'local');
  $start_dt = $start_dt ->subtract( days => 1 ) unless defined $self->{SkipYesterday};

  my @periods;

  for( my $days = 0; $days <= $maxdays; $days++ )
  {
    my $dt = $start_dt->clone;
    $dt=$dt->add( days => $days );

    push @periods, $dt->ymd('-');
  }

  return @periods;
}

1;
