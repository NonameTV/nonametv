package SQLAbstraction::mysql;

use strict;
use warnings;

=head1 NAME

SQLAbstraction::mysql - Implementation of SQLAbstraction for mysql.

=cut

use SQLAbstraction;

use base qw(SQLAbstraction);
use fields qw( dbhost dbname dbuser dbpassword );

use Carp;

use UTF8DBI;
  
sub new {
  my SQLAbstraction::mysql $self = shift;
  my( $p, $first ) = @_;

  if( not ref $self ) {
    $self = fields::new($self);
  }
  $self->SUPER::new( $p, 1 );
  
  my @required_params = qw( dbhost dbname dbuser dbpassword );
  
  my %optional_params = ( );

  # Initialize new properties.
  $self->init( $p, \@required_params, \%optional_params );

  $self->check_unknown( $p, $first );

  return $self;
}

sub Connect {
  my SQLAbstraction::mysql $self = shift;

  my $host = $self->{dbhost};
  my $database = $self->{dbname};
  
  my $dsn = "DBI:mysql:database=$database;host=$host";
  
  $self->{dbh} = UTF8DBI->connect($dsn, $self->{dbuser}, $self->{dbpassword})
      or die "Cannot connect: " . $DBI::errstr;

  $self->{dbh}->do("set character set utf8");
  $self->{dbh}->do("set names utf8");

  return 1;
}

sub last_inserted_id {
  my SQLAbstraction::mysql $self = shift;
  
  return $self->{dbh}->{'mysql_insertid'};
}

1;

