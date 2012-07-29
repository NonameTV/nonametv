package NonameTV::DataStore::Updater;

use strict;
use warnings;

use Carp;
use NonameTV::Log qw/progress error/;

=head1 NAME

NonameTV::DataStore::Updater

=head1 DESCRIPTION

Update a batch

==head1 SYNOPSIS

To update a batch, i.e. modify some of the programs in a batch
without deleting all of them, do the following steps:

  StartBatchUpdate( $batch_id );
  DeleteProgramme( ... );
  AddProgramme( ... );
  EndBatchUpdate( $success, $message );

=head1 METHODS

=over 4

=cut

=item new

The constructor for the object. Called with a NonameTV::DataStore object
as a parameter. 

=cut

sub new
{
  my $class = ref( $_[0] ) || $_[0];
  
  my $self = { }; 
  bless $self, $class;
  
  $self->{ds} = $_[1];
  
  return $self;
}

sub DESTROY
{
  my $self = shift;
  
}

=item StartBatchUpdate

Called by an importer to signal the start of an update of a batch.
Takes a single parameter containing a string that uniquely identifies
a set of programmes.

Returns 1 on success and 0 on failure. Failure means that this batch does not
exist.

=cut

sub StartBatchUpdate
{
  my( $self, $batchname ) = @_;
  
  my $ds = $self->{ds};

#  print "SBU: $batchname\n";

  $ds->sa->DoSql( "START TRANSACTION" );
  my $data = $ds->sa->Lookup( 'batches', { name => $batchname } );
  if( not defined( $data->{id} ) )
  {
    error( "No such batch $batchname" );
    return 0;
  }

  my $id = $data->{id};

  $ds->SetBatch( $id, $batchname );

  $self->{currbatch} = $id;
  $self->{currbatchname} = $batchname;
  $self->{batcherror} = 0;
  $self->{oldmessage} = $data->{message};
  $self->{oldabortmessage} = $data->{abort_message};

  return 1;
}

=item EndBatchUpdate

Called by an importer to signal the end of a batch of updates.
Takes two parameters: 

An integer containing 1 if the batch was processed
successfully and 0 if the batch failed and the database should
be rolled back to the contents as they were before StartBatchUpdate was called.

A string containing a log-message to add to the batchrecord. If success==1,
then the log-message is appended to the field 'message'. If success==0, then
the log-message is appended to the field abort_message. The log-message 
can be undef.

=cut

sub EndBatchUpdate
{
  my( $self, $success, $log ) = @_;
  
#  print "EBU: $success\n";

  die "You must call StartBatchUpdate before EndBatchUpdate"
    unless exists $self->{currbatch};

  my $ds = $self->{ds};

  $log = "" if not defined $log;

  if( $success and not $self->{batcherror} )
  {
    $ds->sa->Update( 'batches', { id => $self->{currbatch} }, 
		     { last_update => time(),
		       message => $self->{oldmessage} .  "\n$log" } );

    $ds->sa->DoSql("Commit");
  }
  else
  {
    $ds->sa->DoSql("Rollback");

    $ds->sa->Update( 'batches', { id => $self->{currbatch} },
		     { abort_message => $self->{oldabortmessage} 
		       . "\n$log" } );

    error( $self->{currbatchname} . ": Rolling back changes" );
  }

  delete $self->{currbatch};
  $ds->ClearBatch();
}

=item AddProgramme

Called by an importer to add a programme for the current batch.

See NonameTV::DataStore::AddProgramme.

=cut

sub AddProgramme
{
  my $self = shift;
  my( $data ) = @_;

#  print "AP: $data->{title}\n";

  die "You must call StartBatchUpdate before AddProgramme"
    unless exists $self->{currbatch};

  return if $self->{batcherror};

  $self->{ds}->AddProgrammeRaw( $data );
}

=item DeleteProgramme

Delete a single programme from the database. Takes a hashref containing
fields and values that the programme should match. If none or more than one
program matches the hashref, DeleteProgramme die()s.

Returns the deleted record as a hashref if successful.

=cut

sub DeleteProgramme
{
  my $self = shift;
  my( $data, $ignore_batch_id ) = @_;

#  print "DP: $data->{title}\n";

  die "You must call StartBatch before DeleteProgramme"
    unless exists $self->{currbatch};
  
  $ignore_batch_id = 0
    unless defined $ignore_batch_id;
  
  $data->{batch_id} = $self->{currbatch}
    unless $ignore_batch_id;

  my $del_data = $self->{ds}->sa->Lookup( 'programs', $data );
  
  # I won't check that $del_data is defined here. If it isn't, then
  # the delete will not delete exactly one record and we'll catch it
  # there instead.

  my $del = $self->{ds}->sa->Delete( 'programs', $data );

  if( $del != 1 )
  {
    my $mess = "$del records deleted, must be 1. ";
    foreach my $key (sort keys %{$data} )
    {
      $mess .= "$key: '$data->{$key}' ";
    }
    die $self->{currbatchname} . ": $mess";
  }

  return $del_data;
}

1;
