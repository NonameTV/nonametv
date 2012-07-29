package NonameTV::Importer::BaseWeekly;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that downloads data in one 
file per week and channel. 

=cut

use DateTime;

use NonameTV::Importer::BasePeriodic;

use base 'NonameTV::Importer::BasePeriodic';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{MaxWeeks} = 52 unless defined $self->{MaxWeeks};
    $self->{MaxWeeksShort} = 1 unless defined $self->{MaxWeeksShort};

    return $self;
}

sub BatchPeriods { 
  my $self = shift;
  my( $shortgrab ) = @_;

  my $start_dt = DateTime->today(time_zone => 'local' );

  my $maxweeks = $shortgrab ? $self->{MaxWeeksShort} : 
    $self->{MaxWeeks};

  my @periods;

  for( my $week=0; $week <= $maxweeks; $week++ ) {
    my $dt = $start_dt->clone->add( days => $week*7 );

    push @periods, $dt->week_year . '-' . $dt->week_number;
  }

  return @periods;
}

1;
