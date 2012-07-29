package NonameTV::Augmenter::Base;

use strict;
use warnings;

use utf8; # just in case, not needed here

=pod

Abstract base class for an Augmenter that enhances programs.

To implement an Augmenter deriving from Base, the following methods must
be implemented:

AugmentProgram

=cut

#use NonameTV::Config qw/ReadConfig/;

sub new {
  my $class = ref( $_[0] ) || $_[0];

  my $self = { }; 
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key (keys(%{$_[1]})) {
      $self->{$key} = ($_[1])->{$key};
  }

  $self->{datastore} = $_[2];

#    $self->{OptionSpec} = [ qw/force-update verbose+ quiet+ 
#			    short-grab remove-old clear/ ];
#    $self->{OptionDefaults} = { 
#      'force-update' => 0,
#      'verbose'      => 0,
#      'quiet'        => 0,
#      'short-grab'   => 0,
#      'remove-old'   => 0,
#      'clear'        => 0,
#    };

#    $self->{cc} = NonameTV::ContentCache->new( { 
#      basedir => $conf->{ContentCachePath} . $self->{ConfigName},
#      credentials => $conf->{ContentCacheCredentials},
#      callbackobject => $self,
#      useragent => 'Grabber from http://tv.swedb.se', 
#    } );

    return $self;
}

sub AugmentProgram {
  my $self = shift;

  my( $program, $cref, $chd ) = @_;

  die 'You must override AugmentProgram';
}

1;
