package NonameTV::DataStore::FilePrint;
# $Id: FilePrint.pm,v 1.1 2005/09/02 12:38:11 frax Exp $

use strict;
use warnings;

use IO::File;

=head1 NAME

NonameTV::DataStore::FilePrint

=head1 DESCRIPTION

Mockup-interface that just prints prints debugging information to the
file handle given to the constructor (defaults to STDOUT). Does not
tuch the database at all.

=cut

#use base 'NonameTV::DataStore';

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = { fh => (defined $_[0] ? $_[0] : new IO::File ">&STDOUT") };
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

  die "You must provide batchname!"
      unless defined $batchname;

  print { $self->{fh} } "StartBatch $batchname\n";

  $self->{currbatch} = $batchname;
  $self->{currbatchname} = $batchname;
  $self->{last_end} = "1970-01-01 00:00:00";
}

sub EndBatch
{
  my( $self, $success ) = @_;
  
  print { $self->{fh} } "EndBatch $success\n";
}

sub AddProgramme
{
  my( $self, $data ) = @_;

  print { $self->{fh} } "AddProgramme $data->{start_time} $data->{title}\n";
  print { $self->{fh} } "End: $data->{end_time}\n" if exists( $data->{end_time} );
  print { $self->{fh} } "Desc: $data->{description}\n" if exists( $data->{description} );
  print { $self->{fh} } "Episode: $data->{episode}\n" if exists( $data->{episode} );
                                              
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
    print { $self->{fh} } "Category: $data->{category}\n";
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
