package NonameTV::Path;

use strict;
use warnings;

=head1 NAME

NonameTV::Path - Locate different parts of the NonameTV source.

=head1 SYNOPSIS

 use NonameTV::Path;

 print NonameTV::Path::Root();

=head1 DESCRIPTION

Locates the full path to the directory where NonameTV is located.
This is done based on the location of the NonameTV::Path module.

=cut

use Cwd qw/abs_path/;

my $root;

BEGIN {
  my $pathfile = abs_path( $INC{"NonameTV/Path.pm"} );
  ( $root ) = ( $pathfile =~ m%(.*)/lib/NonameTV/Path.pm% ); 
  if( not -f "$root/lib/NonameTV/Path.pm" ) {
    print STDERR "Failed to find NonameTV installation at $root.\n";
    exit 1;
  }
}

sub Root {
  return $root;
}

sub Templates {
  return "$root/templates";
}

1;
