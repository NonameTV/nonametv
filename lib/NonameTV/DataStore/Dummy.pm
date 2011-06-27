package NonameTV::DataStore::Dummy;

use strict;
use warnings;

use Carp;

=head1 NAME

NonameTV::DataStore::Dummy

=head1 DESCRIPTION

Dummy-interface to the datastore for NonameTV. Prints debugging
information to STDOUT. Does not touch the database for StartBatch,
AddProgramme and EndBatch. All other requests are sent to the
database unmodified.

=cut

use base 'NonameTV::DataStore';

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  return $self;
}

sub DESTROY
{
  my $self = shift;

}

sub StartBatch
{
  my( $self, $batchname ) = @_;
  
  print "StartBatch $batchname\n";
  $self->{currbatch} = $batchname;
  $self->{currbatchname} = $batchname;
  $self->{last_end} = "1970-01-01 00:00:00";
}

sub EndBatch
{
  my( $self, $success ) = @_;
  
  print "EndBatch $success\n";
  delete $self->{currbatch};
}

sub AddProgramme
{
  my( $self, $data ) = @_;

  print "AddProgramme $data->{start_time} $data->{title}\n";
  print "End: $data->{end_time}\n" if exists( $data->{end_time} );
  print "Desc: $data->{description}\n" if exists( $data->{description} );
  print "Episode: $data->{episode}\n" if exists( $data->{episode} );
                                              
  die "You must call StartBatch before AddProgramme" 
    unless exists $self->{currbatch};

  if( $self->{last_end} gt $data->{start_time} )
  {
    print STDERR $self->{currbatchname} . 
      " Starttime must be later than or equal to last endtime: " . 
      $self->{last_end} . " -> " . $data->{start_time} . "\n";
    return;
  }

  $self->{last_end} = $data->{start_time};

  if( defined( $data->{end_time} ) )
  {
    if( $data->{start_time} ge $data->{end_time} )
    {
      print STDERR $self->{currbatchname} . 
	  " Stoptime must be later than starttime: " . 
	  $data->{start_time} . " -> " . $data->{end_time} . "\n";
      return;
    }
    $self->{last_end} = $data->{end_time};
  }

  $data->{batch_id} = $self->{currbatch};

  if( defined( $data->{category} ) )
  {
    my $cat = join "++", @{$data->{category}};
    $data->{category} = $cat;
    print "Category: $data->{category}\n";
  }
  else
  {
    delete( $data->{category} );
  }
}


=head1 COPYRIGHT

Copyright (C) 2004 Mattias Holmlund.

=cut

1;
