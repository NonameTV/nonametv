package NonameTV::StringMatcher;

use strict;
use warnings;

=pod

=head1 NAME

NonameTV::StringMatcher

=head1 DESCRIPTION


  my $sm = NonameTV::StringMatcher->new();
  $sm->AddRegexp( qr/\bt.st\b/, [ 1,2 ] );

  my $res = $sm->Match( "this is a test" );
  if( defined( $res ) )
  {
    print $res->[0] . " " . $res->[1] . "\n";
  }

=head1 METHODS

=over 4

=cut

=item new

The constructor for the object. 

=cut

sub new
{
  my $class = ref( $_[0] ) || $_[0];

  my $self = { }; 
  bless $self, $class;

  return $self;
}

=item AddRegexp

Add a new regexp that all strings should be matched against.
Takes two parameters, the regexp to match against and the data
that should be returned if the match is successful.

=cut

sub AddRegexp
{
  my $self = shift;
  my( $re, $res ) = @_;

  push @{$self->{regexps}}, [$re,$res];
}

=item Match

Match a string against all regexps in the object. Returns
the result for the first regexp that matches.
Takes a single parameter, the string to match against the regexps.

Returns undef if no regexp matches.

=cut

sub Match
{
  my $self = shift;
  my( $s ) = @_;

  foreach my $r (@{$self->{regexps}})
  {
    my $re = $r->[0];
    if( $s =~ /$re/ )
    {
      return $r->[1];
    }
  }

  return undef;
}


=head1 COPYRIGHT

Copyright (C) 2004 Mattias Holmlund.

=cut

1;
