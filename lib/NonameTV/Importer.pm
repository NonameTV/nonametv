package NonameTV::Importer;

use strict;

use File::Copy;
use IO::Scalar;
use NonameTV::Log qw/info progress error log_to_string log_to_string_result/;

=head1 NAME

NonameTV::Importer

=head1 DESCRIPTION

Abstract base-class for the NonameTV::Importer::* classes.

A package derived from NonameTV::Importer can be used to import
data from different datasources into the NonameTV programming
database.

NonameTV::Importer::*-objects are instantiated from the nonametv.conf
configuration file. To instantiate an object, add an entry
in the 'importers'-hash. Each entry consists of a hash with 
the package-name of the importer in the type-key and any other
parameters to the object in other keys.

=head1 METHODS

=over 4

=cut

=item new

The constructor for the object. Called with a hashref as the first parameter.
This is a ref to the configuration for the object from the nonametv.conf-
file. The second parameter is a NonameTV::DataStore object.

=cut

sub new {
  my $class = ref( $_[0] ) || $_[0];

  my $self = { }; 
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key (keys(%{$_[1]})) {
      $self->{$key} = ($_[1])->{$key};
  }

  $self->{datastore} = $_[2];

  return $self;
}

=item Import

Import is called from the nonametv-import executable. It takes a hashref as 
the only parameter. The hashref 
points to a hash with the command-line parameters decoded by Getopt::Long 
using the $NonameTV::Importer::*::Options arrayref as format specification.

=cut

sub Import {
  my( $self, $param ) = @_;
  
  die "You must override Import in your own class"
}

=item ImportFile

Import the content from a single file.

=cut

sub ImportFile {
  my $self = shift;
  my( $contentname, $filename, $p ) = @_;

  my $content;

  # Load data from file
  {
    local( $/ ) ;
    open( my $fh, "$filename" ) 
        or die "Failed to read from $filename: $@";
    $content = <$fh>;
  }

  return $self->ImportContent( $contentname, \$content, $p );
}

=head1 CLASS VARIABLES

=item $OptionSpec, $OptionDefaults

Format specifications and default values for Getopt::Long.

our $OptionSpec = [ qw/force-update/ ];
our %OptionDefaults = ( 
                        'force-update' => 0,
                        );

 
=head1 COPYRIGHT

Copyright (C) 2004 Mattias Holmlund.

=cut

1;
