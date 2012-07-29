package NonameTV::Importer::BaseOne;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that downloads data in one 
file per channel. 

=cut

use NonameTV::Importer::BasePeriodic;

use base 'NonameTV::Importer::BasePeriodic';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    return $self;
}

sub BatchPeriods {
  my $self = shift;
  my( $shortgrab ) = @_;

  return ("all");
}

1;
