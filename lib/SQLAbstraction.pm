package SQLAbstraction;
use Carp;

use strict;
use warnings;

=head1 NAME

SQLAbstraction - Simplified interface to DBI.

=head1 SYNOPSIS


=head1 DESCRIPTION

=head2 Constructor

=cut

use fields qw/die_on_error dbh dbh_errstr/;

sub new {
  my SQLAbstraction $self = shift;
  my ( $p, $first ) = @_;

  if ( not ref $self ) {
    $self = fields::new($self);
  }

  my @required_params = qw( );
  my %optional_params = ( die_on_error => 1 );

  # Initialize new properties.
  $self->init( $p, \@required_params, \%optional_params );

  $self->check_unknown( $p, $first );
  return $self;
}

sub init {
  my SQLAbstraction $self = shift;

  my ( $p, $required, $optional ) = @_;

  foreach my $param ( keys %{$optional} ) {
    if ( exists( $p->{$param} ) ) {
      $self->{$param} = $p->{$param};
      delete( $p->{$param} );
    }
    else {
      $self->{$param} = $optional->{$param};
    }
  }

  foreach my $param ( @{$required} ) {
    if ( exists( $p->{$param} ) ) {
      $self->{$param} = $p->{$param};
      delete( $p->{$param} );
    }
    else {
      croak "Missing required parameter $param for " . ref($self);
    }
  }
}

sub check_unknown {
  my SQLAbstraction $self = shift;
  my ( $p, $first ) = @_;

  if ( not( defined($first) ) and ( scalar( %{$p} ) ) ) {
    my ($callingclass) = caller;
    croak "Unknown parameters to " . $callingclass . "::new " . join ", ",
      keys %{$p};
  }
}

sub DESTROY {
  my SQLAbstraction $self = shift;

  $self->{dbh}->disconnect()
    if defined( $self->{dbh} );
}

=head2 Methods

=over 4

=item Connect 

  $sa->Connect();

=cut

sub Connect {
  my $self = shift();

  die "You need to override Connect()";

}

=over 4

=item Count( $table, $args )

Return the number of records in table $table matching $args. $table should
be a string containing the name of a table, $args should be a hash-reference
with field-names and values.

=cut

sub Count {
  my $self = shift;
  my ( $table, $args ) = @_;

  my $dbh = $self->{dbh};

  my @where  = ("(1)");
  my @values = ();

  map { push @where, "($_ = ?)"; push @values, $args->{$_}; }
    sort keys %{$args};

  my $where = join " and ", @where;
  my $sql = "select count(*) from $table where $where";

  my $sth = $dbh->prepare($sql)
    or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  $sth->execute(@values)
    or die "Execute failed. $sql\nError: " . $dbh->errstr;

  my $aref = $sth->fetchrow_arrayref;
  my $res  = $aref->[0];
  $sth->finish;
  return $res;
}

=item Delete( $table, $args )

Delete all records in table $table matching $args. $table should
be a string containing the name of a table, $args should be a hash-reference
with field-names and values. Returns the number of deleted records.

=cut

sub Delete {
  my $self = shift;
  my ( $table, $args ) = @_;

  my $dbh = $self->{dbh};

  my @where  = ("(1)");
  my @values = ();

  map { push @where, "($_ = ?)"; push @values, $args->{$_}; }
    sort keys %{$args};

  my $where = join " and ", @where;
  my $sql = "delete from $table where $where";

  my $sth = $dbh->prepare_cached($sql)
    or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  my $res = $sth->execute(@values);
  $sth->finish;

  return $res;
}

=item Add( $table, $values, $die_on_error )

Add a new record to a table. $table should be a string containing the name 
of a table, $values should be a hash-reference with field-names and values.
$die_on_error defaults to $self->{die_on_error}.
Returns the primary key assigned to the new record or -1 if the Add failed.

=cut 

sub Add {
  my $self = shift;
  my ( $table, $args, $die_on_error ) = @_;

  $die_on_error = $self->{die_on_error} unless defined($die_on_error);

  my $dbh = $self->{dbh};

  my @fields = ();
  my @values = ();

  map { push @fields, "$_ = ?"; push @values, $args->{$_}; }
    sort keys %{$args};

  my $fields = join ", ", @fields;
  my $sql = "insert into $table set $fields";

  my $sth = $dbh->prepare_cached($sql)
    or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  $sth->{PrintError} = 0;

  if ( not $sth->execute(@values) ) {
    if ( $die_on_error ) {
      die "Execute failed. $sql\nError: " . $dbh->errstr;
    }
    else {
      $self->{dbh_errstr} = $dbh->errstr;
      $sth->finish();
      return -1;
    }
  }

  $sth->finish();

  return $self->last_inserted_id();
}

=item Update( $table, $args, $new_values )

Update all records matching $args. $table should be a string containing the name of a table, $args and $new_values should be a hash-reference with field-names and values. Returns the number of updated records.

Example:
    $ds->Update( "users", { uid => 1 }, 
		 { lastname => "Holmlund", 
		   firstname => "Mattias" } );

=cut

sub Update {
  my $self = shift;
  my ( $table, $args, $new_values ) = @_;

  my $dbh = $self->{dbh};

  my @where  = ("(1)");
  my @values = ();

  map { push @where, "($_ = ?)"; push @values, $args->{$_}; }
    sort keys %{$args};

  my $where = join " and ", @where;

  my @set       = ();
  my @setvalues = ();
  map { push @set, "$_ = ?"; push @setvalues, $new_values->{$_}; }
    sort keys %{$new_values};

  my $setexpr = join ", ", @set;

  my $sql = "UPDATE $table SET $setexpr WHERE $where";

  my $sth = $dbh->prepare($sql)
    or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  my $res = $sth->execute( @setvalues, @values )
    or die "Execute failed. $sql\nError: " . $dbh->errstr;

  $sth->finish();

  return $res;
}


sub _BuildLookup {
  my $self = shift;
  my ( $table, $args, $field, $order ) = @_;

  my $dbh = $self->{dbh};

  my @where  = ("(1)");
  my @values = ();

  map { push @where, "($_ = ?)"; push @values, $args->{$_}; }
    sort keys %{$args};

  my $where = join " and ", @where;

  my $sql;

  if ( defined $field ) {
    $sql = "SELECT $field FROM $table WHERE $where";
  }
  else {
    $sql = "SELECT * FROM $table WHERE $where";
  }

  if( defined( $order ) and ( scalar( @{$order} ) > 0 ) ) {
    $sql .= " ORDER BY " . join( ", ", @{$order} );
  }

  my $sth = $dbh->prepare_cached($sql)
    or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  my $res = $sth->execute(@values)
    or die "Execute failed. $sql\nError: " . $dbh->errstr;

  return $sth;
}

=item Lookup( $table, $args [, $field] )

Retrieve values from a record. $table should be a string containing the name 
of a table, $args should be a hash-reference with field-names and values. 
If $field is specified, it should be the name of a field in the record and
Lookup will then return the contents of that field. If $field is undef, 
a hash-reference with all fields and values in the record is returned.

If $args fails to identify one unique record, undef is returned. 

=cut

sub Lookup {
  my $self = shift;
  my ( $table, $args, $field ) = @_;

  my $sth = $self->_BuildLookup( $table, $args, $field );

  my $row = $sth->fetchrow_hashref;

  if ( not defined($row) ) {
    $sth->finish();
    return undef;
  }

  my $row2 = $sth->fetchrow_hashref;
  $sth->finish();

  die "More than one record returned from $table"
      if ( defined $row2 );

  return $row->{$field} if defined $field;
  return $row;
}

=item LookupMany( $table, $args[, $order,  $limit] )

Retrieve values from several records. $table should be a string
containing the name of a table, $args should be a hash-reference with
field-names and values.  Returns a reference to an array containing
hashrefs for each record.

$order is an arrayref containing expressions to sort on.

$limit can be used to limit the number of records returned. Defaults to
using no limit.

=cut

sub LookupMany {
  my $self = shift;
  my ( $table, $args, $order, $limit ) = @_;

  my $sth = $self->_BuildLookup( $table, $args, undef, $order );

  my $res = $sth->fetchall_arrayref( {}, $limit );

  $sth->finish();
  return $res;
}

=item LookupManySql( $sql[, $argarray] )

Lookup possibly may records using an SQL expression. $sql should be a
string that can be sent to $dbh->prepare(). $argarray can be a
reference to an array of arguments that matches $sql.

Returns a reference to an array containing hashrefs for each record.

=cut

sub LookupManySql {
  my $self = shift;
  my ( $sql, $argarray ) = @_;

  $argarray = [] if not defined $argarray;

  my $dbh = $self->{dbh};

  my $sth = $dbh->prepare_cached($sql)
    or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  my $res = $sth->execute(@{$argarray})
    or die "Execute failed. $sql\nError: " . $dbh->errstr;

  $res = $sth->fetchall_arrayref( {} );

  $sth->finish();
  return $res;
}

=item Iterate

Same as Lookup, but returns a dbi statement handle that can be used
as an iterator. Can also take several field-arguments.

=cut 

sub Iterate {
  my $self = shift;
  my ( $table, $args, @fields ) = @_;

  my $dbh = $self->{dbh};

  my @where  = ("(1)");
  my @values = ();

  map { push @where, "($_ = ?)"; push @values, $args->{$_}; }
    sort keys %{$args};

  my $where = join " and ", @where;

  my $sql;

  if ( scalar(@fields) > 0 ) {
    $sql = "SELECT " . join( ",", @fields ) . " FROM $table WHERE $where";
  }
  else {
    $sql = "SELECT * FROM $table WHERE $where";
  }

  my $sth = $dbh->prepare($sql)
    or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  my $res = $sth->execute(@values)
    or die "Execute failed. $sql\nError: " . $dbh->errstr;

  return undef if $res == 0;

  return $sth;
}

sub Sql {
  my SQLAbstraction $self = shift;
  my ( $sqlexpr, $values ) = @_;

  my $dbh = $self->{dbh};

  my $sth = $dbh->prepare($sqlexpr)
    or die "Prepare failed. $sqlexpr\nError: " . $dbh->errstr;

  my $res = $sth->execute( @{$values} )
    or die "Execute failed. $sqlexpr\nError: " . $dbh->errstr;

  return ( $res, $sth );
}

sub DoSql {
  my SQLAbstraction $self = shift;
  my ( $sqlexpr, $values ) = @_;

  my ( $res, $sth ) = $self->Sql( $sqlexpr, $values );

  $sth->finish();
}

=item errstr

Return the error message from the latest failed operation.

=cut

sub errstr {
  my $self = shift;

  return $self->{dbh}->errstr;
}

=head1 COPYRIGHT

Copyright (C) 2007 Mattias Holmlund.

=cut

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:

