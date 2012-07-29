package NonameTV::Importer::BaseMonthly;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that downloads data in one 
file per month and channel. 

=cut

use DateTime;

use NonameTV::Importer::BasePeriodic;

use base 'NonameTV::Importer::BasePeriodic';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{MaxMonths} = 12 unless defined $self->{MaxMonths};
    $self->{MaxMonthsShort} = 1 unless defined $self->{MaxMonthsShort};

    return $self;
}

sub BatchPeriods { 
  my $self = shift;
  my( $shortgrab ) = @_;

  my @periods;

  my $start_dt = DateTime->today(time_zone => 'local' );
  push @periods, $start_dt->year . '-' . $start_dt->month;

  my $maxmonths = $shortgrab ? $self->{MaxMonthsShort} : $self->{MaxMonths};

  my $dt = $start_dt->clone;

  for( my $month=0; $month <= $maxmonths; $month++ ) {
    $dt->add( months => 1 );

    push @periods, $dt->year . '-' . $dt->month;
  }

  return @periods;
}

1;
