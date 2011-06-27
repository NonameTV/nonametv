package NonameTV::Exporter;

use strict;
use warnings;

=head1 NAME

NonameTV::Exporter

=head1 DESCRIPTION

Abstract base-class for the NonameTV::Exporter::* classes.

A package derived from NonameTV::Exporter can be used to export
data from the NonameTV programming database to another format.

NonameTV::Exporter::*-objects are instantiated from the nonametv.conf
configuration file. To instantiate an object, add an entry
in the 'Exporters'-hash. Each entry consists of a hash with 
the package-name of the exporter in the Type-key and any other
parameters to the object in other keys.

=head1 METHODS

=over 4

=cut

=item new

The constructor for the object. Called with a hashref as the first parameter.
This is a ref to the configuration for the object from the nonametv.conf-
file. The second parameter is a NonameTV::DataStore object.

=cut

sub new
{
  my $class = ref( $_[0] ) || $_[0];

  my $self = { }; 
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key (keys(%{$_[1]}))
  {
      $self->{$key} = ($_[1])->{$key};
  }

  $self->{datastore} = $_[2];

  return $self;
}

=item Export

Export is called from the nonametv-export executable. It takes a hashref 
as a parameter. The hashref points to a hash with the command-line 
parameters decoded by Getopt::Long  using the $NonameTV::Exporter::*::Options
arrayref as format specification.

=cut

sub Export
{
  my( $self, $param ) = @_;
  
  die "You must override Export in your own class"
}

=head1 CLASS VARIABLES

=item $Options

Arrayref containing format specifications for Getopt::Long.

Example: $Options = [ qw/offset=i days=i/ ]
 
=head1 COPYRIGHT

Copyright (C) 2004 Mattias Holmlund.

=cut

1;
