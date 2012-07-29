package SQLAbstraction::SQLite;

use strict;
use warnings;

=head1 NAME

SQLAbstraction::SQLite - Implementation of SQLAbstraction for SQLite.

=cut

use SQLAbstraction;

use base qw(SQLAbstraction);
use fields qw( filename );

use DBI;
use Carp;

sub new {
  my SQLAbstraction::SQLite $self = shift;
  my( $p, $first ) = @_;

  if( not ref $self ) {
    $self = fields::new($self);
  }
  $self->SUPER::new( $p, 1 );
  
  my @required_params = qw( filename );
  
  my %optional_params = ( );

  # Initialize new properties.
  $self->init( $p, \@required_params, \%optional_params );

  $self->check_unknown( $p, $first );

  return $self;
}

sub Connect {
  my SQLAbstraction::SQLite $self = shift;

  my $dsn = "dbi:SQLite:dbname=" . $self->{filename};
  
  $self->{dbh} = DBI->connect($dsn, "", "")
      or die "Cannot connect: " . $DBI::errstr;

  $self->{dbh}->{unicode} = 1;
  return 1;
}

sub last_inserted_id {
  my SQLAbstraction::SQLite $self = shift;

  return $self->{dbh}->func('last_insert_rowid');
}

1;

